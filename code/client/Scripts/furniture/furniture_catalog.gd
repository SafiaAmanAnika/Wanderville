class_name FurnitureCatalog
extends RefCounted
# Reads Assets/furniture/furniture_manifest.json once, then answers questions about it.
#   info("wooden_chair")              -> that item's whole record
#   texture("wooden_chair", "left")   -> the picture for one direction
#   cost("wooden_chair")              -> its price in wood
#   make("wooden_chair")              -> a ready-to-place FurnitureItem (null if unknown)
#   items_in_tab("seating")           -> every item on that tab of the menu

const BASE := "res://Assets/furniture/"
const DIRS := ["front", "left", "back", "right"]
const MANIFEST := BASE + "furniture_manifest.json"

# the furniture menu's tabs, in the order they are shown
const TABS := ["seating", "tables_storage", "bedroom", "kitchen", "bathroom",
	"lights", "decor", "tabletop", "devices", "gym", "gym_small_items"]

const TAB_NAMES := {
	"seating": "Seating",
	"tables_storage": "Tables & Storage",
	"bedroom": "Bedroom",
	"kitchen": "Kitchen",
	"bathroom": "Bathroom",
	"lights": "Lights",
	"decor": "Decor",
	"tabletop": "Tabletop",
	"devices": "Devices",
	"gym": "Gym",
	"gym_small_items": "Gym Bits",
}

static var _items := {}      # item id -> its record from the manifest
static var _read := false


# reads the manifest the first time anything is asked of this catalog
static func _read_manifest() -> void:
	if _read:
		return
	_read = true
	if not FileAccess.file_exists(MANIFEST):
		push_error("FurnitureCatalog: cannot find " + MANIFEST)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not (data is Dictionary):
		push_error("FurnitureCatalog: cannot read " + MANIFEST)
		return
	for item in data.get("items", []):
		_items[String(item.get("id", ""))] = item


# one item's whole record; an empty dictionary if the pack has no such item
static func info(id: String) -> Dictionary:
	_read_manifest()
	return _items.get(id, {})


# every item on one tab, in the order the manifest lists them
static func items_in_tab(tab: String) -> Array:
	_read_manifest()
	var out := []
	for id in _items:
		if String(_items[id].get("category", "")) == tab:
			out.append(_items[id])
	return out


# the picture for one direction (falls back to the front view)
static func texture(id: String, dir: String = "front") -> Texture2D:
	var files: Dictionary = info(id).get("files", {})
	var path := String(files.get(dir, files.get("front", "")))
	if path == "":
		return null
	return load(BASE + path) as Texture2D


# the small picture on a menu button; takes an item record or just an id
static func icon(item) -> Texture2D:
	var id := String(item.get("id", "")) if item is Dictionary else String(item)
	return texture(id, "front")


# how much wood this item costs
static func cost(id: String) -> int:
	return int(info(id).get("wood_cost", 0))


# builds a ready-to-place piece of furniture; null if the pack has no such item
static func make(id: String, dir: String = "front") -> FurnitureItem:
	if info(id).is_empty():
		return null
	var piece := FurnitureItem.new()
	piece.setup(id, dir)
	return piece
