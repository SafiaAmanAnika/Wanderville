from sqlalchemy import select, func
from app.core.exceptions import AppError, Forbidden, NotFound
from app.core.gameplay import public
from app.db.session import transaction
from app.modules.players.repository import PlayerRepository
from app.modules.inventory.service import InventoryService
from app.modules.social.community_models import (
    SocialPreferences,
    WishlistEntry,
    GiftWishlistAllocation,
    SocialRevision,
)
from app.modules.social.models import Gift


def bump_social(db, *players):
    # Caller holds all affected player locks; the revision commits with the action.
    for pid in sorted(set(players)):
        row = db.get(SocialRevision, pid, populate_existing=True)
        if row is None:
            db.add(SocialRevision(player_id=pid, revision=1))
        else:
            row.revision += 1
    db.flush()


class CommunityService:
    def __init__(self, db):
        self.db = db

    def preferences(self, pid):
        row = self.db.get(SocialPreferences, pid)
        return (
            public(row)
            if row
            else dict(
                player_id=pid,
                voice_privacy="friends",
                wishlist_visibility="friends",
                proximity_prompts=True,
            )
        )

    def update_preferences(self, pid, request):
        with transaction(self.db):
            PlayerRepository(self.db).lock(pid)
            row = self.db.get(SocialPreferences, pid, populate_existing=True)
            if row is None:
                row = SocialPreferences(**self.preferences(pid))
                self.db.add(row)
            for key, value in request.model_dump(exclude_unset=True).items():
                setattr(row, key, value)
            bump_social(self.db, pid)
            result = public(row)
        return result

    def authorize_view(self, viewer, owner):
        if viewer == owner:
            return
        from app.modules.social.service import SocialService

        SocialService(self.db).allowed(viewer, owner)
        if self.preferences(owner)["wishlist_visibility"] != "friends":
            raise Forbidden("Wishlist is not visible")

    def counts(self, entry_id):
        rows = self.db.execute(
            select(Gift.claimed, func.sum(Gift.quantity))
            .join(GiftWishlistAllocation, GiftWishlistAllocation.gift_id == Gift.id)
            .where(GiftWishlistAllocation.entry_id == entry_id)
            .group_by(Gift.claimed)
        ).all()
        values = dict(rows)
        return int(values.get(False, 0)), int(values.get(True, 0))

    def entry_public(self, row):
        pending, fulfilled = self.counts(row.id)
        return {
            **public(row),
            "pending_quantity": pending,
            "fulfilled_quantity": fulfilled,
            "remaining_quantity": max(0, row.quantity - pending - fulfilled),
        }

    def wishlist(self, viewer, owner):
        self.authorize_view(viewer, owner)
        rows = self.db.scalars(
            select(WishlistEntry)
            .where(WishlistEntry.player_id == owner, WishlistEntry.active.is_(True))
            .order_by(WishlistEntry.priority.desc(), WishlistEntry.id)
            .limit(50)
        )
        return [self.entry_public(row) for row in rows]

    def own_entry(self, pid, item_code):
        row = self.db.scalar(
            select(WishlistEntry).where(
                WishlistEntry.player_id == pid, WishlistEntry.item_code == item_code
            )
        )
        if row is None:
            raise NotFound("Wishlist item not found")
        return self.entry_public(row)

    def put(self, pid, item_code, request):
        with transaction(self.db):
            PlayerRepository(self.db).lock(pid)
            if not InventoryService(self.db).definition(item_code).giftable:
                raise Forbidden("Item is not giftable")
            row = self.db.scalar(
                select(WishlistEntry)
                .where(
                    WishlistEntry.player_id == pid, WishlistEntry.item_code == item_code
                )
                .execution_options(populate_existing=True)
            )
            if (row.version if row else 0) != request.expected_version:
                raise AppError(
                    "WISHLIST_CHANGED", "Refresh the wishlist before editing", 409
                )
            if row is None or not row.active:
                count = self.db.scalar(
                    select(func.count())
                    .select_from(WishlistEntry)
                    .where(
                        WishlistEntry.player_id == pid, WishlistEntry.active.is_(True)
                    )
                )
                if count >= 50:
                    raise AppError(
                        "WISHLIST_FULL", "A wishlist can contain 50 items", 409
                    )
            if row:
                pending, fulfilled = self.counts(row.id)
                if request.quantity < pending + fulfilled:
                    raise AppError(
                        "WISHLIST_ALLOCATED",
                        "Quantity is below gifts already allocated",
                        409,
                    )
                row.quantity, row.priority, row.active = (
                    request.quantity,
                    request.priority,
                    True,
                )
                row.version += 1
            else:
                row = WishlistEntry(
                    player_id=pid,
                    item_code=item_code,
                    quantity=request.quantity,
                    priority=request.priority,
                    version=1,
                    active=True,
                )
                self.db.add(row)
            bump_social(self.db, pid)
            result = self.entry_public(row)
        return result

    def remove(self, pid, item_code, expected_version):
        with transaction(self.db):
            PlayerRepository(self.db).lock(pid)
            row = self.db.scalar(
                select(WishlistEntry)
                .where(
                    WishlistEntry.player_id == pid, WishlistEntry.item_code == item_code
                )
                .execution_options(populate_existing=True)
            )
            if row is None:
                raise NotFound("Wishlist item not found")
            if row.version != expected_version:
                raise AppError(
                    "WISHLIST_CHANGED", "Refresh the wishlist before editing", 409
                )
            row.active = False
            row.version += 1
            bump_social(self.db, pid)
            result = self.entry_public(row)
        return result

    def reserve(self, sender, request):
        # Both player rows already locked by gift(); all edits lock the owner.
        if request.wishlist_entry_id is None:
            return None
        self.authorize_view(sender, request.target_id)
        row = self.db.get(
            WishlistEntry, request.wishlist_entry_id, populate_existing=True
        )
        if row is None or row.player_id != request.target_id:
            raise NotFound("Wishlist item not found")
        if (
            not row.active
            or row.item_code != request.item_code
            or row.version != request.wishlist_version
        ):
            raise AppError(
                "WISHLIST_CHANGED", "Refresh the wishlist before gifting", 409
            )
        pending, fulfilled = self.counts(row.id)
        if request.quantity > row.quantity - pending - fulfilled:
            raise AppError(
                "WISHLIST_CHANGED", "The requested quantity is already allocated", 409
            )
        row.version += 1
        return row

    def gift_receipt(self, pid, request_id):
        row = self.db.scalar(
            select(Gift).where(Gift.sender_id == pid, Gift.request_id == request_id)
        )
        return {"found": row is not None, "gift": public(row) if row else None}
