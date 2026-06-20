extends Node3D
## World setup for the floating-island mower prototype.
##
## Art direction borrowed from the sibling `delivery-game` bible (procedural
## geometry, zero image assets) and reimplemented for Godot:
##   - Forward+ post stack: ACES tone mapping, exposure 1.25, glow/bloom, SSAO.
##   - Warm key light (#f6e4ca) + cool ambient fill — golden-hour discipline.
##   - Per-instance HSL + roughness variance so nothing looks stamped.
##   - Emissive accents (blooming stars, glowing island crystals).
##   - Beveled geometry helper so blocks read soft, not hard-edged.
##   - A REAL organic floating island (wobbly coast, cliff, tapering rock) with
##     a triplanar procedural normal map for tactile surface.
##   - Orthographic low-angle diorama camera that follows the player (no sway).
##
## The island's outline is island_radius(angle); grass and the player both query
## it so everything matches the real coastline.

const ISLAND_RADIUS := 12.0        # base radius of the island, in world units

var player: Node3D
var grass: Node3D
var camera: Camera3D

const CAM_OFFSET := Vector3(0.0, 13.0, 7.0)
const CAM_SIZE := 18.0             # orthographic vertical extent (smaller = closer)


func _ready() -> void:
	_build_environment()
	_build_starfield()
	_build_sun()
	_build_island()

	player = preload("res://Player.gd").new()
	add_child(player)

	grass = preload("res://GrassField.gd").new()
	grass.player = player
	add_child(grass)

	var hud := preload("res://Hud.gd").new()
	add_child(hud)

	player.swing.connect(grass.on_swing)
	grass.mowed_changed.connect(hud.set_count)

	_build_camera()


# --- the island shape -------------------------------------------------------

static func island_radius(angle: float) -> float:
	return ISLAND_RADIUS * (
		1.0
		+ 0.16 * sin(3.0 * angle + 0.7)
		+ 0.09 * sin(5.0 * angle - 1.3)
		+ 0.06 * sin(7.0 * angle + 2.1)
	)


# --- world pieces -----------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.03)            # deep space
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.46, 0.62)          # cool fill
	env.ambient_light_energy = 0.45

	# Tone mapping + exposure — the single biggest "feel" lever.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.25

	# Glow / bloom so emissive accents and bright highlights pop.
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.05
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.95
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 1.0)
	env.set_glow_level(5, 1.0)

	# SSAO grounds objects (grass into soil, player onto ground).
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 2.5
	env.ssao_power = 1.5

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_starfield() -> void:
	var star_mesh := BoxMesh.new()
	star_mesh.size = Vector3(0.6, 0.6, 0.6)

	# Emissive + over-bright so the glow pass blooms them into twinkles.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.93, 1.0)
	mat.emission_energy_multiplier = 2.6
	star_mesh.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_mesh
	mm.instance_count = 500

	var rng := RandomNumberGenerator.new()
	rng.seed = 20240620
	for i in mm.instance_count:
		var dir := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		var radius := rng.randf_range(80.0, 150.0)
		var s := rng.randf_range(0.4, 1.4)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), dir * radius))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _build_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.965, 0.894, 0.792)   # warm cream (#f6e4ca)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	add_child(sun)


func _build_island() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var seg := 60

	var grass_col := Color(0.34, 0.56, 0.25)
	var dirt_col := Color(0.42, 0.29, 0.17)
	var rock_a := Color(0.37, 0.37, 0.41)
	var rock_b := Color(0.29, 0.28, 0.31)

	var rings := [
		{"rs": 1.00, "y": 0.0},
		{"rs": 0.97, "y": -2.6},
		{"rs": 0.74, "y": -5.6},
		{"rs": 0.44, "y": -8.4},
		{"rs": 0.20, "y": -10.6},
	]
	var band_cols := [dirt_col, rock_a, rock_b, rock_a]
	var apex := Vector3(0.0, -12.6, 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in seg:
		var v0 := _ring_vertex(rings[0]["rs"], rings[0]["y"], i, seg)
		var v1 := _ring_vertex(rings[0]["rs"], rings[0]["y"], (i + 1) % seg, seg)
		_add_tri(st, Vector3.ZERO, v1, v0, vary_color(grass_col, rng), Vector3.UP)

	for k in range(rings.size() - 1):
		for i in seg:
			var a := _ring_vertex(rings[k]["rs"], rings[k]["y"], i, seg)
			var b := _ring_vertex(rings[k]["rs"], rings[k]["y"], (i + 1) % seg, seg)
			var c := _ring_vertex(rings[k + 1]["rs"], rings[k + 1]["y"], i, seg)
			var d := _ring_vertex(rings[k + 1]["rs"], rings[k + 1]["y"], (i + 1) % seg, seg)
			_add_tri(st, a, b, c, vary_color(band_cols[k], rng), _outward(a, b, c))
			_add_tri(st, b, d, c, vary_color(band_cols[k], rng), _outward(b, d, c))

	var last: Dictionary = rings[rings.size() - 1]
	for i in seg:
		var c := _ring_vertex(last["rs"], last["y"], i, seg)
		var d := _ring_vertex(last["rs"], last["y"], (i + 1) % seg, seg)
		_add_tri(st, apex, c, d, vary_color(rock_b, rng), Vector3.DOWN)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _island_material()
	add_child(mi)

	_scatter_surface_rocks(rng)


## Vertex-colour material with a triplanar procedural normal map for tactile
## surface detail (no UVs needed — projected by world position).
func _island_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.9
	var ntex := NoiseTexture2D.new()
	ntex.width = 256
	ntex.height = 256
	ntex.seamless = true
	ntex.as_normal_map = true
	ntex.bump_strength = 1.6
	ntex.noise = noise

	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.normal_enabled = true
	m.normal_texture = ntex
	m.normal_scale = 0.7
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.18, 0.18, 0.18)
	return m


func _ring_vertex(rs: float, y: float, i: int, seg: int) -> Vector3:
	var ang := TAU * float(i) / float(seg)
	var r := island_radius(ang) * rs
	return Vector3(r * cos(ang), y, r * sin(ang))


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, ref: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.000001:
		return
	n = n.normalized()
	if n.dot(ref) < 0.0:
		n = -n
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)


func _outward(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ctr := (a + b + c) / 3.0
	ctr.y = 0.0
	if ctr.length() < 0.001:
		return Vector3.UP
	return ctr.normalized()


func _scatter_surface_rocks(rng: RandomNumberGenerator) -> void:
	for i in 10:
		var ang := rng.randf_range(0.0, TAU)
		var maxr := island_radius(ang) - 1.2
		if maxr < 1.0:
			continue
		var d := rng.randf_range(0.0, maxr)
		var rs := rng.randf_range(0.35, 0.75)
		var m := StandardMaterial3D.new()
		m.albedo_color = vary_color(Color(0.36, 0.36, 0.40), rng)
		m.roughness = clampf(0.9 + rng.randf_range(-0.08, 0.05), 0.0, 1.0)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mb := MeshInstance3D.new()
		mb.mesh = make_beveled_box(Vector3(rs, rs * 0.7, rs), 0.08)
		mb.material_override = m
		mb.position = Vector3(cos(ang) * d, 0.04, sin(ang) * d)
		mb.rotation.y = rng.randf_range(0.0, TAU)
		add_child(mb)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL   # clean diorama look
	camera.size = CAM_SIZE
	camera.position = player.global_position + CAM_OFFSET
	camera.rotation = Vector3(-atan2(CAM_OFFSET.y, CAM_OFFSET.z), 0.0, 0.0)
	camera.current = true
	add_child(camera)


func _process(_delta: float) -> void:
	if player == null or camera == null:
		return
	camera.global_position = player.global_position + CAM_OFFSET


# --- shared building blocks (reused by Player & GrassField) -----------------

## Per-instance HSL + (caller-applied) roughness variance — the delivery-game
## convention: ~±0.04 hue, ±0.06 sat, ±0.08 value so adjacent surfaces differ.
static func vary_color(c: Color, rng: RandomNumberGenerator) -> Color:
	var h := fposmod(c.h + rng.randf_range(-0.04, 0.04), 1.0)
	var s := clampf(c.s + rng.randf_range(-0.06, 0.06), 0.0, 1.0)
	var v := clampf(c.v + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	return Color.from_hsv(h, s, v, c.a)


static func make_pixel_texture(base: Color, contrast: float, rng_seed: int, size: int = 16) -> ImageTexture:
	return make_speckled_texture(base, contrast, base, 0.0, rng_seed, size)


static func make_speckled_texture(base: Color, contrast: float, speck: Color, speck_chance: float, rng_seed: int, size: int = 24) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for y in size:
		for x in size:
			var c: Color
			if rng.randf() < speck_chance:
				var s := rng.randf_range(-contrast, contrast)
				c = Color(clampf(speck.r + s, 0, 1), clampf(speck.g + s, 0, 1), clampf(speck.b + s, 0, 1), 1.0)
			else:
				var d := rng.randf_range(-contrast, contrast)
				c = Color(clampf(base.r + d, 0, 1), clampf(base.g + d, 0, 1), clampf(base.b + d, 0, 1), 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func make_gradient_texture(bottom: Color, top: Color, rng_seed: int) -> ImageTexture:
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


static func make_material(tex: Texture2D, uv_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	m.roughness = 1.0
	m.metallic = 0.0
	return m


# --- beveled box (soft, less-blocky geometry) -------------------------------

## A chamfered box: 6 inset faces + 12 edge chamfers + 8 corner triangles.
## Normals are set outward per-tri; pair with a CULL_DISABLED material so the
## solid renders regardless of winding.
static func make_beveled_box(size: Vector3, bevel: float) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b: float = min(bevel, min(hx, min(hy, hz)) * 0.85)

	var px := {}
	var py := {}
	var pz := {}
	for i in 2:
		for j in 2:
			for k in 2:
				var sx := -1.0 if i == 0 else 1.0
				var sy := -1.0 if j == 0 else 1.0
				var sz := -1.0 if k == 0 else 1.0
				var key := Vector3i(i, j, k)
				px[key] = Vector3(sx * hx, sy * (hy - b), sz * (hz - b))
				py[key] = Vector3(sx * (hx - b), sy * hy, sz * (hz - b))
				pz[key] = Vector3(sx * (hx - b), sy * (hy - b), sz * hz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 6 inset faces
	_bev_quad(st, px[Vector3i(1,1,1)], px[Vector3i(1,1,0)], px[Vector3i(1,0,0)], px[Vector3i(1,0,1)])
	_bev_quad(st, px[Vector3i(0,1,1)], px[Vector3i(0,0,1)], px[Vector3i(0,0,0)], px[Vector3i(0,1,0)])
	_bev_quad(st, py[Vector3i(1,1,1)], py[Vector3i(0,1,1)], py[Vector3i(0,1,0)], py[Vector3i(1,1,0)])
	_bev_quad(st, py[Vector3i(1,0,1)], py[Vector3i(1,0,0)], py[Vector3i(0,0,0)], py[Vector3i(0,0,1)])
	_bev_quad(st, pz[Vector3i(1,1,1)], pz[Vector3i(1,0,1)], pz[Vector3i(0,0,1)], pz[Vector3i(0,1,1)])
	_bev_quad(st, pz[Vector3i(1,1,0)], pz[Vector3i(0,1,0)], pz[Vector3i(0,0,0)], pz[Vector3i(1,0,0)])

	# 12 edge chamfers
	for i in 2:
		for j in 2:
			var e0 := Vector3i(i, j, 0)
			var e1 := Vector3i(i, j, 1)
			_bev_quad(st, px[e0], py[e0], py[e1], px[e1])
	for i in 2:
		for k in 2:
			var f0 := Vector3i(i, 0, k)
			var f1 := Vector3i(i, 1, k)
			_bev_quad(st, px[f0], pz[f0], pz[f1], px[f1])
	for j in 2:
		for k in 2:
			var g0 := Vector3i(0, j, k)
			var g1 := Vector3i(1, j, k)
			_bev_quad(st, py[g0], pz[g0], pz[g1], py[g1])

	# 8 corner triangles
	for i in 2:
		for j in 2:
			for k in 2:
				var key := Vector3i(i, j, k)
				_bev_tri(st, px[key], py[key], pz[key])

	return st.commit()


static func _bev_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.000001:
		return
	n = n.normalized()
	var ref := a + b + c                 # centroid direction from origin == outward
	if n.dot(ref) < 0.0:
		n = -n
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


static func _bev_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_bev_tri(st, a, b, c)
	_bev_tri(st, a, c, d)
