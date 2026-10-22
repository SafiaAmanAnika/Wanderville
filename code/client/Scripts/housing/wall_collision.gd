extends StaticBody2D
# Builds the wall collision of a house from its "layout" TileMapLayer.
# Every layout tile that is mostly solid (wall, window, post) blocks the player;
# see-through tiles (door gaps, empty spots) stay walkable.
# Repaint the layout and the collision follows automatically - nothing to redraw by hand.

@export var layout_path: NodePath = ^"../layout"
@export_range(0.05, 1.0) var solid_threshold := 0.35   # how much of a tile must be painted to block
@export var show_debug := false                          # draw the blocking boxes in red

var _coverage_cache := {}   # "source:x,y" -> fraction of opaque pixels
var _images := {}           # texture -> Image


func _ready() -> void:
	var layout := get_node_or_null(layout_path) as TileMapLayer
	if layout == null or layout.tile_set == null:
		push_warning("wall_collision: no 'layout' TileMapLayer found")
		return
	position = Vector2.ZERO
	_build(layout)


func _build(layout: TileMapLayer) -> void:
	var tile := Vector2(layout.tile_set.tile_size)
	# 1. which cells are solid, grouped by row
	var rows := {}
	for cell in layout.get_used_cells():
		if _is_solid(layout, cell):
			if not rows.has(cell.y):
				rows[cell.y] = []
			rows[cell.y].append(cell.x)
	# 2. join neighbours in a row into one long box (far fewer shapes than one per tile)
	for y in rows:
		var xs: Array = rows[y]
		xs.sort()
		var start: int = xs[0]
		var prev: int = xs[0]
		for i in range(1, xs.size() + 1):
			var x: int = xs[i] if i < xs.size() else prev + 2   # +2 forces the last run to close
			if x != prev + 1:
				_add_box(layout, Vector2i(start, y), prev - start + 1, tile)
				start = x
			prev = x


func _add_box(layout: TileMapLayer, first: Vector2i, width: int, tile: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width * tile.x, tile.y)
	var box := CollisionShape2D.new()
	box.shape = shape
	# centre of the run, in the layout's coordinates, then moved by the layout's own offset
	var left := layout.map_to_local(first)
	box.position = layout.position + left + Vector2((width - 1) * tile.x / 2.0, 0)
	if show_debug:
		box.debug_color = Color(1, 0, 0, 0.4)
	add_child(box)


# a tile blocks when enough of its pixels are painted
func _is_solid(layout: TileMapLayer, cell: Vector2i) -> bool:
	var source_id := layout.get_cell_source_id(cell)
	var atlas := layout.get_cell_atlas_coords(cell)
	var key := "%d:%d,%d" % [source_id, atlas.x, atlas.y]
	if not _coverage_cache.has(key):
		_coverage_cache[key] = _coverage(layout.tile_set.get_source(source_id), atlas)
	return _coverage_cache[key] >= solid_threshold


func _coverage(source: TileSetSource, atlas: Vector2i) -> float:
	var atlas_source := source as TileSetAtlasSource
	if atlas_source == null or atlas_source.texture == null:
		return 1.0   # unknown kind of tile: treat as wall to be safe
	var image := _image_of(atlas_source.texture)
	if image == null:
		return 1.0
	var region := atlas_source.get_tile_texture_region(atlas)
	var solid := 0
	var total := 0
	for y in range(region.position.y, region.end.y, 2):       # every 2nd pixel is plenty
		for x in range(region.position.x, region.end.x, 2):
			total += 1
			if image.get_pixel(x, y).a > 0.5:
				solid += 1
	return float(solid) / maxf(1.0, total)


func _image_of(texture: Texture2D) -> Image:
	if not _images.has(texture):
		var image := texture.get_image()
		if image and image.is_compressed():
			image.decompress()
		_images[texture] = image
	return _images[texture]
