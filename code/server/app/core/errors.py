"""Exception translation: domain failure in, client-facing envelope out.

This is the only place in the application that turns an exception into an HTTP
status code. Services raise ``AppError`` subclasses and never import anything
from FastAPI; routers stay thin; everything cross-cutting is registered here.

Two rules are load-bearing:

* **Never echo request payloads.** ``RequestValidationError.errors()`` contains
  the raw input, which for auth endpoints is the password or the Google token.
* **Never leak connection strings.** A database error message can embed the DSN
  including its password, so only the exception *type name* is logged, and the
  password is redacted even then.
"""

import logging
import re

from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from starlette.exceptions import HTTPException

from app.core.config import settings
from app.core.exceptions import AppError
from app.core.responses import ErrorResponse

# Matches the credentials segment of any URL-shaped string.
CREDENTIALS = re.compile(r"://[^@\s]*@")
MAX_LOGGED_DETAIL = 300


def error_response(status, code, message):
    headers = {"WWW-Authenticate": "Bearer"} if status == 401 else None
    return JSONResponse(
        status_code=status,
        content=ErrorResponse(error=code, message=message).model_dump(),
        headers=headers,
    )


def _redact(exc):
    """Safe-to-log rendering of a database exception."""
    return CREDENTIALS.sub("://***@", str(getattr(exc, "orig", exc)))[
        :MAX_LOGGED_DETAIL
    ]


async def app_error(_request, exc: AppError):
    return error_response(exc.status, exc.code, exc.message)


async def validation_error(_request, exc: RequestValidationError):
    # Never echo exc.errors(): it includes raw passwords and tokens as input.
    return error_response(
        422,
        "VALIDATION_ERROR",
        "; ".join(
            f"{'.'.join(map(str, e['loc'][1:]))}: {e['msg']}" for e in exc.errors()
        ),
    )


async def http_error(_request, exc: HTTPException):
    return error_response(exc.status_code, "HTTP_ERROR", str(exc.detail))


async def integrity_error(_request, _exc: IntegrityError):
    return error_response(
        409, "DATA_CONFLICT", "This operation conflicts with existing data"
    )


async def database_error(_request, exc: SQLAlchemyError):
    # The type name alone cannot distinguish a bad host, bad credentials or a
    # missing schema, and none of these strings may carry the password.
    detail = _redact(exc)
    logging.getLogger("wanderville").error(
        "Database operation failed against %s: %s: %s",
        settings.database_target,
        type(exc).__name__,
        detail,
    )
    return error_response(
        503, "DATABASE_UNAVAILABLE", "Database operation could not be completed"
    )


async def unexpected_error(_request, exc: Exception):
    logging.getLogger("wanderville").error("Unhandled failure: %s", type(exc).__name__)
    return error_response(500, "INTERNAL_ERROR", "An unexpected error occurred")


# Ordered by specificity: Starlette matches on exact exception type, and
# IntegrityError/SQLAlchemyError must be reached before the catch-all Exception.
EXCEPTION_HANDLERS = (
    (AppError, app_error),
    (RequestValidationError, validation_error),
    (HTTPException, http_error),
    (IntegrityError, integrity_error),
    (SQLAlchemyError, database_error),
    (Exception, unexpected_error),
)


def register(app):
    """Attach every handler above to ``app``."""
    for exception_type, handler in EXCEPTION_HANDLERS:
        app.add_exception_handler(exception_type, handler)