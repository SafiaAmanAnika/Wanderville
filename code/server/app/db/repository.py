"""Shared persistence primitives for every module repository.

``Repository`` is the one place the three operations every repository needs live:
fetch-by-primary-key with a not-found contract, create-and-flush, and a bounded
list. It lives in ``app/db/`` rather than ``app/core/`` because it is persistence
infrastructure, not a leaf concern -- and putting it here is what lets ``app/core/``
stay a genuine leaf layer with no dependency on any module.
"""

from sqlalchemy import select

from app.core.exceptions import NotFound


class Repository:
    """Base for the read/write half of a module.

    Two structural rules hold for every subclass:

    * **Never commit.** ``add`` and ``delete`` flush so a caller's own
      ``transaction(db)`` sees the change and decides when it becomes durable.
      The one exception is the login-failure write in ``auth``, which opens its
      own boundary on purpose because it must survive the credential error.
    * **Refresh locked rows.** ``get`` and the explicit ``populate_existing``
      options elsewhere make a re-read authoritative, so a value the caller read
      before taking a ``FOR UPDATE`` lock cannot leak into the decision made
      after it.
    """

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

    def keyset_page(self, model, *conditions, before=None, limit=50, order=None):
        """One page of a newest-first, id-cursored feed.

        Every paginated feed in the product pages backwards over the primary key
        rather than by offset, so a page cannot skip or repeat rows when rows are
        inserted while the reader is paging.

        Returns ``(rows, next_cursor)``; ``next_cursor`` is ``None`` on the last
        page, which is the case when fewer rows came back than were asked for.
        """
        if before:
            conditions = (*conditions, model.id < before)
        rows = self.list(model, *conditions, limit=limit, order=order)
        return rows, (rows[-1].id if len(rows) == limit else None)