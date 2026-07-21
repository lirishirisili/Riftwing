extends SceneTree
## One-shot: circular + chroma key so planet_rift_accent has real transparency.
## godot --headless --path . --script res://tools/fix_planet_alpha.gd


const SRC := "res://assets/backgrounds/planet_rift_accent.png"
const OUT_ABS := "C:/Users/liron/Riftwing/assets/backgrounds/planet_rift_accent.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var img := Image.new()
	var err := img.load(SRC)
	if err != OK:
		printerr("load failed %s" % err)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)

	var w := img.get_width()
	var h := img.get_height()
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	var body_r := mini(w, h) * 0.42
	var glow_r := mini(w, h) * 0.455
	var feather := mini(w, h) * 0.02

	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var dx := float(x) - cx
			var dy := float(y) - cy
			var dist := sqrt(dx * dx + dy * dy)
			var luma := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			var mx := maxf(c.r, maxf(c.g, c.b))
			var mn := minf(c.r, minf(c.g, c.b))
			var sat := mx - mn
			# Purple/magenta/cyan rim contribution (moon + glow).
			var moonish: float = clampf(maxf(c.b, c.r) * 1.35 - c.g * 0.55, 0.0, 1.0)

			var a := 1.0
			if dist >= glow_r + feather:
				a = 0.0
			elif dist > glow_r:
				a = 1.0 - ((dist - glow_r) / feather)
			elif dist > body_r:
				# Soft glow ring: keep only tinted pixels, drop checkerboard grays.
				var t := (dist - body_r) / maxf(0.001, glow_r - body_r)
				var keep := clampf(moonish * 1.4 + sat * 1.8 - luma * 0.35, 0.0, 1.0)
				a = keep * (1.0 - t * 0.35)
			else:
				# Body: kill leftover checkerboard blacks only.
				if luma < 0.035 and sat < 0.03 and moonish < 0.04:
					a = 0.0

			# Global key for baked checkerboard cells.
			if sat < 0.04 and luma < 0.09 and moonish < 0.06 and dist > body_r * 0.85:
				a = 0.0

			c.a = clampf(a, 0.0, 1.0)
			# Premultiply-ish cleanup so dark RGB cannot flash through.
			if c.a < 0.02:
				c = Color(0, 0, 0, 0)
			img.set_pixel(x, y, c)

	err = img.save_png(OUT_ABS)
	if err != OK:
		printerr("save failed %s" % err)
		quit(1)
		return
	print("PLANET_ALPHA_FIXED %dx%d" % [w, h])
	quit(0)
