# Pet companions

Open the paw button beside Voice in the world HUD. Choose Cat, Dog, Rabbit,
Fox, Duck or Red Panda. One companion is active at a time. Selection takes
effect immediately and is saved to the signed-in account; offline play uses
`user://pet_companion.cfg`. Restart the backend after updating so the new
`PUT /pets` route is available. No database migration is needed.

The six walking sheets in `code/client/Assets/Pets` are the supplied artwork.
Each sheet has eight directions, eight frames per direction, 128×128 cells,
and plays at 8 FPS. The old collision-free world cat is replaced by the active
companion. Its original avatar assets remain available to existing character
references.

## What the pet decides

Distances below are world pixels, before camera zoom. The companion has four
states: relaxing, following, exploring and sleeping.

1. **Following:** it notices its owner within 750 pixels. Once noticed, it keeps
   tracking until the owner passes 900 pixels. These different enter/leave
   distances prevent flickering between behaviors at the boundary. It begins
   following beyond 220 pixels and settles within 155 pixels. Following moves
   at up to 230 pixels/second, slower than the owner's normal walk,
   and recalculates the route at most once every 0.55 seconds.
2. **Exploring nearby:** after a random 1.5–3.5 second pause, a relaxed pet
   chooses somewhere within 280 pixels of its owner. It walks there at 80
   pixels/second. This gives it room to sniff around instead of standing on
   the owner's feet.
3. **Exploring independently:** when the owner leaves detection range, the
   pet remembers its own current location as a familiar spot. It explores
   within 480 pixels of that spot rather than chasing an unseen owner forever.
   Returning within detection range makes the owner available for following
   again. There is no catch-up teleport through walls.
4. **Sleeping:** after 32 seconds of active time, it takes a nap at the next
   idle pause. It will not stop in the middle of following to sleep. Naps last
   a random 16–26 seconds; an owner leaving its nearby following distance can
   wake it earlier. On waking, its active-time counter resets. Sleeping keeps
   the collision body enabled and position fixed.

## Roaming heuristic

The implementation is `_choose_roam()` in
`code/client/Scripts/pets/pet_companion.gd`.

Each decision samples up to 18 candidate destinations around the current
anchor (owner or familiar spot). Candidates must fit the leash radius, lie
on clear ground, be at least 65 pixels away, and have a reachable route.

The score is:

```
3 × novelty + 2 × clearance + comfort + 0.5 × heading + small random variation
```

- **Novelty:** `1 / (1 + previous visits to the cell)`, so repeatedly visiting
  the same spot becomes less attractive. History is limited to 64 cells.
- **Clearance:** checks open ground 45 pixels to the north, south, east and
  west. Open destinations score higher than cramped corners.
- **Comfort:** prefers a destination roughly 180 pixels from the anchor,
  while respecting the outer leash.
- **Heading:** slightly favors continuing its previous direction, reducing
  abrupt back-and-forth turns.
- **Variation:** a small random value avoids identical-looking decisions.

This is purposeful wandering, not a random direction every frame. The selected
destination remains fixed while the pet walks its route.

Destinations also exclude the owner's personal space. During movement, a
route crossing the owner's body steers around a 115-pixel circle centered on
the character's ground body (the character origin is above it). If the owner
steps into that circle, even an idle/sleeping pet yields. This steering is
needed because the owner moves and is not baked into the navigation grid.

## Species sizes and pace

Sizes are relative to the enlarged cat: dog 112%, fox 104%, red panda 108%,
rabbit 82%, and duck 65%. Walking and sleeping use the same species multiplier;
ground collision circles scale with it. Duck movement is 80% of the base pace,
red panda 90%, rabbit 105%, and the others 100%. World depth sorting replaces
the old forced foreground layer so pets can pass behind characters.

## Paths and collisions

`pet_navigation.gd` builds a shared 64-pixel A* grid from the campus boundary
and exported collision polygons. It checks 20 pixels of body clearance around
each candidate cell. The grid is built in batches over multiple frames so
joining a world does not pause to construct the whole map at once.

Routes use the octile heuristic for eight-direction travel. Diagonals are
allowed only when neighboring cells are clear, so pets cannot cut through
blocked corners. See [Godot's AStarGrid2D documentation](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html).

Pathfinding requests do not set position. A `CharacterBody2D` with an
18-pixel circular ground collider uses `move_and_slide()` to perform actual
movement. It collides with the world and pet collision layer, including while
asleep. The owner's movement collision mask is unchanged, so the companion
does not introduce an obstacle that conflicts with server-owned player movement.

New furniture may not exist in the exported map. On a collision with a small
static obstacle, the exact colliding shape's bounds, expanded for body clearance,
are marked blocked for eight seconds. The pet then replans. Large campus
border polygons are excluded from this update so their bounding boxes cannot
accidentally block a whole courtyard. A separate 1.1-second no-progress check
also abandons a stuck waypoint. The pet never solves an obstacle by teleporting.

## Sleep artwork and anchoring

The generated six-pose atlas is
`code/client/Assets/Pets/generated/sleep_atlas.png`. The generation method,
reference files and exact prompt are recorded beside it in `README.md`.

The atlas is a 3×2 grid: cat, dog, rabbit / fox, duck, red panda. Its transparent
sprite bounds are recorded in `sleep_frames.json`. Each pose is scaled to a
consistent apparent width and anchored using its own ground contact. A gentle
1.5% breathing motion compensates the sprite position so the feet/ground point
does not move. Small floating sleep marks are drawn by code.

## Persistence and scope

`GET /pets` reads the account's existing pet row. `PUT /pets` accepts only the
six asset species and derives ownership from the authenticated player; the
caller cannot supply a different owner. Selecting a species preserves the
existing pet's name, affection and accessories. Pet names, feeding and fetch
continue to use the existing `/pets/actions` endpoints.

The companion is currently a campus client-side simulation. Its species is
persisted on the server; AI positions and sleep state are not replicated to
other clients. It grants no items or progression, and its behavior does not
claim authority over player movement. Server affection and `resting` metadata
remain separate from the visual nap timer. Other scenes do not yet spawn it.

## Verification

- `tests/pet_companions_check.gd`: real-world spawn, six species, eight
  directions each, local save, proximity following, personal space, bounded
  roaming, varied destinations, sleep/wake, wall collision, and recovery around
  a dynamically placed obstacle. A rendered run saves menu/follow/sleep previews
  under `test-output/pets`.
- `tests/gameplay/test_pet_companions.py`: all six server selections persist;
  another account is untouched; unknown species and unauthenticated writes
  are refused. Existing feeding/fetch/ownership tests remain applicable.
- `tests/integration/test_pet_companions.py`: a disposable real account opens
  the world and HUD selector, saves Fox through HTTP, reloads the world, and
  restores Fox. It uses an isolated test database and Godot user profile.
