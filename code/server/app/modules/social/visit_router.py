"""Farm invitation and visit endpoints.

Route contract notes:

* Every route takes the caller from the access token only. No route accepts a
  ``player_id``, ``owner_id`` or ``world_id`` from the request body as proof of
  anything. The two routes that do take a world id (``/farm/visiting/state`` and
  the legacy ``/social/farms/{id}``) re-derive permission from the caller's own
  active visit session.
* ``accept`` is the only place a visitor slot is created. It is a single
  transactional call, so there is no separate "check then reserve" step a second
  request could interleave with.
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.responses import success
from app.db.session import get_db
from app.modules.auth.dependencies import get_current_player_id
from app.modules.farming.service import FarmingService
from app.modules.social.farm_visiting import FarmVisitService
from app.modules.social.schemas import FarmInviteRequest
from app.modules.world.access import resolve

router = APIRouter(prefix="/farm/visiting", tags=["farm-visiting"])


def _service(db):
    return FarmVisitService(db)


# ---------------------------------------------------------------- invitations


@router.post("/invitations")
def create_invitation(
    payload: FarmInviteRequest,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    """Host invites one guest to their farm.

    Idempotent: re-inviting inside the existing offer's window returns the same
    pending invitation rather than creating a second one.
    """
    return success(
        _service(db).invite(pid, payload.guest),
        "Invitation sent",
    )


@router.get("/invitations")
def list_invitations(
    resolved: bool = Query(False, description="Include declined/expired/cancelled"),
    as_host: bool = Query(False, description="Outgoing instead of incoming"),
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    service = _service(db)
    rows = (
        service.outgoing(pid, resolved) if as_host else service.inbox(pid, resolved)
    )
    return success(rows)


@router.post("/invitations/{invitation_id}/accept")
def accept_invitation(
    invitation_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    """Guest accepts: capacity checked and slot reserved in one transaction."""
    return success(
        _service(db).accept(pid, invitation_id),
        "Farm visit started",
    )


@router.post("/invitations/{invitation_id}/decline")
def decline_invitation(
    invitation_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(_service(db).decline(pid, invitation_id), "Invitation declined")


@router.delete("/invitations/{invitation_id}")
def cancel_invitation(
    invitation_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    return success(_service(db).cancel(pid, invitation_id), "Invitation cancelled")


# -------------------------------------------------------------------- visits


@router.get("/session")
def current_session(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    """The caller's resolved session: owned vs current world and the mode."""
    return success(resolve(db, pid).public())


@router.get("/visitors")
def list_visitors(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    """Current occupancy of the caller's own farm. The owner is not counted."""
    return success(_service(db).visitors(pid))


@router.delete("/visitors/{visit_session_id}")
def remove_visitor(
    visit_session_id: int,
    pid: int = Depends(get_current_player_id),
    db: Session = Depends(get_db),
):
    """Owner kicks a visitor; the visitor is returned to their own world."""
    return success(
        _service(db).kick(pid, visit_session_id), "Visitor removed"
    )


@router.post("/leave")
def leave_farm(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    """Visitor leaves: slot released and the caller returns to their own farm."""
    result = _service(db).leave(pid, "LEFT")
    if result is None:
        result = resolve(db, pid).public()
        result["reason"] = "NOT_VISITING"
    return success(result, "Returned to your farm")


@router.get("/state")
def visiting_state(
    pid: int = Depends(get_current_player_id), db: Session = Depends(get_db)
):
    """Authoritative snapshot of the world the caller is currently in.

    While visiting this is the host's farm, including its tiles, crops and
    growth state. It is a read; the caller cannot change what comes back.
    """
    return success(FarmingService(db).list(pid))