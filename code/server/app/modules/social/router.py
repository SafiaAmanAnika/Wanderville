from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.core.responses import success
from app.modules.social.service import SocialService
from app.modules.social.schemas import (
    TargetRequest,
    FriendAction,
    TradeAction,
    GiftRequest,
    TradeRequest,
    MessageRequest,
    ReportRequest,
)

router = APIRouter(prefix="/social", tags=["social"])


@router.get("/search")
def get_search(
    q: str = Query(min_length=2, max_length=32),
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).search(pid, q))


@router.get("/friends")
def get_friends(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(SocialService(db).friends(pid))


@router.get("/requests")
def get_requests(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(SocialService(db).friends(pid, True))


@router.post("/requests")
def post_requests(
    payload: TargetRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).request(pid, payload.target_id))


@router.post("/friends/{target_id}")
def post_friends_target_id(
    payload: FriendAction,
    target_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).respond(pid, target_id, payload.action))


@router.post("/blocks")
def post_blocks(
    payload: TargetRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).block(pid, payload.target_id))


@router.post("/blocks/{target_id}/remove")
def post_blocks_target_id_remove(
    target_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).block(pid, target_id, True))


@router.post("/gifts")
def post_gifts(
    payload: GiftRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).gift(pid, payload))


@router.post("/gifts/{gift_id}/claim")
def post_gifts_gift_id_claim(
    gift_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).claim_gift(pid, gift_id))


@router.post("/trades")
def post_trades(
    payload: TradeRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).propose(pid, payload))


@router.post("/trades/{trade_id}")
def post_trades_trade_id(
    payload: TradeAction,
    trade_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).trade_action(pid, trade_id, payload.action))


@router.post("/visit/{target_id}")
def post_visit_target_id(
    target_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).visit(pid, target_id))


@router.post("/invites")
def post_invites(
    payload: TargetRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).invite(pid, payload.target_id))


@router.post("/invites/{invite_id}/accept")
def post_invites_invite_id_accept(
    invite_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).accept_invite(pid, invite_id))


@router.post("/messages")
def post_messages(
    payload: MessageRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).message(pid, payload))


@router.get("/messages/{target_id}")
def get_messages_target_id(
    target_id: int,
    after: int = Query(0, ge=0),
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).messages(pid, target_id, after))


@router.post("/reports")
def post_reports(
    payload: ReportRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).report(pid, payload))


@router.get("/gifts")
def gifts(
    before: int | None = Query(None, gt=0),
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).inbox(pid, before))


@router.get("/trades")
def trades(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(SocialService(db).trades(pid))


@router.get("/invites")
def invites(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(SocialService(db).invites(pid))


@router.get("/blocks")
def blocks(pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(SocialService(db).blocks(pid))


@router.get("/farms/{target_id}")
def farm(
    target_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).farm(pid, target_id))
