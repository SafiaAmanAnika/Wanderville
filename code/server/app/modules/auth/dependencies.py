from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.exceptions import InvalidToken
from app.db.session import get_db
from app.modules.auth.service import AuthService

bearer = HTTPBearer(auto_error=False)


def get_current_player(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
):
    if credentials is None:
        raise InvalidToken()
    return AuthService(db).authenticate(credentials.credentials)


def get_current_player_id(player=Depends(get_current_player)):
    return player.id


def client_host(request: Request) -> str | None:
    """The caller's address, for login-attempt bookkeeping.

    Resolving the peer address is a transport concern, so it belongs here rather
    than being inlined into each route that needs it. Behind a proxy this is the
    proxy's address unless a trusted forwarded header is configured, which is why
    it is recorded as an audit hint and never used to decide access.
    """
    return request.client.host if request.client else None
