extends Node3D
## World setup for the floating-island mower prototype.
##
## Builds everything procedurally so the project needs no imported assets:
##   - a near-black "space" environment with a scattered starfield
##   - a sun (directional light) for shading
##   - a REAL floating island: an organic, wobbly-coastline landmass with a flat
##     grassy top, cliff sides and a tapering rocky underside (low-poly mesh)
##   - the Player and the GrassField, wired together via signals
##   - a steep, fixed-angle top-down camera that follows the player (no sway)
##
## The island's outline is defined by island_radius(angle); the grass and the
## player both query it so everything matches the real coastline.

const ISLAND_RADIUS := 12.0        # base radius of the island, in world units

var player: Node3D
var grass: Node3D
var camera: Camera3D

# Steep, high top-down framing, pulled in close. Pitch is derived from the
# offset so the camera always points at the player; position follows directly
# (no look_at, no lerp) which keeps the view rock-steady while moving.
const CAM_OFFSET := Vector3(0.0, 13.0, 7.0)


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

## Organic coastline: base radius modulated by a few sine waves so the outline
## wobbles like a real island instead of being a circle (or a square). Shared by
## the grass planter and the player's edge clamp.
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
	env.background_color = Color(0.015, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.65)
	env.ambient_light_energy = 0.5

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_starfield() -> void:
	var star_mesh := BoxMesh.new()
	star_mesh.size = Vector3(0.6, 0.6, 0.6)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0)
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
	sun.light_energy = 1.15
	sun.shadow_enabled = true
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

	# Concentric rings from the coast (y = 0) tapering down to a point.
	var rings := [
		{"rs": 1.00, "y": 0.0},     # coast top edge
		{"rs": 0.97, "y": -2.6},    # bottom of the dirt cliff
		{"rs": 0.74, "y": -5.6},    # rock
		{"rs": 0.44, "y": -8.4},
		{"rs": 0.20, "y": -10.6},
	]
	var band_cols := [dirt_col, rock_a, rock_b, rock_a]   # one per gap between rings
	var apex := Vector3(0.0, -12.6, 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Flat grassy top: fan from centre to the coast ring.
	for i in seg:
		var v0 := _ring_vertex(rings[0]["rs"], rings[0]["y"], i, seg)
		var v1 := _ring_vertex(rings[0]["rs"], rings[0]["y"], (i + 1) % seg, seg)
		_add_tri(st, Vector3.ZERO, v1, v0, _vary(grass_col, rng), Vector3.UP)

	# Sides: stitch each ring to the next with quads (two triangles).
	for k in range(rings.size() - 1):
		for i in seg:
			var a := _ring_vertex(rings[k]["rs"], rings[k]["y"], i, seg)
			var b := _ring_vertex(rings[k]["rs"], rings[k]["y"], (i + 1) % seg, seg)
			var c := _ring_vertex(rings[k + 1]["rs"], rings[k + 1]["y"], i, seg)
			var d := _ring_vertex(rings[k + 1]["rs"], rings[k + 1]["y"], (i + 1) % seg, seg)
			_add_tri(st, a, b, c, _vary(band_cols[k], rng), _outward(a, b, c))
			_add_tri(st, b, d, c, _vary(band_cols[k], rng), _outward(b, d, c))

	# Bottom: close the underside down to the point.
	var last: Dictionary = rings[rings.size() - 1]
	for i in seg:
		var c := _ring_vertex(last["rs"], last["y"], i, seg)
		var d := _ring_vertex(last["rs"], last["y"], (i + 1) % seg, seg)
		_add_tri(st, apex, c, d, _vary(rock_b, rng), Vector3.DOWN)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # robust against winding
	mi.material_override = mat
	add_child(mi)

	_scatter_surface_rocks(rng)


func _ring_vertex(rs: float, y: float, i: int, seg: int) -> Vector3:
	var ang := TAU * float(i) / float(seg)
	var r := island_radius(ang) * rs
	return Vector3(r * cos(ang), y, r * sin(ang))


## Add a flat-shaded triangle with a single colour; normal is computed and
## flipped to face `ref` so lighting is correct regardless of winding.
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


func _vary(col: Color, rng: RandomNumberGenerator) -> Color:
	var f := rng.randf_range(0.9, 1.08)
	return Color(clampf(col.r * f, 0, 1), clampf(col.g * f, 0, 1), clampf(col.b * f, 0, 1), 1.0)


func _scatter_surface_rocks(rng: RandomNumberGenerator) -> void:
	var stone := make_material(
		make_speckled_texture(Color(0.36, 0.36, 0.40), 0.06, Color(0.23, 0.23, 0.27), 0.16, 303), 4.0
	)
	for i in 10:
		var ang := rng.randf_range(0.0, TAU)
		var maxr := island_radius(ang) - 1.2
		if maxr < 1.0:
			continue
		var d := rng.randf_range(0.0, maxr)
		var rs := rng.randf_range(0.3, 0.7)
		add_child(_make_box(
			Vector3(rs, rs * 0.7, rs),
			Vector3(cos(ang) * d, 0.05, sin(ang) * d),
			stone
		))


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.position = player.global_position + CAM_OFFSET
	# Fixed pitch aimed at the player — derived from the offset. No look_at == no sway.
	camera.rotation = Vector3(-atan2(CAM_OFFSET.y, CAM_OFFSET.z), 0.0, 0.0)
	camera.current = true
	add_child(camera)


func _process(_delta: float) -> void:
	if player == null or camera == null:
		return
	camera.global_position = player.global_position + CAM_OFFSET


# --- shared building blocks (reused by Player & GrassField) -----------------

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


## A vertical gradient (darker base -> lighter tip) with light noise, for grass.
static func make_gradient_texture(bottom: Color, top: Color, rng_seed: int) -> ImageTexture:
	var w := 4
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for y in h:
		var t := 1.0 - float(y) / float(h - 1)   # row 0 (top of texture) = tip
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


func _make_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi
