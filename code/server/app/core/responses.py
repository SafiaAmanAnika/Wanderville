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
