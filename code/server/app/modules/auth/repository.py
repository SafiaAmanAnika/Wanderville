from sqlalchemy import select, update

from app.modules.auth.models import AccountToken, RefreshToken


class AuthRepository:
    def __init__(self, db):
        self.db = db

    def refresh(self, token_hash, lock=False):
        query = select(RefreshToken).where(RefreshToken.token_hash == token_hash)
        if lock:
            query = query.with_for_update().execution_options(populate_existing=True)
        return self.db.scalar(query)

    def account(self, token_hash, token_type, lock=False):
        query = select(AccountToken).where(
            AccountToken.token_hash == token_hash, AccountToken.token_type == token_type
        )
        if lock:
            query = query.with_for_update().execution_options(populate_existing=True)
        return self.db.scalar(query)

    def add_refresh(self, **values):
        self.db.add(RefreshToken(**values))
        self.db.flush()

    def add_account(self, **values):
        self.db.add(AccountToken(**values))
        self.db.flush()

    def revoke_all(self, player_id, now):
        self.db.execute(
            update(RefreshToken)
            .where(
                RefreshToken.player_id == player_id, RefreshToken.revoked_at.is_(None)
            )
            .values(revoked_at=now)
        )

    def invalidate_accounts(self, player_id, kind, now):
        query = update(AccountToken).where(
            AccountToken.player_id == player_id, AccountToken.used_at.is_(None)
        )
        if kind:
            query = query.where(AccountToken.token_type == kind)
        self.db.execute(query.values(used_at=now))
