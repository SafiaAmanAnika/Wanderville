class_name HouseCatalog
# Every price and path for the housing system, in one place.

const OUTER_COST := 10    # outer layer on the map
const WALLS_COST := 15    # inside walls
const FLOOR_COST := 10    # floor

const SELL_AURA_PER_WOOD := 3   # selling: each wood you spent on the house gives back this much Aura
# how much wood was spent on a house, based on how far it was built
static func wood_spent(stage: String) -> int:
	match stage:
		"outer":
			return OUTER_COST
		"walls":
			return OUTER_COST + WALLS_COST
		"done":
			return OUTER_COST + WALLS_COST + FLOOR_COST
	return 0

const FLOORS := ["original", "chestnut", "walnut", "honey", "ash"]

# a color for each floor button
const FLOOR_SWATCH := {
	"original": Color("ff659dff"),
	"chestnut": Color("#7E5032"),
	"walnut": Color("#463025"),
	"honey": Color("#CC9865"),
	"ash": Color("#C5B4A3"),
}

const EXTERIOR_SCALE := 6.0              # house_N.png is only 192 x 128 — scale it up on the map
const INTERIOR_POSITION := Vector2(60000, 0)   # where the inside lives, far from the map


static func interior_scene(id: int) -> PackedScene:
	return load("res://Scenes/house%d.tscn" % id)


static func exterior_texture(id: int) -> Texture2D:
	return load("res://Assets/house/house%d/house_%d.png" % [id, id])
