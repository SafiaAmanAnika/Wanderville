"""Export static map polygons in world coordinates. Run after editing the map or its transform."""
import argparse
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CLIENT = ROOT / "code/client"


def nodes(path):
    result = {}
    for block in re.split(r"(?=^\[node )", path.read_text(), flags=re.M)[1:]:
        header = block.splitlines()[0]
        name = re.search(r'name="([^"]+)"', header)[1]
        parent = re.search(r'parent="([^"]+)"', header)
        parent = parent[1] if parent else None
        key = name if parent in (None, ".") else parent + "/" + name
        row = {"parent": parent, "type": re.search(r'type="([^"]+)"', header), "block": block}
        for prop, default in (("position", [0., 0.]), ("scale", [1., 1.])):
            value = re.search(r"^" + prop + r" = Vector2\(([^)]+)\)", block, re.M)
            row[prop] = [float(x) for x in value[1].split(",")] if value else default
        rotation = re.search(r"^rotation = ([^\n]+)", block, re.M)
        row["rotation"] = float(rotation[1]) if rotation else 0.
        result[key] = row
    return result


def transform(point, row):
    x, y = point[0] * row["scale"][0], point[1] * row["scale"][1]
    c, s = math.cos(row["rotation"]), math.sin(row["rotation"])
    return [round(x*c-y*s+row["position"][0], 6), round(x*s+y*c+row["position"][1], 6)]


SEASONS = ("Summer", "Autumn", "Winter", "Spring")
# Each tree scene draws a 128x160 sprite at scale 0.25, centred on the node; the
# trunk meets the ground 72px below the sprite's centre, 18 node units down.
TRUNK = (0.0, 18.0)


def to_world(point, key, scene, world):
    """Carry a point in node ``key``'s space up through the map into the world."""
    node = key
    while node is not None:
        point = transform(point, scene[node])
        node = scene[node]["parent"]
        if node == ".":
            node = "Map"
    for name in ("Map", "World"):
        point = transform(point, world[name])
    return point


def export():
    world_path = CLIENT / "Scenes/world.tscn"
    world = nodes(world_path)
    resource_id = re.search(r'instance=ExtResource\("([^"]+)"\)', world["Map"]["block"])[1]
    scene_path = re.search(r'path="res://([^"]+)" id="' + re.escape(resource_id) + r'"', world_path.read_text())[1]
    scene = nodes(CLIENT / scene_path)
    collision, water, boundary = [], [], []
    for key, row in scene.items():
        polygon = re.search(r'^polygon = PackedVector2Array\(([^)]+)\)', row["block"], re.M)
        parent = scene.get(row["parent"], {})
        if not polygon or not parent.get("type") or parent["type"][1] != "StaticBody2D":
            continue
        values = [float(v) for v in polygon[1].split(",")]
        points = list(zip(values[::2], values[1::2]))
        node = key
        while node is not None:
            points = [transform(point, scene[node]) for point in points]
            node = scene[node]["parent"]
            if node == ".":
                node = "Map"
        for name in ("Map", "World"):
            points = [transform(point, world[name]) for point in points]
        item = {"name": key, "points": points}
        collision.append(item)
        if key.startswith("WaterSource/"):
            water.append(item)
        if key == "CollisionLayer/Collision_border":
            # First four vertices trace the inner edge of the border strip.
            boundary = points[:4]
    if not boundary or not collision:
        raise ValueError("Missing campus boundary or static collision")
    spawn = transform(world["girl"]["position"], world["World"])
    text = (CLIENT / scene_path).read_text()
    resources = dict((rid, path) for path, rid in re.findall(
        r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"', text))
    trees = []
    for key, row in scene.items():
        parts = key.split("/")
        if len(parts) != 3 or parts[0] != "Trees" or parts[1] not in SEASONS:
            continue
        instance = re.search(r'instance=ExtResource\("([^"]+)"\)', row["block"].splitlines()[0])
        x, y = to_world(TRUNK, key, scene, world)
        trees.append({"id": parts[1] + "/" + parts[2], "season": parts[1].lower(),
                      "scene": resources[instance[1]] if instance else "", "x": x, "y": y})
    zone = scene["FarmField/FarmZone/CollisionShape2D"]
    size = [float(v) for v in re.search(
        r'\[sub_resource type="RectangleShape2D" id="' + re.escape(
            re.search(r'SubResource\("([^"]+)"\)', zone["block"])[1]) + r'"\]\nsize = Vector2\(([^)]+)\)',
        text)[1].split(",")]
    corners = [to_world((sx * size[0] / 2, sy * size[1] / 2), "FarmField/FarmZone/CollisionShape2D", scene, world)
               for sx, sy in ((-1, -1), (1, 1))]
    return {"source": scene_path + "; transforms from Scenes/world.tscn", "spawn": spawn,
            "boundary": boundary, "water_reach": 180., "collision": collision, "water": water,
            "tree_reach": 220., "trees": trees, "farm": corners}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    content = json.dumps(export(), indent=2) + "\n"
    targets = [CLIENT / "data/campus_layout.json", ROOT / "code/server/app/modules/world/geometry.json"]
    for path in targets:
        if args.check:
            if not path.exists() or path.read_text() != content:
                raise SystemExit("Stale campus geometry: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    print("Campus geometry matches world.tscn" if args.check else "Exported campus geometry and spawn")
