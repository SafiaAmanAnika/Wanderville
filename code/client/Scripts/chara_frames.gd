class_name CharaFrames
# Card picture for the character select screen (first idle frame, facing the camera)

static func portrait(folder: String) -> Texture2D:
	var tex := AtlasTexture.new()
	tex.atlas = load(folder + "/idle.png")
	tex.region = Rect2(140, 130, 170, 200)   # crop around the body
	return tex
