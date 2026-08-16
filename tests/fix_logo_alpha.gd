extends SceneTree
## Remove logo white/black plateaus while keeping cyan glow + metal faces.


func _init() -> void:
	var path := "res://assets/branding/logo_riftstrike.png"
	var img := Image.new()
	var err := img.load(ProjectSettings.globalize_path(path))
	if err != OK:
		printerr("load failed")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var c0 := img.get_pixel(0, 0)
	print("before corner rgba=%.3f,%.3f,%.3f,%.3f size=%dx%d" % [c0.r, c0.g, c0.b, c0.a, img.get_width(), img.get_height()])
	_clear_plateau(img)
	img = _crop(img, 12, 0.15)
	err = img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		printerr("save failed")
		quit(1)
		return
	var sample := img.get_pixel(0, 0)
	print("FIX_LOGO_ALPHA_OK size=%dx%d corner_a=%.3f" % [img.get_width(), img.get_height(), sample.a])
	quit(0)


func _clear_plateau(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			var maxc := maxf(c.r, maxf(c.g, c.b))
			var minc := minf(c.r, minf(c.g, c.b))
			var sat := 0.0 if maxc < 0.001 else (maxc - minc) / maxc
			var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			# Always drop near-white / near-black flats first.
			if lum >= 0.88 and sat < 0.18:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			if lum <= 0.18 and sat < 0.35:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var is_cyan_glow := c.b > 0.35 and c.b > c.r + 0.08 and c.b > c.g + 0.05
			var is_metal := lum > 0.28 and lum < 0.90 and sat < 0.45
			if is_cyan_glow or is_metal:
				continue
			# Soft gray halo around logo.
			if sat < 0.2 and lum > 0.18 and lum < 0.88:
				img.set_pixel(x, y, Color(0, 0, 0, 0))


func _crop(img: Image, pad: int, alpha_min: float) -> Image:
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
		return img
	min_x = maxi(0, min_x - pad)
	min_y = maxi(0, min_y - pad)
	max_x = mini(w - 1, max_x + pad)
	max_y = mini(h - 1, max_y + pad)
	return img.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
