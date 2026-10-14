from sqlalchemy import select

from app.core.config import settings
from app.core.exceptions import AppError, Forbidden, NotFound
from app.core.progression import (
    LEVEL_AURA_REWARDS,
    LEVELS,
    MAX_LEVEL,
    level_for_xp,
    level_info,
    xp_progress,
)
from app.db.session import transaction
from app.modules.economy.models import PlayerLevelReward
from app.modules.economy.repository import EconomyRepository
from app.modules.economy.schemas import (
    EconomyResponse,
    LevelRewardResponse,
    TransactionResponse,
    XPResponse,
)
from app.modules.inventory.models import ItemDefinition
from app.modules.inventory.service import InventoryService
from app.modules.notifications.service import NotificationsService
from app.modules.players.repository import PlayerRepository
from app.modules.shop.models import ItemRule


def progression(total_xp):
    """Backwards-compatible tuple view of the shared level table."""
    progress = xp_progress(total_xp)
    return (
        progress["level"],
        progress["current_xp"],
        progress["xp_to_next_level"] or progress["xp_span"],
    )


def _next_title(level):
    """The title the next level promotes to, so the HUD can preview it."""
    if level >= MAX_LEVEL:
        return None, None
    upcoming = level + 1
    for row in LEVELS:
        if row[0] >= upcoming and row[1] != level_info(level).title:
            return row[1], row[0]
    return None, None


class EconomyService:
    def __init__(self, db):
        self.db, self.repo = db, EconomyRepository(db)
        self.players = PlayerRepository(db)

    @staticmethod
    def validate_amount(amount):
        if type(amount) is not int or not 0 < amount <= 1_000_000:
            raise AppError(
                "INVALID_AMOUNT", "Amount must be a positive integer up to 1000000"
            )

    def balance(self, player_id):
        row = self.repo.economy(player_id)
        if row is None:
            raise NotFound("Player economy has not been initialized")
        return row

    def get(self, player_id):
        row = self.balance(player_id)
        return EconomyResponse(
            player_id=player_id,
            aura_balance=row.aura_balance,
            taka_balance=row.aura_balance,
            total_earned=row.total_earned,
            total_spent=row.total_spent,
        )

    def granted_rewards(self, player_id):
        return {
            row.level: row
            for row in self.db.scalars(
                select(PlayerLevelReward).where(
                    PlayerLevelReward.player_id == player_id
                )
            )
        }

    def xp(self, player_id):
        row = self.repo.experience(player_id)
        if row is None:
            raise NotFound("Player experience has not been initialized")
        progress = xp_progress(row.total_xp)
        info = level_info(progress["level"])
        title, title_level = _next_title(info.level)
        granted = self.granted_rewards(player_id)
        unlocked = self.db.execute(
            select(ItemDefinition.item_code, ItemDefinition.name, ItemRule.required_level)
            .join(ItemRule, ItemRule.item_code == ItemDefinition.item_code)
            .where(ItemDefinition.buy_value.is_not(None), ItemRule.required_level <= info.level)
            .order_by(ItemRule.required_level, ItemDefinition.item_code)
        ).mappings().all()
        return XPResponse(
            player_id=player_id,
            total_xp=row.total_xp,
            level=info.level,
            title=info.title,
            xp_span=info.span_to_next,
            xp_floor=info.min_xp,
            next_title=title,
            next_title_level=title_level,
            slot_increment=info.cumulative_slots,
            slot_capacity=InventoryService(self.db).capacity(player_id),
            unlocked_items=[dict(item) for item in unlocked],
            rewards=[
                LevelRewardResponse(
                    level=reward.level,
                    aura=reward.aura,
                    # Each reward keeps its own level's title, so a jump from
                    # level 1 to 10 does not relabel the level 2 payout.
                    title=level_info(reward.level).title,
                )
                for _, reward in sorted(granted.items())
            ],
            **{
                key: progress[key]
                for key in ("current_xp", "xp_to_next_level", "max_level")
            },
        )

    def change_internal(
        self, player_id, amount, earn, reason, reference_type=None, reference_id=None
    ):
        """Caller owns the player lock and transaction."""
        self.validate_amount(amount)
        row = self.balance(player_id)
        if not earn and row.aura_balance < amount:
            raise AppError("INSUFFICIENT_FUNDS", "Not enough Aura")
        row.aura_balance += amount if earn else -amount
        if earn:
            row.total_earned += amount
        else:
            row.total_spent += amount
        self.repo.record(
            player_id=player_id,
            amount=amount if earn else -amount,
            transaction_type="earn" if earn else "spend",
            reason=reason or "unspecified",
            reference_type=reference_type,
            reference_id=reference_id,
        )
        return row

    def grant_level_rewards_internal(self, player_id, previous_level, new_level):
        """Pay every level crossed, once, even if XP jumps several levels."""
        granted = self.granted_rewards(player_id)
        paid = []
        for level in range(previous_level + 1, min(new_level, MAX_LEVEL) + 1):
            if level in granted or level not in LEVEL_AURA_REWARDS:
                continue
            aura = LEVEL_AURA_REWARDS[level]
            self.db.add(
                PlayerLevelReward(player_id=player_id, level=level, aura=aura)
            )
            granted[level] = True
            paid.append(
                LevelRewardResponse(
                    level=level, aura=aura, title=level_info(level).title
                )
            )
            if aura:
                self.change_internal(
                    player_id,
                    aura,
                    True,
                    f"Level {level} reward",
                    reference_type="level_reward",
                    reference_id=str(level),
                )
        if paid:
            self.db.flush()
        return paid

    def gain_internal(self, player_id, amount):
        self.validate_amount(amount)
        row = self.repo.experience(player_id)
        if row is None:
            raise NotFound("Player experience has not been initialized")
        # Legacy entitlements/rewards are retained by the migration; the level
        # itself always follows cumulative XP and is capped at ten.
        previous_level = level_for_xp(row.total_xp).level
        row.total_xp += amount
        row.level = level_for_xp(row.total_xp).level
        if row.level > previous_level:
            NotificationsService(self.db).emit(
                player_id, "level_up", f"Reached level {row.level}", "/economy/xp"
            )
        self.db.flush()
        return self.grant_level_rewards_internal(
            player_id, previous_level, row.level
        )

    def change(self, player_id, request, earn):
        if earn and not settings.is_development:
            raise Forbidden("Arbitrary currency awards are development-only")
        with transaction(self.db):
            self.players.lock(player_id)
            self.change_internal(player_id, request.amount, earn, request.description)
            result = self.get(player_id)
        return result

    def gain_compatibility(self, player_id, request):
        if not settings.is_development:
            raise Forbidden("Arbitrary XP awards are development-only")
        with transaction(self.db):
            self.players.lock(player_id)
            paid = self.gain_internal(player_id, request.xp_amount)
            result = self.xp(player_id)
        # `xp()` reports every reward ever granted; the caller that just earned
        # XP needs only this call's payouts, so the HUD never re-announces a
        # level it already celebrated.
        result.rewards = paid
        return result

    def history(self, player_id, limit):
        return [
            TransactionResponse.model_validate(r)
            for r in self.repo.history(player_id, limit)
        ]
