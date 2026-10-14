class AppError(Exception):
    """Controlled domain failure, translated to HTTP only by app.main."""

    def __init__(self, code: str, message: str, status: int = 400):
        super().__init__(message)
        self.code, self.message, self.status = code, message, status


class NotFound(AppError):
    def __init__(self, message="Resource not found"):
        super().__init__("RESOURCE_NOT_FOUND", message, 404)


class Forbidden(AppError):
    def __init__(self, message="This action is not allowed"):
        super().__init__("FORBIDDEN", message, 403)


class InvalidToken(AppError):
    def __init__(self):
        super().__init__("INVALID_TOKEN", "Invalid or expired token", 401)


class TransactionBoundaryError(RuntimeError):
    """A service action opened a second transaction on an already-open session.

    This is a programming error, not a domain failure, so it is deliberately
    not an AppError: it must never be translated into a client-facing response.
    """
