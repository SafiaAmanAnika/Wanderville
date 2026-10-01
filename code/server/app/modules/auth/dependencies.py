from fastapi import Depends
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
