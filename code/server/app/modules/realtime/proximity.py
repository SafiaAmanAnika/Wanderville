import math
from sqlalchemy import select, or_
from app.core.config import settings
from app.modules.realtime.service import RealtimeService
from app.modules.social.community import CommunityService
from app.modules.social.community_models import SocialPreferences, SocialRevision
from app.modules.social.models import Friendship


def proximity_view(db, pid):
    """The proximity/voice policy projection for one player.

    Selection (who is near, who is blocked, who is a friend) comes from
    ``RealtimeService.roster`` so this view and the snapshot roster can never
    disagree about who is present. Under ``PRESENCE_BACKEND=memory`` that is the
    in-process projection's coordinates filtered by the database's
    authorization, so voice permission follows the same live positions the
    players see rather than the last committed row.
    """
    service = RealtimeService(db)
    row = service.active(pid)
    candidates, names = service.roster(
        row, radius=settings.proximity_exit_radius, exclude_blocks=True
    )
    ids = [p.player_id for p in candidates]
    preferences = {
        p.player_id: p.voice_privacy
        for p in db.scalars(
            select(SocialPreferences).where(SocialPreferences.player_id.in_(ids))
        )
    }
    own = CommunityService(db).preferences(pid)
    friends = {
        r.high_id if r.low_id == pid else r.low_id
        for r in db.scalars(
            select(Friendship).where(
                or_(Friendship.low_id == pid, Friendship.high_id == pid),
                Friendship.status == "accepted",
            )
        )
    }
    nearby = []
    for other in candidates:
        target = other.player_id
        distance = math.hypot(row.x - other.x, row.y - other.y)
        if target == pid or distance > settings.proximity_exit_radius:
            continue
        friend = target in friends
        policies = (own["voice_privacy"], preferences.get(target, "friends"))
        voice = all(p == "nearby" or (p == "friends" and friend) for p in policies)
        nearby.append(
            dict(
                player_id=target,
                username=names[target],
                distance=distance,
                friend=friend,
                can_text=distance <= settings.proximity_radius,
                can_voice=settings.voice_enabled
                and voice
                and distance <= settings.proximity_radius,
            )
        )
    revision = db.get(SocialRevision, pid)
    return dict(
        room=row.room,
        room_epoch=row.room_epoch,
        nearby=nearby,
        voice_privacy=own["voice_privacy"],
        proximity_prompts=own["proximity_prompts"],
        social_revision=revision.revision if revision else 0,
        enter_radius=settings.proximity_radius,
        exit_radius=settings.proximity_exit_radius,
    )
