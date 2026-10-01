from app.core.config import settings
from app.core.exceptions import AppError, Forbidden, NotFound
from app.db.session import transaction
from app.modules.economy.repository import EconomyRepository
from app.modules.economy.schemas import EconomyResponse, TransactionResponse, XPResponse
from app.modules.players.repository import PlayerRepository


def progression(total_xp):
    level, current, threshold = 1, total_xp, 100
    while current >= threshold:
        current -= threshold
        level += 1
        threshold = threshold * 3 // 2
    return level, current, threshold


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

    def xp(self, player_id):
        row = self.repo.experience(player_id)
        if row is None:
            raise NotFound("Player experience has not been initialized")
        level, current, threshold = progression(row.total_xp)
        return XPResponse(
            player_id=player_id,
            current_xp=current,
            total_xp=row.total_xp,
            level=level,
            xp_to_next_level=threshold,
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

    def gain_internal(self, player_id, amount):
        self.validate_amount(amount)
        row = self.repo.experience(player_id)
        if row is None:
            raise NotFound("Player experience has not been initialized")
        previous_level = row.level
        row.total_xp += amount
        row.level = progression(row.total_xp)[0]
        if row.level > previous_level:
            from app.modules.notifications.service import NotificationsService

            NotificationsService(self.db).emit(
                player_id, "level_up", f"Reached level {row.level}", "/economy/xp"
            )
        self.db.flush()
        return row

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
            self.gain_internal(player_id, request.xp_amount)
            result = self.xp(player_id)
        return result

    def history(self, player_id, limit):
        return [
            TransactionResponse.model_validate(r)
            for r in self.repo.history(player_id, limit)
        ]
