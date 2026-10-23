"""Static polygon snapshot of the supplied campus map; no client writes."""

import json
import math
from pathlib import Path

GEOMETRY = json.loads(Path(__file__).with_name("geometry.json").read_text())


def inside(x, y, points):
    result = False
    for (a, b), (c, d) in zip(points, points[1:] + points[:1]):
        if (b > y) != (d > y) and x < (c - a) * (y - b) / (d - b) + a:
            result = not result
    return result


def walkable(x, y):
    return (math.isfinite(x) and math.isfinite(y)
            and inside(x, y, GEOMETRY["boundary"])
            and not any(inside(x, y, p["points"]) for p in GEOMETRY["collision"]))


def distance_to_segment(x, y, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = dx * dx + dy * dy
    t = max(0., min(1., ((x-a[0])*dx + (y-a[1])*dy) / length)) if length else 0.
    return math.hypot(x-a[0]-t*dx, y-a[1]-t*dy)


def at_water(x, y):
    # Players stand beside solid pond banks, rather than inside them.
    reach = GEOMETRY["water_reach"]
    return any(inside(x, y, p["points"]) or any(
        distance_to_segment(x, y, a, b) <= reach
        for a, b in zip(p["points"], p["points"][1:] + p["points"][:1])
    ) for p in GEOMETRY["water"])


def blocked_segment(x, y, nx, ny):
    if not inside(nx, ny, GEOMETRY["boundary"]):
        return True

    def cross(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    for polygon in GEOMETRY["collision"]:
        points = polygon["points"]
        if inside(nx, ny, points):
            return True
        for a, b in zip(points, points[1:] + points[:1]):
            p, q = (x, y), (nx, ny)
            if (
                cross(p, q, a) * cross(p, q, b) < 0
                and cross(a, b, p) * cross(a, b, q) < 0
            ):
                return True
    return False
