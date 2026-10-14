"""Farm invitations, visit sessions and per-world visitor admission rules.

Additive plus one table replacement:

* ``farm_invitations`` supersedes ``social_invites``. The old table only had a
  ``sender_id``/``receiver_id`` pair plus an ``accepted`` boolean, so an invite
  could not express DECLINED/CANCELLED/EXPIRED and two identical pending invites
  were indistinguishable from one. Rows are copied over before the old table is
  dropped.
* ``farm_visit_sessions`` records the temporary occupancy of a farm. Nothing
  previously recorded it, so there was no slot to release on disconnect.
* ``player_worlds`` gains the visitor entrance and the admission limit so a
  visitor spawns at the host's farm and the cap is data, not a literal.

Uniqueness uses NULLable key columns rather than partial indexes so the same DDL
works on SQLite (the test database) and PostgreSQL (Neon). SQL treats NULLs as
distinct in a UNIQUE index, so only PENDING / ACTIVE rows collide.

``visitor_limit`` deliberately carries no database CHECK constraint. Adding one
to an existing SQLite table means Alembic has to rebuild ``player_worlds``, and
with ``PRAGMA foreign_keys=ON`` that rebuild's ``DROP TABLE`` fires every
``ON DELETE CASCADE`` pointed at it -- which silently deleted every existing
``farm_tiles`` row when the migration chain was replayed in the test suite. The
1..5 bound is therefore enforced by the request schema and clamped again in
``app.modules.world.access.capacity``, which is the check that actually guards
admission.
"""

from datetime import datetime, timezone

import sqlalchemy as sa
from alembic import op

revision = "0007_farm_visiting"
down_revision = "0006_progression_and_stacks"
branch_labels = None
depends_on = None

INVITATION_STATUSES = ("PENDING", "ACCEPTED", "DECLINED", "EXPIRED", "CANCELLED")
SESSION_STATUSES = ("ACTIVE", "LEFT", "DISCONNECTED", "KICKED", "EXPIRED")

INVITE_STATUS_SQL = " or ".join(f"status = '{s}'" for s in INVITATION_STATUSES)
SESSION_STATUS_SQL = " or ".join(f"status = '{s}'" for s in SESSION_STATUSES)


def upgrade():
    # --- per-world visitor admission ------------------------------------
    # Entrance defaults to the shared campus spawn so a visitor never appears at
    # the map origin, and so pre-existing worlds get a sane gate immediately.
    op.add_column(
        "player_worlds",
        sa.Column("farm_entrance_x", sa.Float(), nullable=False, server_default="7377.0"),
    )
    op.add_column(
        "player_worlds",
        sa.Column("farm_entrance_y", sa.Float(), nullable=False, server_default="-891.0"),
    )
    op.add_column(
        "player_worlds",
        sa.Column("visitor_limit", sa.Integer(), nullable=False, server_default="5"),
    )

    # --- invitations ---------------------------------------------------
    op.create_table(
        "farm_invitations",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "host_player_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "invited_player_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "world_id",
            sa.Integer(),
            sa.ForeignKey("player_worlds.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "status",
            sa.String(16),
            nullable=False,
            server_default="PENDING",
        ),
        # "host:guest:world" while PENDING, NULL otherwise. Enforces exactly
        # one active invitation per host/guest/world triple without a partial
        # index, and lets a fresh invite be sent once the old one resolves.
        sa.Column("active_key", sa.String(64), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("responded_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "host_player_id <> invited_player_id", name="not_self"
        ),
        sa.CheckConstraint(
            "expires_at > created_at", name="expiry_order"
        ),
        sa.CheckConstraint(f"({INVITE_STATUS_SQL})", name="status"),
        sa.UniqueConstraint("active_key", name="uq_farm_invitations_active"),
    )
    op.create_index(
        "ix_farm_invitations_guest_status",
        "farm_invitations",
        ["invited_player_id", "status", "id"],
    )
    op.create_index(
        "ix_farm_invitations_host_status",
        "farm_invitations",
        ["host_player_id", "status"],
    )
    op.create_index(
        "ix_farm_invitations_expiry", "farm_invitations", ["expires_at"]
    )

    # Carry surviving invites across. A stored invite is by definition still
    # pending (an accepted one had left no usable session), and the old expiry
    # is preserved rather than extended.
    #
    # ``created_at`` is bound as a Python timestamp instead of calling ``now()``
    # because this migration chain also runs against SQLite in the test suite,
    # which has no ``now()`` function. The ``server_default`` above stays
    # dialect-aware, so this copy statement is the only place needing a value.
    connection = op.get_bind()
    connection.execute(
        sa.text(
            "INSERT INTO farm_invitations "
            "(host_player_id, invited_player_id, world_id, status, active_key, "
            " created_at, expires_at) "
            "SELECT i.sender_id, i.receiver_id, i.world_id, "
            "       CASE WHEN i.accepted THEN 'ACCEPTED' ELSE 'PENDING' END, "
            "       CASE WHEN i.accepted THEN NULL "
            "            ELSE i.sender_id || ':' || i.receiver_id || ':' || i.world_id END, "
            "       :copied_at, i.expires_at "
            "FROM social_invites i "
            "WHERE NOT (i.accepted AND EXISTS ("
            "    SELECT 1 FROM farm_invitations d "
            "    WHERE d.host_player_id = i.sender_id "
            "      AND d.invited_player_id = i.receiver_id "
            "      AND d.world_id = i.world_id AND d.status = 'PENDING'))"
        ),
        {"copied_at": datetime.now(timezone.utc)},
    )
    op.drop_table("social_invites")

    # --- visit sessions -------------------------------------------------
    op.create_table(
        "farm_visit_sessions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "world_id",
            sa.Integer(),
            sa.ForeignKey("player_worlds.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "host_player_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "visitor_player_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "status",
            sa.String(16),
            nullable=False,
            server_default="ACTIVE",
        ),
        # The visitor's own player id while ACTIVE, NULL once resolved. This is
        # the database-level guarantee that one player occupies at most one
        # visitor slot, even across concurrent accepts.
        sa.Column("active_visitor_key", sa.Integer(), nullable=True),
        sa.Column(
            "started_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "last_seen_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "host_player_id <> visitor_player_id", name="not_self"
        ),
        sa.CheckConstraint(
            "ended_at IS NULL OR ended_at >= started_at", name="end_order"
        ),
        sa.CheckConstraint(f"({SESSION_STATUS_SQL})", name="status"),
        sa.UniqueConstraint(
            "active_visitor_key", name="uq_farm_visit_sessions_active_visitor"
        ),
    )
    # Capacity counting reads ACTIVE rows for one world; this index is the
    # server-authoritative answer to "does this farm still have a free slot".
    op.create_index(
        "ix_farm_visit_sessions_world_status",
        "farm_visit_sessions",
        ["world_id", "status"],
    )
    op.create_index(
        "ix_farm_visit_sessions_visitor",
        "farm_visit_sessions",
        ["visitor_player_id", "status"],
    )
    # Stale-session sweep reads ACTIVE rows older than the heartbeat deadline.
    op.create_index(
        "ix_farm_visit_sessions_heartbeat",
        "farm_visit_sessions",
        ["status", "last_seen_at"],
    )


def downgrade():
    op.drop_table("farm_visit_sessions")
    op.create_table(
        "social_invites",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "sender_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "receiver_id",
            sa.Integer(),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "world_id",
            sa.Integer(),
            sa.ForeignKey("player_worlds.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "expires_at", sa.DateTime(timezone=True), nullable=False
        ),
        sa.Column(
            "accepted", sa.Boolean(), nullable=False, server_default=sa.false()
        ),
        sa.CheckConstraint(
            "sender_id <> receiver_id", name="not_self"
        ),
    )
    op.create_index("ix_social_invites_sender_id", "social_invites", ["sender_id"])
    op.create_index(
        "ix_invite_receiver_expiry",
        "social_invites",
        ["receiver_id", "expires_at"],
    )
    # ``accepted`` is a boolean again, so use CASE rather than relying on each
    # dialect's boolean comparison result.
    connection = op.get_bind()
    connection.execute(
        sa.text(
            "INSERT INTO social_invites "
            "(sender_id, receiver_id, world_id, expires_at, accepted) "
            "SELECT host_player_id, invited_player_id, world_id, expires_at, "
            "       CASE WHEN status = 'ACCEPTED' THEN TRUE ELSE FALSE END "
            "FROM farm_invitations ORDER BY id"
        )
    )
    op.drop_table("farm_invitations")
    op.drop_column("player_worlds", "visitor_limit")
    op.drop_column("player_worlds", "farm_entrance_y")
    op.drop_column("player_worlds", "farm_entrance_x")