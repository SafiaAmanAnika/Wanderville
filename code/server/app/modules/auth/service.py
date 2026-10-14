import re
from datetime import timedelta

from sqlalchemy.exc import IntegrityError

from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.core.exceptions import AppError, Forbidden, InvalidToken
from app.db.session import transaction
from app.modules.auth import email, oauth, security
from app.modules.auth.repository import AuthRepository
from app.modules.auth.schemas import LoginResponse, TokenResponse
from app.modules.economy.repository import EconomyRepository
from app.modules.economy.service import EconomyService
from app.modules.players.repository import PlayerRepository
from app.modules.players.schemas import PlayerPublic
from app.modules.profile.models import PlayerProfile
from app.modules.profile.service import ProfileService
from app.modules.progression.service import ProgressionService
from app.modules.realtime.service import RealtimeService
from app.modules.world.repository import WorldRepository

_DUMMY_HASH = security.hasher.hash("TimingOnly-password-123!")


class AuthService:
    def __init__(self, db):
        self.db, self.repo, self.players = db, AuthRepository(db), PlayerRepository(db)

    def _initialize_player(self, player):
        WorldRepository(self.db).create(player.id)
        EconomyRepository(self.db).create(player.id)
        ProfileService(self.db).initialize(player.id)
        if settings.starting_aura:
            EconomyService(self.db).change_internal(
                player.id, settings.starting_aura, True, "starting_balance"
            )

    def _account_token(self, player_id, kind, now):
        raw = security.new_token()
        minutes = (
            settings.email_verification_expire_minutes
            if kind == "email_verification"
            else settings.password_reset_expire_minutes
        )
        self.repo.invalidate_accounts(player_id, kind, now)
        self.repo.add_account(
            player_id=player_id,
            token_hash=security.hash_token(raw),
            token_type=kind,
            expires_at=now + timedelta(minutes=minutes),
        )
        return raw

    def _refresh_token(self, player_id, now):
        raw = security.new_token()
        self.repo.add_refresh(
            player_id=player_id,
            token_hash=security.hash_token(raw),
            expires_at=now + timedelta(days=settings.refresh_token_expire_days),
        )
        return raw

    def _login_result(self, player, now, ip):
        ProgressionService(self.db).login(player.id, now)
        profile = self.db.get(PlayerProfile, player.id)
        if profile:
            profile.last_seen_at = now
        player.last_login_at, player.last_login_ip = now, ip
        player.failed_login_attempts, player.locked_until = 0, None
        refresh = self._refresh_token(player.id, now)
        return LoginResponse(
            access_token=security.create_access_token(player.id, player.token_version),
            refresh_token=refresh,
            player=PlayerPublic.model_validate(player),
        )

    @staticmethod
    def _active(player):
        if not player.is_active:
            raise AppError("INACTIVE_ACCOUNT", "Account is inactive", 403)
        if not player.email_verified:
            raise AppError(
                "EMAIL_NOT_VERIFIED", "Please verify your email before logging in", 403
            )

    def signup(self, request):
        now = utcnow()
        try:
            with transaction(self.db):
                if self.players.by_username(request.username):
                    raise AppError("USERNAME_TAKEN", "This username is already taken")
                if self.players.by_email(request.email):
                    raise AppError("EMAIL_TAKEN", "This email is already registered")
                player = self.players.create(
                    username=request.username,
                    email=request.email,
                    hashed_password=security.hash_password(request.password),
                    display_name=request.display_name or request.username,
                    is_active=True,
                    email_verified=False,
                )
                self._initialize_player(player)
                raw = self._account_token(player.id, "email_verification", now)
                result = PlayerPublic.model_validate(player)
        except IntegrityError as exc:
            raise AppError(
                "ACCOUNT_EXISTS", "Username or email is already registered", 409
            ) from exc
        if not email.deliver_safely(player.email, player.username, raw, "email_verification"):
            raise AppError("EMAIL_DELIVERY_FAILED", "Your account was created, but the verification email could not be delivered. Ask the server owner to check the mail provider settings, then use Resend Verification.", 503)
        return result

    def login(self, request, ip=None):
        now, failed = utcnow(), False
        with transaction(self.db):
            player = self.players.by_username(request.username)
            if player is None:
                security.verify_password(request.password, _DUMMY_HASH)
                raise AppError(
                    "INVALID_CREDENTIALS", "Invalid username or password", 401
                )
            self.players.lock(player.id)
            if player.locked_until and as_utc(player.locked_until) > now:
                raise AppError(
                    "ACCOUNT_internal",
                    "Account is temporarily locked. Try again later.",
                    423,
                )
            if player.locked_until:
                player.failed_login_attempts, player.locked_until = 0, None
            if not security.verify_password(request.password, player.hashed_password):
                if not player.hashed_password:
                    security.verify_password(request.password, _DUMMY_HASH)
                player.failed_login_attempts += 1
                if player.failed_login_attempts >= settings.max_login_attempts:
                    player.locked_until = now + timedelta(
                        minutes=settings.lockout_minutes
                    )
                failed = True
            else:
                self._active(player)
                result = self._login_result(player, now, ip)
        # Failed-attempt persistence is itself a complete transaction.
        if failed:
            raise AppError("INVALID_CREDENTIALS", "Invalid username or password", 401)
        return result

    def authenticate(self, raw):
        player_id, version = security.decode_access_token(raw)
        player = self.players.get(player_id)
        if player is None or player.token_version != version:
            raise InvalidToken()
        self._active(player)
        return player

    def refresh(self, raw):
        now, hashed = utcnow(), security.hash_token(raw)
        with transaction(self.db):
            row = self.repo.refresh(hashed)
            if row is None:
                raise InvalidToken()
            locked = self.players.lock(row.player_id)
            if not locked:
                raise InvalidToken()
            player = locked[0]
            row = self.repo.refresh(hashed, lock=True)
            if row.revoked_at:
                raise AppError(
                    "REVOKED_REFRESH_TOKEN", "Refresh token was revoked", 401
                )
            if as_utc(row.expires_at) <= now:
                raise AppError("EXPIRED_REFRESH_TOKEN", "Refresh token expired", 401)
            self._active(player)
            row.revoked_at = now
            fresh = self._refresh_token(player.id, now)
            result = TokenResponse(
                access_token=security.create_access_token(
                    player.id, player.token_version
                ),
                refresh_token=fresh,
            )
        return result

    def logout(self, raw):
        player_id = None
        # One action, one boundary: revoking the refresh token and releasing the
        # player's presence/visitor slots commit together, so a failure cannot
        # leave a live session with a revoked token or the reverse.
        with transaction(self.db):
            hashed = security.hash_token(raw)
            row = self.repo.refresh(hashed)
            if row:
                self.players.lock(row.player_id)
                row = self.repo.refresh(hashed, lock=True)
                row.revoked_at = row.revoked_at or utcnow()
                player_id = row.player_id
            if player_id is not None:
                # Signing out is an intentional departure, so release presence and
                # any held visitor slots now instead of waiting for the socket to
                # drop.
                RealtimeService(self.db).leave_internal(player_id)

    def _internal_account_token(self, raw, kind, now):
        hashed = security.hash_token(raw)
        row = self.repo.account(hashed, kind)
        if row is None:
            raise AppError("INVALID_TOKEN", "Invalid account token")
        if not self.players.lock(row.player_id):
            raise InvalidToken()
        row = self.repo.account(hashed, kind, lock=True)
        if row is None or row.used_at:
            # The client shows a dedicated "already verified" screen for a spent
            # verification link, and "invalid link" for a spent reset link.
            spent = self.players.get(row.player_id) if row is not None else None
            if (
                kind == "email_verification"
                and spent is not None
                and spent.email_verified
            ):
                raise AppError(
                    "ALREADY_VERIFIED",
                    "Your email is already verified. You can log in.",
                )
            raise AppError("INVALID_TOKEN", "This account token has already been used")
        if as_utc(row.expires_at) <= now:
            raise AppError(
                "TOKEN_EXPIRED",
                "This account token has expired. Please request a new one.",
            )
        return row, self.players.get(row.player_id)

    def verify_email(self, raw):
        now = utcnow()
        with transaction(self.db):
            row, player = self._internal_account_token(raw, "email_verification", now)
            if not player.is_active:
                raise Forbidden("Account is inactive")
            row.used_at = now
            player.email_verified = True
            self.db.flush()
            result = PlayerPublic.model_validate(player)
        return result

    def request_email(self, address, kind):
        delivery = None
        with transaction(self.db):
            player = self.players.by_email(address.lower())
            if player:
                self.players.lock(player.id)
                allowed = player.is_active and (
                    (kind == "email_verification" and not player.email_verified)
                    or (
                        kind == "password_reset"
                        and player.email_verified
                        and player.hashed_password
                    )
                )
                if allowed:
                    raw = self._account_token(player.id, kind, utcnow())
                    delivery = (player.email, player.username, raw, kind)
        if delivery:
            email.deliver_safely(*delivery)

    def _change_credentials(self, player, password, now):
        player.hashed_password = security.hash_password(password)
        player.failed_login_attempts, player.locked_until = 0, None
        player.token_version += 1
        self.repo.revoke_all(player.id, now)
        self.repo.invalidate_accounts(player.id, None, now)

    def reset_password(self, request):
        now = utcnow()
        with transaction(self.db):
            row, player = self._internal_account_token(
                request.token, "password_reset", now
            )
            self._active(player)
            row.used_at = now
            self._change_credentials(player, request.new_password, now)

    def change_password(self, player_id, request):
        with transaction(self.db):
            player = self.players.lock(player_id)[0]
            if not security.verify_password(
                request.current_password, player.hashed_password
            ):
                raise AppError("INVALID_PASSWORD", "Current password is incorrect", 401)
            self._change_credentials(player, request.new_password, utcnow())

    def google_login(self, raw, ip=None, nonce=None):
        identity = oauth.verify_google(raw) if nonce is None else oauth.verify_google(raw, nonce)
        now = utcnow()
        try:
            with transaction(self.db):
                player = self.players.by_oauth("google", identity.subject)
                if player is None:
                    player = self.players.by_email(identity.email)
                    if player and (
                        not identity.authoritative_email
                        or (
                            player.oauth_provider
                            and player.oauth_provider_id != identity.subject
                        )
                    ):
                        raise AppError(
                            "ACCOUNT_LINK_REQUIRED",
                            "Sign in with your existing account to link this identity",
                            409,
                        )
                if player:
                    self.players.lock(player.id)
                    if not player.is_active:
                        raise Forbidden("Account is inactive")
                    if (
                        player.oauth_provider_id
                        and player.oauth_provider_id != identity.subject
                    ):
                        raise Forbidden("Google account does not match")
                    player.oauth_provider, player.oauth_provider_id = (
                        "google",
                        identity.subject,
                    )
                    player.email_verified = True
                    self.repo.invalidate_accounts(player.id, "email_verification", now)
                else:
                    base = re.sub(r"[^a-zA-Z0-9_-]", "", identity.email.split("@")[0])[
                        :24
                    ]
                    base = base if len(base) >= 3 else "player"
                    candidate, counter = base, 0
                    while self.players.by_username(candidate):
                        counter += 1
                        candidate = f"{base}{counter}"
                    player = self.players.create(
                        username=candidate,
                        email=identity.email,
                        hashed_password=None,
                        display_name=identity.name or candidate,
                        is_active=True,
                        email_verified=True,
                        oauth_provider="google",
                        oauth_provider_id=identity.subject,
                        avatar_url=identity.picture[:512] if identity.picture else None,
                    )
                    self._initialize_player(player)
                result = self._login_result(player, now, ip)
        except IntegrityError as exc:
            raise AppError(
                "ACCOUNT_CONFLICT", "Account changed concurrently; retry sign-in", 409
            ) from exc
        return result
