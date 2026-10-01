"""Static polygon snapshot of the supplied campus map; no client writes."""

import json
from pathlib import Path

GEOMETRY = json.loads(Path(__file__).with_name("geometry.json").read_text())


def inside(x, y, points):
    result = False
    for (a, b), (c, d) in zip(points, points[1:] + points[:1]):
        if (b > y) != (d > y) and x < (c - a) * (y - b) / (d - b) + a:
            result = not result
    return result


def at_water(x, y):
    return any(inside(x, y, p["points"]) for p in GEOMETRY["water"])


def blocked_segment(x, y, nx, ny):
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
