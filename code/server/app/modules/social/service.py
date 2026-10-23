import re
from datetime import timedelta
from sqlalchemy import and_, or_, select
from app.core.clock import as_utc, utcnow
from app.core.config import settings
from app.core.exceptions import AppError, Forbidden, NotFound
from app.core.idempotency import ensure_same_payload
from app.core.responses import public
from app.db.session import transaction
from app.modules.social.models import (
    Friendship,
    PlayerBlock,
    Gift,
    Trade,
    DirectMessage,
    PlayerReport,
)
from app.modules.social.community_models import (
    GiftWishlistAllocation,
    WishlistEntry,
)
from app.modules.social.farm_visiting import FarmVisitService
from app.modules.social.repository import SocialRepository
from app.modules.players.models import Player
from app.modules.players.repository import PlayerRepository
from app.modules.profile.models import PlayerProfile
from app.modules.housing.models import PlayerHouse
from app.modules.economy.models import PlayerExperience
from app.modules.inventory.service import InventoryService
from app.modules.notifications.service import NotificationsService
from app.modules.realtime.models import Presence
from app.modules.world.access import resolve
from app.modules.world.service import WorldService
from app.modules.social.community import CommunityService, bump_social


def filter_message(body):
    # Deliberately small configurable baseline; not an ML moderation guarantee.
    terms = [
        re.escape(w.strip())
        for w in settings.chat_blocked_words.split(",")
        if w.strip()
    ]
    return (
        re.sub(
            r"\b(" + "|".join(terms) + r")\b",
            lambda m: "*" * len(m[0]),
            body,
            flags=re.I,
        )
        if terms
        else body
    )


class SocialService:
    def __init__(self, db):
        self.db, self.repo = db, SocialRepository(db)
        self.players, self.inventory = PlayerRepository(db), InventoryService(db)
        self.alerts = NotificationsService(db)

    def online_ids(self, ids):
        return set(self.db.scalars(select(Presence.player_id).where(
            Presence.player_id.in_(ids),
            Presence.updated_at > utcnow() - timedelta(seconds=settings.presence_ttl_seconds),
        )))

    def pair(self, a, b):
        if a == b:
            raise AppError("SELF_INTERACTION", "Cannot target yourself")
        return tuple(sorted((a, b)))

    def blocked(self, a, b):
        return (
            self.db.scalar(
                select(PlayerBlock.player_id).where(
                    or_(
                        and_(PlayerBlock.player_id == a, PlayerBlock.blocked_id == b),
                        and_(PlayerBlock.player_id == b, PlayerBlock.blocked_id == a),
                    )
                )
            )
            is not None
        )

    def allowed(self, a, b, friends=True):
        key = self.pair(a, b)
        target = self.players.get(b)
        if target is None or not target.is_active or not target.email_verified:
            raise NotFound("Player not found")
        if self.blocked(a, b):
            raise Forbidden("Interaction is blocked")
        row = self.repo.get(Friendship, key, False)
        if friends and (row is None or row.status != "accepted"):
            raise Forbidden("This action requires an accepted friendship")
        return row

    def request(self, player_id, target):
        with transaction(self.db):
            self.players.lock(player_id, target)
            old = self.allowed(player_id, target, False)
            if old:
                raise AppError(
                    "FRIENDSHIP_EXISTS", "Friendship or request already exists", 409
                )
            low, high = self.pair(player_id, target)
            row = self.repo.add(
                Friendship, low_id=low, high_id=high, requested_by=player_id
            )
            self.alerts.emit(
                target,
                "friend_request",
                "You have a new friend request",
                "/social/requests",
            )
            bump_social(self.db, player_id, target)
        return public(row)

    def respond(self, player_id, target, action):
        with transaction(self.db):
            self.players.lock(player_id, target)
            row = self.allowed(player_id, target, False)
            if not row:
                raise NotFound("Friend request not found")
            if action in ("accept", "decline"):
                if row.status != "pending" or row.requested_by == player_id:
                    raise Forbidden(
                        "Only the recipient can respond to a pending request"
                    )
                if action == "accept":
                    row.status = "accepted"
                else:
                    self.db.delete(row)
            else:
                self.db.delete(row)
            bump_social(self.db, player_id, target)
        return {"action": action}

    def block(self, player_id, target, unblock=False):
        with transaction(self.db):
            self.players.lock(player_id, target)
            self.pair(player_id, target)
            self.repo.get(Player, target)
            row = self.repo.get(PlayerBlock, (player_id, target), False)
            if unblock:
                if row:
                    self.db.delete(row)
            elif row is None:
                self.repo.add(PlayerBlock, player_id=player_id, blocked_id=target)
                friendship = self.repo.get(
                    Friendship, self.pair(player_id, target), False
                )
                if friendship:
                    self.db.delete(friendship)
            bump_social(self.db, player_id, target)
        return {"blocked": not unblock}

    def search(self, player_id, query, limit=20):
        blocked = (
            select(PlayerBlock.blocked_id)
            .where(PlayerBlock.player_id == player_id)
            .union(
                select(PlayerBlock.player_id).where(PlayerBlock.blocked_id == player_id)
            )
        )
        rows = self.db.execute(
            select(Player, PlayerProfile)
            .outerjoin(PlayerProfile, PlayerProfile.player_id == Player.id)
            .where(
                Player.id != player_id,
                Player.is_active.is_(True),
                Player.email_verified.is_(True),
                Player.id.not_in(blocked),
                Player.username.startswith(query, autoescape=True),
            )
            .order_by(Player.username)
            .limit(limit)
        ).all()
        online = self.online_ids([p.id for p, _ in rows])
        return [
            {
                "id": p.id,
                "username": p.username,
                "display_name": p.display_name,
                "online": p.id in online,
                "character_code": s.character_code if s else None,
            }
            for p, s in rows
        ]

    def friends(self, player_id, pending=False):
        links = self.repo.list(
            Friendship,
            or_(Friendship.low_id == player_id, Friendship.high_id == player_id),
            Friendship.status == ("pending" if pending else "accepted"),
            limit=200,
        )
        ids = [r.high_id if r.low_id == player_id else r.low_id for r in links]
        rows = self.db.execute(
            select(Player, PlayerProfile, PlayerHouse, PlayerExperience)
            .outerjoin(PlayerProfile, PlayerProfile.player_id == Player.id)
            .outerjoin(PlayerHouse, PlayerHouse.player_id == Player.id)
            .outerjoin(PlayerExperience, PlayerExperience.player_id == Player.id)
            .where(Player.id.in_(ids))
        ).all()
        online = self.online_ids(ids)
        data = {
            p.id: {
                "id": p.id,
                "username": p.username,
                "display_name": p.display_name,
                "status_message": s.status_message if s else "",
                "last_online": s.last_seen_at if s else None,
                "online": p.id in online,
                "character_code": s.character_code if s else None,
                "house_tier": h.tier if h else 1,
                "level": x.level if x else 1,
            }
            for p, s, h, x in rows
        }
        return [
            {
                **data[r.high_id if r.low_id == player_id else r.low_id],
                "requested_by": r.requested_by,
            }
            for r in links
        ]

    def gift(self, player_id, request):
        with transaction(self.db):
            self.players.lock(player_id, request.target_id)
            old = self.db.scalar(
                select(Gift).where(
                    Gift.sender_id == player_id, Gift.request_id == request.request_id
                )
            )
            if old:
                allocation = self.db.get(GiftWishlistAllocation, old.id)
                old_link = (allocation.entry_id, allocation.expected_version) if allocation else (None, None)
                if old_link != (request.wishlist_entry_id, request.wishlist_version):
                    raise AppError("IDEMPOTENCY_CONFLICT", "Request ID reused with different wishlist", 409)
                ensure_same_payload(
                    old,
                    {
                        "receiver_id": request.target_id,
                        "item_code": request.item_code,
                        "quantity": request.quantity,
                    },
                    "Request ID reused with different gift",
                )
                return public(old)
            self.allowed(player_id, request.target_id)
            if not self.inventory.definition(request.item_code).giftable:
                raise Forbidden("Item is not giftable")
            entry = CommunityService(self.db).reserve(player_id, request)
            self.inventory.remove_internal(
                player_id, request.item_code, request.quantity
            )
            row = self.repo.add(
                Gift,
                sender_id=player_id,
                receiver_id=request.target_id,
                request_id=request.request_id,
                item_code=request.item_code,
                quantity=request.quantity,
            )
            if entry is not None:
                self.db.add(GiftWishlistAllocation(gift_id=row.id, entry_id=entry.id, expected_version=request.wishlist_version))
            bump_social(self.db, player_id, request.target_id)
            self.alerts.emit(
                request.target_id,
                "gift",
                "A gift is waiting in your mailbox",
                "/social/gifts",
            )
        return public(row)

    def claim_gift(self, player_id, gift_id):
        with transaction(self.db):
            row = self.repo.get(Gift, gift_id)
            if row.receiver_id != player_id:
                raise NotFound()
            self.players.lock(player_id, row.sender_id)
            row = self.db.get(Gift, gift_id, populate_existing=True)
            if row.claimed:
                raise AppError("ALREADY_CLAIMED", "Gift already claimed", 409)
            if self.blocked(player_id, row.sender_id):
                raise Forbidden("Interaction is blocked")
            self.inventory.add_internal(player_id, row.item_code, row.quantity)
            row.claimed = True
            allocation = self.db.get(GiftWishlistAllocation, gift_id)
            if allocation:
                entry = self.db.get(
                    WishlistEntry, allocation.entry_id, populate_existing=True
                )
                entry.version += 1
            bump_social(self.db, player_id, row.sender_id)
        return public(row)

    def propose(self, player_id, request):
        with transaction(self.db):
            self.players.lock(player_id, request.target_id)
            old = self.db.scalar(
                select(Trade).where(
                    Trade.sender_id == player_id, Trade.request_id == request.request_id
                )
            )
            values = dict(
                receiver_id=request.target_id,
                offered_code=request.offered_code,
                offered_quantity=request.offered_quantity,
                wanted_code=request.wanted_code,
                wanted_quantity=request.wanted_quantity,
            )
            if old:
                ensure_same_payload(
                    old, values, "Request ID reused with different trade"
                )
                return public(old)
            self.allowed(player_id, request.target_id)
            for code in (request.offered_code, request.wanted_code):
                if not self.inventory.definition(code).tradable:
                    raise Forbidden("Item is not tradable")
            if not self.inventory.has_item(
                player_id, request.offered_code, request.offered_quantity
            ):
                raise AppError(
                    "INSUFFICIENT_INVENTORY", "Offered items are not available"
                )
            row = self.repo.add(
                Trade, sender_id=player_id, request_id=request.request_id, **values
            )
            self.alerts.emit(
                request.target_id,
                "trade",
                "A new trade proposal is waiting",
                "/social/trades",
            )
        return public(row)

    def trade_action(self, player_id, trade_id, action):
        with transaction(self.db):
            row = self.repo.get(Trade, trade_id)
            if player_id not in (row.sender_id, row.receiver_id):
                raise NotFound()
            self.players.lock(row.sender_id, row.receiver_id)
            row = self.repo.get(Trade, trade_id)
            if row.status != "pending":
                raise AppError("TRADE_CLOSED", "Trade is no longer pending", 409)
            if (action == "cancel" and player_id != row.sender_id) or (
                action != "cancel" and player_id != row.receiver_id
            ):
                raise Forbidden()
            if action == "accept":
                self.allowed(row.sender_id, row.receiver_id)
                for code in (row.offered_code, row.wanted_code):
                    if not self.inventory.definition(code).tradable:
                        raise Forbidden("Item is not tradable")
                self.inventory.remove_internal(
                    row.sender_id, row.offered_code, row.offered_quantity
                )
                self.inventory.remove_internal(
                    row.receiver_id, row.wanted_code, row.wanted_quantity
                )
                self.inventory.add_internal(
                    row.receiver_id, row.offered_code, row.offered_quantity
                )
                self.inventory.add_internal(
                    row.sender_id, row.wanted_code, row.wanted_quantity
                )
            row.status = {
                "accept": "accepted",
                "decline": "declined",
                "cancel": "cancelled",
            }[action]
            self.alerts.emit(
                row.sender_id, "trade", f"Trade {row.status}", "/social/trades"
            )
        return public(row)

    def visit(self, player_id, target):
        """Deprecated one-shot lookup retained for existing clients.

        It only resolves the world id and read-only flag; it does not create a
        visit session, so it grants no entry. New clients use the invitation
        lifecycle in ``FarmVisitService``.
        """
        with transaction(self.db):
            self.players.lock(player_id, target)
            self.allowed(player_id, target)
            world = WorldService(self.db).own_world(target)
            self.alerts.emit(
                target, "visit", "A friend is visiting your farm", f"/world/{world.id}"
            )
            result = {"world_id": world.id, "owner_id": target, "read_only": True}
        return result

    def invite(self, player_id, target):
        return FarmVisitService(self.db).invite(player_id, target)

    def accept_invite(self, player_id, invite_id):
        return FarmVisitService(self.db).accept(player_id, invite_id)

    def message(self, player_id, request):
        with transaction(self.db):
            self.players.lock(player_id, request.target_id)
            self.allowed(player_id, request.target_id)
            last = self.repo.list(
                DirectMessage,
                DirectMessage.sender_id == player_id,
                order=DirectMessage.id.desc(),
                limit=1,
            )
            if last and (utcnow() - as_utc(last[0].created_at)).total_seconds() < 1:
                raise AppError(
                    "CHAT_COOLDOWN", "Please wait before sending another message", 429
                )
            row = self.repo.add(
                DirectMessage,
                sender_id=player_id,
                receiver_id=request.target_id,
                body=filter_message(request.body),
            )
        return public(row)

    def messages(self, player_id, target, after=0):
        self.allowed(player_id, target)
        return [
            public(r)
            for r in self.repo.list(
                DirectMessage,
                DirectMessage.id > after,
                or_(
                    and_(
                        DirectMessage.sender_id == player_id,
                        DirectMessage.receiver_id == target,
                    ),
                    and_(
                        DirectMessage.sender_id == target,
                        DirectMessage.receiver_id == player_id,
                    ),
                ),
                order=DirectMessage.id,
            )
        ]

    def report(self, player_id, request):
        with transaction(self.db):
            self.players.lock(player_id)
            self.pair(player_id, request.target_id)
            self.repo.get(Player, request.target_id)
            row = self.repo.add(
                PlayerReport,
                reporter_id=player_id,
                reported_id=request.target_id,
                reason=request.reason,
                details=request.details,
            )
        return {"report_id": row.id}

    def inbox(self, player_id, before=None):
        return [public(r) for r in self.repo.inbox(player_id, before)]

    def trades(self, player_id):
        return [public(r) for r in self.repo.trades(player_id)]

    def invites(self, player_id):
        return FarmVisitService(self.db).inbox(player_id)

    def blocks(self, player_id):
        return [public(r) for r in self.repo.blocks(player_id)]

    def farm(self, player_id, target):
        """Read-only view of another player's farm.

        Requires an ACTIVE visit session to that host, not just friendship: a
        player only sees a farm they were actually admitted to.
        """
        # Deferred: farming imports the realtime service for campus presence, and
        # realtime imports this module for message filtering.
        from app.modules.farming.service import FarmingService

        session = resolve(self.db, player_id)
        if not session.is_visitor or session.host_player_id != target:
            raise Forbidden("Accept a farm invitation before viewing this farm")
        return FarmingService(self.db).list_world(player_id, session.current_world_id)
