extends RefCounted
## Procedural textures for the crisp, pixelated look — no image assets.
## Reference via `const TextureFactory := preload(...)`.

## Vertical gradient (darker base -> lighter tip) with light noise, for grass.
static func gradient(bottom: Color, top: Color, rng_seed: int) -> ImageTexture:
	var w := 4
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for y in h:
		var t := 1.0 - float(y) / float(h - 1)
		var base := bottom.lerp(top, t)
		for x in w:
			var d := rng.randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(clampf(base.r + d, 0, 1), clampf(base.g + d, 0, 1), clampf(base.b + d, 0, 1), 1.0))
	return ImageTexture.create_from_image(img)


## Matte material with NEAREST filtering so pixels stay sharp; uv_scale tiles
## the little texture across big faces.
static func material(tex: Texture2D, uv_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	m.roughness = 1.0
	m.metallic = 0.0
	return m
