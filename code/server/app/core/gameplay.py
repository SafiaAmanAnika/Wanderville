from sqlalchemy import select
from app.core.clock import as_utc, utcnow
from app.core.exceptions import NotFound


def game_day(db, now=None):
    from app.modules.world.service import WorldService

    state = WorldService(db).raw_state()
    return int(
        ((now or utcnow()) - as_utc(state.day_cycle_anchor_at)).total_seconds()
        // (state.day_night_cycle_minutes * 60)
    )


def public(row):
    return {c.name: getattr(row, c.name) for c in row.__table__.columns}


class Repository:
    def __init__(self, db):
        self.db = db

    def get(self, model, key, required=True):
        row = self.db.get(model, key, populate_existing=True)
        if row is None and required:
            raise NotFound()
        return row

    def add(self, model, **values):
        row = model(**values)
        self.db.add(row)
        self.db.flush()
        return row

    def list(self, model, *conditions, limit=100, order=None):
        statement = select(model).where(*conditions)
        if order is not None:
            statement = statement.order_by(order)
        return list(self.db.scalars(statement.limit(limit)))
