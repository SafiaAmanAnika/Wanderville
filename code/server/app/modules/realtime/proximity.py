import math
from datetime import timedelta
from sqlalchemy import select, or_
from app.core.clock import utcnow
from app.core.config import settings
from app.modules.realtime.repository import RealtimeRepository
from app.modules.realtime.service import RealtimeService, PRESENCE_TTL_SECONDS
from app.modules.social.community import CommunityService
from app.modules.social.community_models import SocialPreferences, SocialRevision
from app.modules.social.models import Friendship


def proximity_view(db, pid):
    row = RealtimeService(db).active(pid)
    repo = RealtimeRepository(db)
    blocked = repo.blocked_ids(pid)
    candidates = repo.nearby(
        row.room,
        utcnow() - timedelta(seconds=PRESENCE_TTL_SECONDS),
        row.x,
        row.y,
        settings.proximity_exit_radius,
    )
    ids = [p.player_id for p in candidates]
    names = repo.usernames(ids)
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
        if (
            target == pid
            or target in blocked
            or distance > settings.proximity_exit_radius
        ):
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
