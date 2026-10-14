from sqlalchemy import delete
from app.core.clock import utcnow
from app.core.exceptions import AppError, Forbidden
from app.core.responses import public
from app.db.session import transaction
from app.modules.profile.models import PlayerProfile, EncounterHint, Feedback
from app.db.repository import Repository
from app.modules.players.models import Player
from app.modules.players.repository import PlayerRepository
from app.modules.pets.models import PlayerPet
from app.modules.housing.models import PlayerHouse
from app.modules.auth import oauth
from app.modules.auth.security import verify_password


class ProfileService:
    def __init__(self, db):
        self.db, self.repo = db, Repository(db)

    def initialize(self, player_id):
        # Same transaction as signup; backfill old accounts in migration.
        for model in (PlayerProfile, PlayerHouse):
            if self.repo.get(model, player_id, False) is None:
                self.repo.add(model, player_id=player_id)

    def get(self, player_id):
        row = self.repo.get(PlayerProfile, player_id)
        player = self.repo.get(Player, player_id)
        return {
            **public(row),
            "display_name": player.display_name,
            "username": player.username,
            "joined_at": player.created_at,
        }

    def update(self, player_id, request):
        with transaction(self.db):
            player = PlayerRepository(self.db).lock(player_id)[0]
            row = self.repo.get(PlayerProfile, player_id)
            for key, value in request.model_dump(exclude_unset=True).items():
                if key == "display_name":
                    player.display_name = value
                else:
                    setattr(row, key, value)
            if (
                row.character_code
                and self.repo.get(PlayerPet, player_id, False) is None
            ):
                self.repo.add(PlayerPet, player_id=player_id)
            row.last_saved_at = utcnow()
        return self.get(player_id)

    def heartbeat(self, player_id):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            row = self.repo.get(PlayerProfile, player_id)
            row.last_seen_at = row.last_saved_at = utcnow()
        return {"saved_at": row.last_saved_at}

    def tutorial(self, player_id, request):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            row = self.repo.get(PlayerProfile, player_id)
            if request.skip:
                row.tutorial_step = 3
            elif request.expected_step != row.tutorial_step:
                raise AppError("STALE_STEP", "Tutorial step has changed", 409)
            else:
                row.tutorial_step = min(3, row.tutorial_step + 1)
        return {"step": row.tutorial_step, "completed": row.tutorial_step == 3}

    def hint(self, player_id, feature):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            old = self.repo.get(EncounterHint, (player_id, feature), False)
            if old is None:
                self.repo.add(EncounterHint, player_id=player_id, feature=feature)
        return {"show_hint": old is None}

    def feedback(self, player_id, message):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            row = self.repo.add(Feedback, player_id=player_id, message=message)
        return {"id": row.id}

    def delete_account(self, player_id, request):
        with transaction(self.db):
            player = PlayerRepository(self.db).lock(player_id)[0]
            if request.confirm_username != player.username:
                raise AppError(
                    "CONFIRMATION_REQUIRED", "Type your username to confirm deletion"
                )
            if player.hashed_password:
                if not request.password or not verify_password(
                    request.password, player.hashed_password
                ):
                    raise Forbidden("Password is incorrect")
            else:
                if not request.google_id_token:
                    raise Forbidden("Reauthenticate with Google to delete this account")
                identity = oauth.verify_google(request.google_id_token)
                if (
                    player.oauth_provider != "google"
                    or identity.subject != player.oauth_provider_id
                ):
                    raise Forbidden("Google identity does not match this account")
            # Deletion takes no locks on other players, so reciprocal operations serialize.
            self.db.execute(delete(Player).where(Player.id == player_id))
        return {"deleted": True}
