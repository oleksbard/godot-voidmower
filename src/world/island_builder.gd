extends RefCounted
## Builds the floating island: an organic low-poly landmass (wobbly coast, dirt
## cliff, tapering rock underside) with a triplanar procedural normal map, plus
## scattered surface rocks. Returns a single `Node3D` for the caller to add.
## Reference via `const IslandBuilder := preload(...)`.

const ColorUtil := preload("res://src/lib/color_util.gd")
const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Island"

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

	# Flat grassy top: fan from centre to the coast ring.
	for i in seg:
		var v0 := IslandShape.ring_vertex(rings[0]["rs"], rings[0]["y"], i, seg)
		var v1 := IslandShape.ring_vertex(rings[0]["rs"], rings[0]["y"], (i + 1) % seg, seg)
		_add_tri(st, Vector3.ZERO, v1, v0, ColorUtil.vary(grass_col, rng), Vector3.UP)

	# Sides: stitch each ring to the next.
	for k in range(rings.size() - 1):
		for i in seg:
			var a := IslandShape.ring_vertex(rings[k]["rs"], rings[k]["y"], i, seg)
			var b := IslandShape.ring_vertex(rings[k]["rs"], rings[k]["y"], (i + 1) % seg, seg)
			var c := IslandShape.ring_vertex(rings[k + 1]["rs"], rings[k + 1]["y"], i, seg)
			var d := IslandShape.ring_vertex(rings[k + 1]["rs"], rings[k + 1]["y"], (i + 1) % seg, seg)
			_add_tri(st, a, b, c, ColorUtil.vary(band_cols[k], rng), _outward(a, b, c))
			_add_tri(st, b, d, c, ColorUtil.vary(band_cols[k], rng), _outward(b, d, c))

	# Bottom: close the underside down to the point.
	var last: Dictionary = rings[rings.size() - 1]
	for i in seg:
		var c := IslandShape.ring_vertex(last["rs"], last["y"], i, seg)
		var d := IslandShape.ring_vertex(last["rs"], last["y"], (i + 1) % seg, seg)
		_add_tri(st, apex, c, d, ColorUtil.vary(rock_b, rng), Vector3.DOWN)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _island_material()
	root.add_child(mi)

	_scatter_rocks(root, rng)
	return root


## Vertex-colour material with a triplanar procedural normal map for tactile
## surface detail (no UVs needed — projected by world position).
static func _island_material() -> StandardMaterial3D:
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


## Flat-shaded triangle with a single colour; normal is flipped to face `ref`
## so lighting is correct regardless of winding.
static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, ref: Vector3) -> void:
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


static func _outward(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ctr := (a + b + c) / 3.0
	ctr.y = 0.0
	if ctr.length() < 0.001:
		return Vector3.UP
	return ctr.normalized()


static func _scatter_rocks(root: Node3D, rng: RandomNumberGenerator) -> void:
	for i in 10:
		var ang := rng.randf_range(0.0, TAU)
		var maxr := IslandShape.radius(ang) - 1.2
		if maxr < 1.0:
			continue
		var d := rng.randf_range(0.0, maxr)
		var rs := rng.randf_range(0.35, 0.75)
		var m := StandardMaterial3D.new()
		m.albedo_color = ColorUtil.vary(Color(0.36, 0.36, 0.40), rng)
		m.roughness = clampf(0.9 + rng.randf_range(-0.08, 0.05), 0.0, 1.0)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mb := MeshInstance3D.new()
		mb.mesh = MeshFactory.beveled_box(Vector3(rs, rs * 0.7, rs), 0.08)
		mb.material_override = m
		mb.position = Vector3(cos(ang) * d, 0.04, sin(ang) * d)
		mb.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(mb)
