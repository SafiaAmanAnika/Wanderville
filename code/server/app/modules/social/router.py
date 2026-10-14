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
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).search(player_id, q))


@router.get("/friends")
def get_friends(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(SocialService(db).friends(player_id))


@router.get("/requests")
def get_requests(
    player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    return success(SocialService(db).friends(player_id, True))


@router.post("/requests")
def post_requests(
    payload: TargetRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).request(player_id, payload.target_id))


@router.post("/friends/{target_id}")
def post_friends_target_id(
    payload: FriendAction,
    target_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).respond(player_id, target_id, payload.action))


@router.post("/blocks")
def post_blocks(
    payload: TargetRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).block(player_id, payload.target_id))


@router.post("/blocks/{target_id}/remove")
def post_blocks_target_id_remove(
    target_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).block(player_id, target_id, True))


@router.post("/gifts")
def post_gifts(
    payload: GiftRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).gift(player_id, payload))


@router.post("/gifts/{gift_id}/claim")
def post_gifts_gift_id_claim(
    gift_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).claim_gift(player_id, gift_id))


@router.post("/trades")
def post_trades(
    payload: TradeRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).propose(player_id, payload))


@router.post("/trades/{trade_id}")
def post_trades_trade_id(
    payload: TradeAction,
    trade_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).trade_action(player_id, trade_id, payload.action))


@router.post("/visit/{target_id}")
def post_visit_target_id(
    target_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).visit(player_id, target_id))


@router.post("/invites")
def post_invites(
    payload: TargetRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).invite(player_id, payload.target_id))


@router.post("/invites/{invite_id}/accept")
def post_invites_invite_id_accept(
    invite_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).accept_invite(player_id, invite_id))


@router.post("/messages")
def post_messages(
    payload: MessageRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).message(player_id, payload))


@router.get("/messages/{target_id}")
def get_messages_target_id(
    target_id: int,
    after: int = Query(0, ge=0),
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).messages(player_id, target_id, after))


@router.post("/reports")
def post_reports(
    payload: ReportRequest,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).report(player_id, payload))


@router.get("/gifts")
def gifts(
    before: int | None = Query(None, gt=0),
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).inbox(player_id, before))


@router.get("/trades")
def trades(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(SocialService(db).trades(player_id))


@router.get("/invites")
def invites(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(SocialService(db).invites(player_id))


@router.get("/blocks")
def blocks(player_id: int = Depends(get_current_player_id), db: Session = Depends(get_db)):
    return success(SocialService(db).blocks(player_id))


@router.get("/farms/{target_id}")
def farm(
    target_id: int,
    player_id: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(SocialService(db).farm(player_id, target_id))
