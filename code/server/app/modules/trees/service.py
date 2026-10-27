"""Chopping trees for wood, one forest per player.

The map's seasonal trees come from geometry.json ("trees"), exported from
map2.tscn with each trunk's world position. A chop is checked against the same
presence position every other server-side action uses, so the client cannot
fell a tree from across the map. When a player clears every tree of the
current season, new ones are grown for them on open ground.
"""
import math
import random

from sqlalchemy import select

from app.core.exceptions import AppError, Forbidden
from app.db.session import transaction
from app.modules.inventory.service import InventoryService
from app.modules.players.repository import PlayerRepository
from app.modules.realtime.service import RealtimeService
from app.modules.trees.models import CutTree, SpawnedTree
from app.modules.world.access import resolve
from app.modules.world.geometry import GEOMETRY, at_water, walkable
from app.modules.world.models import CAMPUS_ROOM, CAMPUS_SPAWN
from app.modules.world.service import WorldService

WOOD_PER_TREE = 15
REGROW_COUNT = 12
SPAWN_PREFIX = "spawn-"
# How far apart grown trees stand, and how far they keep from things.
TREE_SPACING = 260.0
AVOID_RADIUS = 350.0
SPAWN_CLEARANCE = 300.0
FARM_MARGIN = 150.0

MAP_TREES = {tree["id"]: tree for tree in GEOMETRY["trees"]}


def _season_scenes(season):
    return sorted({t["scene"] for t in GEOMETRY["trees"] if t["season"] == season})


class TreeService:
    def __init__(self, db):
        self.db = db

    def _season(self):
        return WorldService(self.db).state().current_season

    def _cut_ids(self, player_id):
        return set(self.db.scalars(select(CutTree.tree_id).where(CutTree.player_id == player_id)))

    def _spawned(self, player_id, season=None):
        query = select(SpawnedTree).where(SpawnedTree.player_id == player_id)
        if season is not None:
            query = query.where(SpawnedTree.season == season)
        return list(self.db.scalars(query.order_by(SpawnedTree.id)))

    @staticmethod
    def _public(row):
        return {"id": SPAWN_PREFIX + str(row.id), "season": row.season,
                "scene": row.scene, "x": row.x, "y": row.y}

    def forest(self, player_id):
        """What this player's map looks like: map trees they cut, trees grown for them."""
        return {
            "season": self._season(),
            "wood_per_tree": WOOD_PER_TREE,
            "reach": GEOMETRY["tree_reach"],
            "cut": sorted(self._cut_ids(player_id)),
            "spawned": [self._public(row) for row in self._spawned(player_id)],
        }

    def chop(self, player_id, tree_id, avoid=()):
        with transaction(self.db):
            PlayerRepository(self.db).lock(player_id)
            if resolve(self.db, player_id).is_visitor:
                raise Forbidden("You can only cut trees on your own map")
            presence = RealtimeService(self.db).active(player_id)
            if presence.room != CAMPUS_ROOM:
                raise Forbidden("You can only cut trees on your own map")
            season = self._season()
            spawned_row = None
            if tree_id.startswith(SPAWN_PREFIX):
                key = tree_id.removeprefix(SPAWN_PREFIX)
                spawned_row = self.db.get(SpawnedTree, int(key)) if key.isdigit() else None
                if spawned_row is None or spawned_row.player_id != player_id:
                    raise AppError("UNKNOWN_TREE", "That tree is not on your map", 404)
                tree = {"season": spawned_row.season, "x": spawned_row.x, "y": spawned_row.y}
            else:
                tree = MAP_TREES.get(tree_id)
                if tree is None:
                    raise AppError("UNKNOWN_TREE", "That tree is not on your map", 404)
                if self.db.get(CutTree, (player_id, tree_id)) is not None:
                    raise AppError("TREE_ALREADY_CUT", "That tree is already cut", 409)
            if tree["season"] != season:
                raise AppError("TREE_OUT_OF_SEASON", "That tree is not growing this season")
            if math.hypot(presence.x - tree["x"], presence.y - tree["y"]) > GEOMETRY["tree_reach"]:
                raise AppError("TREE_TOO_FAR", "Walk up to the tree to cut it")
            # Fails cleanly, cutting nothing, when the bag has no room.
            InventoryService(self.db).add_internal(player_id, "wood", WOOD_PER_TREE)
            if spawned_row is not None:
                self.db.delete(spawned_row)
            else:
                self.db.add(CutTree(player_id=player_id, tree_id=tree_id))
            self.db.flush()
            grown = []
            if not self._standing(player_id, season):
                grown = [self._public(row) for row in self._grow(player_id, season, avoid)]
            return {"tree_id": tree_id, "wood": WOOD_PER_TREE, "spawned": grown}

    def _standing(self, player_id, season):
        cut = self._cut_ids(player_id)
        mapped = sum(1 for t in GEOMETRY["trees"] if t["season"] == season and t["id"] not in cut)
        return mapped + len(self._spawned(player_id, season))

    def _grow(self, player_id, season, avoid, rng=None):
        """Plant REGROW_COUNT trees of ``season`` on open ground."""
        rng = rng or random.SystemRandom()
        xs = [p[0] for p in GEOMETRY["boundary"]]
        ys = [p[1] for p in GEOMETRY["boundary"]]
        (fx0, fy0), (fx1, fy1) = GEOMETRY["farm"]
        placed = []
        scenes = _season_scenes(season)
        for _ in range(4000):
            if len(placed) == REGROW_COUNT:
                break
            x, y = rng.uniform(min(xs), max(xs)), rng.uniform(min(ys), max(ys))
            if not self._open_ground(x, y):
                continue
            if fx0 - FARM_MARGIN <= x <= fx1 + FARM_MARGIN and fy0 - FARM_MARGIN <= y <= fy1 + FARM_MARGIN:
                continue
            if math.hypot(x - CAMPUS_SPAWN[0], y - CAMPUS_SPAWN[1]) < SPAWN_CLEARANCE:
                continue
            if any(math.hypot(x - ax, y - ay) < AVOID_RADIUS for ax, ay in avoid):
                continue
            if any(math.hypot(x - px, y - py) < TREE_SPACING for px, py in placed):
                continue
            placed.append((x, y))
        rows = [
            SpawnedTree(player_id=player_id, season=season, scene=rng.choice(scenes),
                        x=round(x, 1), y=round(y, 1))
            for x, y in placed
        ]
        self.db.add_all(rows)
        self.db.flush()
        return rows

    @staticmethod
    def _open_ground(x, y):
        # The trunk and the ground around it must be walkable, clear of the
        # ponds, and not under a building, so a canopy never sits in a wall.
        if at_water(x, y):
            return False
        return all(walkable(x + dx, y + dy) for dx, dy in
                   ((0, 0), (-150, 0), (150, 0), (0, -200), (0, 60)))
