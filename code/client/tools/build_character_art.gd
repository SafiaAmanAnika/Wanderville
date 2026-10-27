extends SceneTree
## Offline pixel-preserving registration and idle-limb walk authoring.
## Run in an empty project, passing the client directory and output directory.
const CAST := ["CharacterA", "CharacterA_Male", "CharacterB", "CharacterB_Male", "CharacterC", "CharacterC_Male"]
const FILES := ["idle", "run", "hoe", "watering_can", "fishing", "scythe"]
const CELL := 448
const GROUND := 321
var client: String
var output: String
var manifest: Dictionary = {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Pass -- <client directory> <output directory>")
		quit(1)
		return
	client = args[0]
	output = args[1]
	for character in CAST:
		build_character(character)
	var file := FileAccess.open(output.path_join("registration.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	print("CHARACTER_ART_BUILD characters=", CAST.size(), " output=", output)
	quit()

func source(character: String, action: String) -> Image:
	return Image.load_from_file(client.path_join("Assets/charas").path_join(character).path_join(action + ".png"))

func build_character(character: String) -> void:
	var folder := output.path_join(character)
	DirAccess.make_dir_recursive_absolute(folder)
	manifest[character] = {}
	for action in FILES:
		var sheet := source(character, action)
		var result := Image.create(CELL * 6, CELL * 8, false, Image.FORMAT_RGBA8)
		var entries: Array = []
		for row in 8:
			for frame in 6:
				var cell := sheet.get_region(Rect2i(frame * CELL, row * CELL, CELL, CELL))
				var contact := sole(cell, action)
				var shift := GROUND - contact
				# Leave subpixel antialias/sole-outline differences alone in tools.
				if action != "run" and absi(shift) <= 2:
					shift = 0
				var used := cell.get_used_rect()
				assert(used.position.y + shift >= 0 and used.end.y + shift <= CELL, "Registration must never clip source pixels")
				result.blit_rect(cell, Rect2i(0, 0, CELL, CELL), Vector2i(frame * CELL, row * CELL + shift))
				if shift != 0:
					entries.append({"row":row, "frame":frame, "translation_y":shift, "source_sole":contact})
		assert(result.save_png(folder.path_join(action + ".png")) == OK)
		manifest[character][action] = entries
	var idle := source(character, "idle")
	var walk := Image.create(CELL * 6, CELL * 8, false, Image.FORMAT_RGBA8)
	for row in 8:
		for frame in 6:
			var standing := idle.get_region(Rect2i(frame * CELL, row * CELL, CELL, CELL))
			walk.blit_rect(walk_pose(standing, row, frame, character), Rect2i(0, 0, CELL, CELL), Vector2i(frame * CELL, row * CELL))
	assert(walk.save_png(folder.path_join("walk.png")) == OK)

func sole(cell: Image, action: String) -> int:
	# Run/idle contain only the character: their lowest opaque pixel is a sole.
	# Tool blades, rods and water must not participate in that measurement.
	if action in ["idle", "run"]:
		for y in range(CELL - 1, 0, -1):
			for x in CELL:
				if cell.get_pixel(x, y).a > 0.5:
					return y + 1
	else:
		# Boot leather is warm dark brown in all six original palettes. Require a
		# horizontal patch rather than a narrow wooden tool shaft or loose pixel.
		for y in range(355, 294, -1):
			var count := 0
			for x in range(145, 304):
				var color := cell.get_pixel(x, y)
				if color.a > 0.5 and color.r8 > 20 and color.r8 < 165 and color.r > color.g * 1.15 and color.g > color.b * 1.1:
					count += 1
			if count >= 8:
				return y + 1
	return GROUND

func walk_pose(standing: Image, row: int, frame: int, character: String) -> Image:
	# Six poses, alternating contact / passing / recovery. Only the legs are
	# articulated; faces, hair, hats, clothing palette and body proportions stay.
	var phase := float(frame) * TAU / 6.0
	var stride := cos(phase)
	var side := absf(sin(float(row) * PI / 4.0))
	var split_y := 276 if character == "CharacterC" else 270
	var lower := standing.get_region(Rect2i(0, split_y, CELL, GROUND - split_y))
	var bounds := lower.get_used_rect()
	var middle := (bounds.position.x + bounds.end.x) / 2
	var left := Rect2i(bounds.position.x, split_y, middle - bounds.position.x, GROUND - split_y)
	var right := Rect2i(middle, split_y, bounds.end.x - middle, GROUND - split_y)
	var result := standing.duplicate() as Image
	result.fill_rect(Rect2i(bounds.position.x, split_y, bounds.size.x, CELL - split_y), Color.TRANSPARENT)
	var amplitude := lerpf(3.0, 15.0, side)
	var first := left if stride > 0.0 else right
	var second := right if stride > 0.0 else left
	leg(result, standing, first, (-1.0 if first == left else 1.0) * stride, amplitude, maxf(0.0, sin(phase) * (-1.0 if first == left else 1.0)) * 6.0)
	leg(result, standing, second, (-1.0 if second == left else 1.0) * stride, amplitude, maxf(0.0, sin(phase) * (-1.0 if second == left else 1.0)) * 6.0)
	# Match sole contact after rotating the legs. This changes source pixels,
	# never runtime collision bodies, cameras or atlas sampling windows.
	var bottom := sole(result, "run")
	if bottom != GROUND:
		var grounded := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
		grounded.blit_rect(result, Rect2i(0, 0, CELL, CELL), Vector2i(0, GROUND - bottom))
		return grounded
	return result

func leg(target: Image, standing: Image, rect: Rect2i, stride: float, amplitude: float, lift: float) -> void:
	var hip := Vector2(rect.get_center().x, rect.position.y)
	var length := float(rect.size.y)
	for y in range(rect.position.y, GROUND + 2):
		for x in range(rect.position.x - 20, rect.end.x + 20):
			var fraction := clampf((y - hip.y) / maxf(1.0, length - lift), 0.0, 1.0)
			var source_x := roundi(x - stride * amplitude * fraction)
			var source_y := roundi(hip.y + (y - hip.y) * length / (length - lift))
			if rect.has_point(Vector2i(source_x, source_y)):
				var color := standing.get_pixel(source_x, source_y)
				if color.a > 0.0:
					target.set_pixel(x, y, color)
