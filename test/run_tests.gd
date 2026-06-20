extends SceneTree
## Zero-dependency headless test runner for the deterministic core.
##
## Run:  godot --headless --path . --script res://test/run_tests.gd
## (or:  ./test/run_tests.sh)
##
## Exits 0 if all checks pass, 1 otherwise — CI-friendly. Tests call the
## extracted lib statics directly and build feature nodes via `_ready()` without
## a full scene, so no addon, plugin, or global class cache is needed.

const IslandShape := preload("res://src/lib/island_shape.gd")
const ColorUtil := preload("res://src/lib/color_util.gd")
const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const PlayerScript := preload("res://src/player/player.gd")
const GrassFieldScript := preload("res://src/grass/grass_field.gd")

var _passed := 0
var _failed := 0
var _suite := ""


func _initialize() -> void:
	print("── running tests ──")
	_test_island_shape()
	_test_color_util()
	_test_mesh_factory()
	_test_player_edge_clamp()
	await _test_grass_planting()   # need a frame so _ready() fires in-tree
	await _test_mow_chain()
	print("──")
	print("%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- IslandShape ------------------------------------------------------------

func _test_island_shape() -> void:
	_suite = "IslandShape"
	# Coefficients sum to 0.31, so the coastline stays within ±31% of BASE.
	var in_bounds := true
	for i in 360:
		var r := IslandShape.radius(deg_to_rad(float(i)))
		if r < IslandShape.BASE * 0.6 or r > IslandShape.BASE * 1.4:
			in_bounds = false
	_ok(in_bounds, "radius() stays within [0.6, 1.4] * BASE for all angles")

	_ok(is_equal_approx(IslandShape.radius(0.5), IslandShape.radius(0.5 + TAU)),
		"radius() is periodic over TAU")

	var v := IslandShape.ring_vertex(1.0, 0.0, 0, 60)   # angle 0 -> +X axis
	_ok(is_equal_approx(v.x, IslandShape.radius(0.0)) and is_zero_approx(v.y) and is_zero_approx(v.z),
		"ring_vertex(i=0) sits on +X at radius(0)")


# --- ColorUtil --------------------------------------------------------------

func _test_color_util() -> void:
	_suite = "ColorUtil"
	var rng := RandomNumberGenerator.new()
	var in_gamut := true
	for seed_i in 50:
		rng.seed = seed_i
		var c := ColorUtil.vary(Color(0.3, 0.6, 0.2, 1.0), rng)
		if c.s < 0.0 or c.s > 1.0 or c.v < 0.0 or c.v > 1.0 or c.h < 0.0 or c.h >= 1.0001:
			in_gamut = false
		if not is_equal_approx(c.a, 1.0):
			in_gamut = false
	_ok(in_gamut, "vary() keeps S/V/H in gamut and preserves alpha")

	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 5
	b.seed = 5
	_ok(ColorUtil.vary(Color(0.3, 0.6, 0.2), a).is_equal_approx(ColorUtil.vary(Color(0.3, 0.6, 0.2), b)),
		"vary() is deterministic for a fixed seed")


# --- MeshFactory ------------------------------------------------------------

func _test_mesh_factory() -> void:
	_suite = "MeshFactory"
	var mesh := MeshFactory.beveled_box(Vector3(1.0, 2.0, 0.5), 0.06)
	_ok(mesh.get_surface_count() == 1, "beveled_box() produces one surface")

	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# 6 faces*2 + 12 edges*2 + 8 corners = 44 tris * 3 = 132 verts.
	_ok(verts.size() == 132, "beveled_box() has 132 vertices (got %d)" % verts.size())

	_ok(mesh.get_aabb().size.is_equal_approx(Vector3(1.0, 2.0, 0.5)),
		"beveled_box() AABB matches requested size")


# --- Player edge clamp ------------------------------------------------------

func _test_player_edge_clamp() -> void:
	_suite = "Player.clamp"
	var p: Node3D = PlayerScript.new()   # not added to tree: _ready/rig not needed

	p.position = Vector3(50.0, 0.0, 30.0)   # far outside the island
	p._clamp_to_island()
	var d := Vector2(p.position.x, p.position.z).length()
	var ang := atan2(p.position.z, p.position.x)
	var max_r: float = IslandShape.radius(ang) - PlayerScript.EDGE_MARGIN
	_ok(d <= max_r + 0.01, "clamp pulls an outside point onto the island")

	var inside := Vector3(1.0, 0.0, 1.0)
	p.position = inside
	p._clamp_to_island()
	_ok(p.position.is_equal_approx(inside), "clamp leaves an inside point untouched")
	p.free()


# --- GrassField planting ----------------------------------------------------

func _test_grass_planting() -> void:
	_suite = "GrassField.plant"
	var dummy := Node3D.new()
	get_root().add_child(dummy)        # player ref must be in-tree (bend reads its global_position)
	var gf: Node3D = GrassFieldScript.new()
	gf.player = dummy
	get_root().add_child(gf)
	await process_frame                # let _ready() plant inside the tree

	_ok(gf._blades.size() > 100, "plants a populated field (%d blades)" % gf._blades.size())
	_ok(gf.mowed == 0, "mow count starts at 0")

	var all_inside := true
	for b in gf._blades:
		var ang := atan2(b.position.z, b.position.x)
		if Vector2(b.position.x, b.position.z).length() > IslandShape.radius(ang) - GrassFieldScript.EDGE_MARGIN + 0.01:
			all_inside = false
	_ok(all_inside, "every planted blade lies inside the coastline")

	gf.free()
	dummy.free()


# --- swing -> cut -> count chain --------------------------------------------

func _test_mow_chain() -> void:
	_suite = "GrassField.mow"
	var dummy := Node3D.new()
	get_root().add_child(dummy)
	var gf: Node3D = GrassFieldScript.new()
	gf.player = dummy
	get_root().add_child(gf)
	await process_frame                # plant + enter tree so global_position works

	var seen := {"count": -1}
	gf.mowed_changed.connect(func(c): seen.count = c)

	gf.on_swing(Vector3.ZERO, Vector3(0.0, 0.0, -1.0))   # swing at island centre
	_ok(gf.mowed > 0, "swing cuts at least one blade (mowed=%d)" % gf.mowed)
	_ok(seen.count == gf.mowed, "mowed_changed signal reports the new count")

	gf.free()
	dummy.free()


# --- harness ----------------------------------------------------------------

func _ok(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  ok   [%s] %s" % [_suite, message])
	else:
		_failed += 1
		printerr("  FAIL [%s] %s" % [_suite, message])
