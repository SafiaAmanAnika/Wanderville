from typing import Generic, Literal, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class Envelope(BaseModel, Generic[T]):
    success: Literal[True] = True
    data: T
    message: str = "OK"


class ErrorResponse(BaseModel):
    success: Literal[False] = False
    error: str
    message: str


def success(data=None, message="OK"):
    return {"success": True, "data": data, "message": message}


def public(row):
    """Every mapped column of ``row`` as a plain dict.

    The default serializer for a model row on its way out of a service. It is
    deliberately shape-agnostic: a module that needs a narrower or annotated
    projection builds one explicitly instead of hiding the difference behind an
    extra parameter here.
    """
    return {c.name: getattr(row, c.name) for c in row.__table__.columns}
