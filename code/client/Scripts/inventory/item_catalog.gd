class_name ItemCatalog
# Names, prices and seasons for every item, so the storage menu works offline too.
# Online, the server's own values (row["item"]) are used first; this is the fallback.
# Crop prices copy server/app/db/catalog.json. Seeds follow the server rule:
#   seed buy price = half the crop's sell price (min 2), seed sells for 1.

# crop code: [name, season, sell price]
const CROPS := {
	"paddy": ["Paddy", "all", 10], "wheat": ["Wheat", "all", 12],
	"sugarcane": ["Sugarcane", "all", 15], "barley": ["Barley", "all", 12],
	"oats": ["Oats", "all", 12], "sweet_corn": ["Sweet Corn", "summer", 25],
	"zucchini": ["Zucchini", "summer", 15], "bell_pepper": ["Bell Pepper", "summer", 22],
	"strawberry": ["Strawberry", "summer", 28], "green_bean": ["Green Bean", "summer", 18],
	"pumpkin": ["Pumpkin", "autumn", 30], "brussels_sprouts": ["Brussels Sprouts", "autumn", 26],
	"kale": ["Kale", "autumn", 17], "apple": ["Apple", "autumn", 35],
	"turnip": ["Turnip", "autumn", 15], "potato": ["Potato", "winter", 20],
	"carrot": ["Carrot", "winter", 16], "cabbage": ["Cabbage", "winter", 18],
	"spinach": ["Spinach", "winter", 12], "onion": ["Onion", "winter", 23],
	"lettuce": ["Lettuce", "spring", 14], "pea": ["Pea", "spring", 16],
	"radish": ["Radish", "spring", 12], "asparagus": ["Asparagus", "spring", 28],
	"beetroot": ["Beetroot", "spring", 18], "moonflower": ["Moonflower", "all", 100],
	"rivermint": ["Rivermint", "all", 80], "sunbloom": ["Sunbloom", "all", 90],
	"ancient_grain": ["Ancient Grain", "all", 120]
}

# fish from the fishing mini game: [name, sell price]
const FISH := {
	"bluegill": ["Bluegill", 8], "carp": ["Carp", 10], "catfish": ["Catfish", 14], "koi": ["Koi", 25],
	"largemouth_bass": ["Largemouth Bass", 16], "pufferfish": ["Pufferfish", 20], "rainbow_trout": ["Rainbow Trout", 15],
	"salmon": ["Salmon", 18], "seahorse": ["Seahorse", 30], "sunfish": ["Sunfish", 9],
	"river_carp": ["River Carp", 12], "golden_carp": ["Golden Carp", 60],   # server fish
}

# everything else: [name, buy price (0 = can't buy), sell price, description]
const MISC := {
	"pet_biscuit": ["Pet Biscuit", 5, 1, "A crunchy treat for your pet."],
	"pet_ribbon": ["Pet Ribbon", 25, 5, "A cute ribbon your pet can wear."],
	"garden_lantern": ["Garden Lantern", 30, 5, "Lights up your garden at night."],
	"basic_rod": ["Basic Fishing Rod", 10, 2, "A simple rod for the campus lake."],
	"lake_pearl": ["Lake Pearl", 0, 90, "A rare pearl found in the lake."],
	"wood": ["Wood", 3, 1, "Used to build houses, furnitures."],
}


# Which room of the storage house an item belongs to: "crops", "seeds", "fish" or "misc"
static func section_of(code: String, category := "") -> String:
	if code.ends_with("_seed") or category == "seed":
		return "seeds"
	if FISH.has(code) or category == "fish":
		return "fish"
	if CROPS.has(code) or category.ends_with("crop") or category == "rare_plant":
		return "crops"
	return "misc"


# One item's info: {name, description, buy (0 = can't buy), sell, season}
static func info(code: String) -> Dictionary:
	if code.ends_with("_seed"):
		var crop := code.trim_suffix("_seed")
		if CROPS.has(crop):
			var c: Array = CROPS[crop]
			return {"name": "%s Seeds" % c[0], "description": "Plant to grow %s." % c[0],
				"buy": maxi(2, int(c[2]) / 2), "sell": 1, "season": c[1]}
	if CROPS.has(code):
		var c: Array = CROPS[code]
		return {"name": c[0], "description": "Freshly harvested %s." % c[0], "buy": 0, "sell": c[2], "season": c[1]}
	if FISH.has(code):
		var f: Array = FISH[code]
		return {"name": f[0], "description": "A %s caught in the campus lake." % f[0], "buy": 0, "sell": f[1], "season": "all"}
	if MISC.has(code):
		var m: Array = MISC[code]
		return {"name": m[0], "description": m[3], "buy": m[1], "sell": m[2], "season": "all"}
	return {"name": code.replace("_", " ").capitalize(), "description": "", "buy": 0, "sell": 0, "season": "all"}


# All seed codes you can buy in this season ("all"-season seeds always count)
static func seeds_for_season(season: String) -> Array:
	var out := []
	for crop in CROPS:
		var s: String = CROPS[crop][1]
		if s == season or s == "all":
			out.append(crop + "_seed")
	return out
