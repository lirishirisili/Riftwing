extends SceneTree
## Strip solid black/white plateaus and crop to opaque content.


func _init() -> void:
	var jobs: Array = [
		{"path": "res://assets/branding/logo_riftwing.png", "modes": ["white", "black"], "white_t": 0.90, "black_t": 0.12, "crop": true, "pad": 10, "alpha_crop": 0.2},
		{"path": "res://assets/ui/chrome/cta_start_plate.png", "modes": ["white", "black"], "white_t": 0.86, "black_t": 0.05, "crop": true, "pad": 6, "alpha_crop": 0.25},
		{"path": "res://assets/ui/chrome/cta_daily_plate.png", "modes": ["white", "black"], "white_t": 0.86, "black_t": 0.05, "crop": true, "pad": 6, "alpha_crop": 0.28},
		{"path": "res://assets/ui/chrome/cta_nav_plate.png", "modes": ["white", "black"], "white_t": 0.86, "black_t": 0.05, "crop": true, "pad": 6, "alpha_crop": 0.25},
		{"path": "res://assets/art/ships/hero_vanguard_menu.png", "modes": ["black"], "white_t": 0.95, "black_t": 0.08, "crop": true, "pad": 14, "alpha_crop": 0.15},
	]
	for job in jobs:
		var path: String = job["path"]
		var img := Image.new()
		var err := img.load(ProjectSettings.globalize_path(path))
		if err != OK:
			printerr("load failed %s err=%s" % [path, err])
			quit(1)
			return
		img.convert(Image.FORMAT_RGBA8)
		var modes: Array = job["modes"]
		for mode in modes:
			if String(mode) == "white":
				_strip(img, "white", float(job["white_t"]))
			else:
				_strip(img, "black", float(job["black_t"]))
		if bool(job.get("crop", false)):
			img = _crop_opaque(img, int(job.get("pad", 4)), float(job.get("alpha_crop", 0.2)))
			if img == null:
				printerr("crop failed %s" % path)
				quit(1)
				return
		err = img.save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			printerr("save failed %s err=%s" % [path, err])
			quit(1)
			return
		print("processed %s size=%dx%d" % [path, img.get_width(), img.get_height()])
	print("STRIP_ASSET_BG_OK")
	quit(0)


func _strip(img: Image, mode: String, threshold: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			var kill := false
			if mode == "white":
				kill = lum >= threshold and absf(c.r - c.g) < 0.12 and absf(c.g - c.b) < 0.12
			else:
				kill = lum <= threshold
			if kill:
				img.set_pixel(x, y, Color(0, 0, 0, 0))


func _crop_opaque(img: Image, pad: int, alpha_min: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a >= alpha_min:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return null
	min_x = maxi(0, min_x - pad)
	min_y = maxi(0, min_y - pad)
	max_x = mini(w - 1, max_x + pad)
	max_y = mini(h - 1, max_y + pad)
	return img.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
