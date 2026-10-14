"""Replay protection for request-id keyed writes.

A client that retries after a dropped response must get back the result of the
*first* attempt, never a second execution. Every such write therefore stores the
original request id on its row and, on a replay, re-checks that the payload
matches what was recorded before returning the stored row.

That check was previously open-coded four times (shop buy, shop sell, social
gift, social trade) and the copies had already drifted -- shop's sell path
returns a different response shape on replay than its buy path does. One
primitive keeps the semantics identical and makes a fifth caller correct by
construction.
"""

from app.core.exceptions import AppError


def ensure_same_payload(row, fields, message):
    """Return ``row`` unchanged, or refuse the replay if the payload differs.

    ``fields`` maps attribute names to the values the retry supplied. A retry
    that reuses a request id for different work is a client bug, and it is
    refused loudly rather than silently returning the earlier result, which
    would hide the mistake until the player noticed missing items.
    """
    if row is not None and any(
        getattr(row, name) != value for name, value in fields.items()
    ):
        raise AppError("IDEMPOTENCY_CONFLICT", message, 409)
    return row