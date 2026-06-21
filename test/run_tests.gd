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
const PlayerRigScript := preload("res://src/player/player_rig.gd")
const GrassFieldScript := preload("res://src/grass/grass_field.gd")
const FlowerFieldScript := preload("res://src/grass/flower_field.gd")
const DayNightScript := preload("res://src/world/day_night.gd")
const ItemDbScript := preload("res://src/inventory/item_db.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")
const HotbarScript := preload("res://src/inventory/hotbar.gd")
const DropFieldScript := preload("res://src/drops/drop_field.gd")

var _passed := 0
var _failed := 0
var _suite := ""


func _initialize() -> void:
	print("── running tests ──")
	_test_island_shape()
	_test_color_util()
	_test_mesh_factory()
	_test_day_night_math()
	_test_item_db()
	_test_inventory()
	_test_player_edge_clamp()
	await _test_player_rig()        # in-tree _ready() builds the body
	await _test_grass_planting()   # need a frame so _ready() fires in-tree
	await _test_mow_chain()
	await _test_flower_mow()
	await _test_day_night_node()
	await _test_hotbar()
	await _test_drop_field()
	await _test_player_tool_gating()
	await _test_grass_drops()
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


# --- DayNight math ----------------------------------------------------------

func _test_day_night_math() -> void:
	_suite = "DayNight"
	_ok(is_equal_approx(DayNightScript.phase_at(0.0), DayNightScript.phase_at(DayNightScript.CYCLE_SECONDS)),
		"phase wraps over CYCLE_SECONDS")
	_ok(is_equal_approx(DayNightScript.phase_at(DayNightScript.CYCLE_SECONDS * 0.5), 0.5),
		"phase is 0.5 at half a cycle")
	_ok(DayNightScript.sun_height(0.25) > 0.0 and DayNightScript.sun_height(0.75) < 0.0,
		"sun is above the horizon by day and below at night")
	_ok(DayNightScript.dayness(0.25) > 0.9 and DayNightScript.dayness(0.75) < 0.1,
		"dayness ~1 at midday and ~0 at deep night")
	_ok(DayNightScript.sun_casts(0.25) and not DayNightScript.sun_casts(0.75),
		"sun casts shadows by day, not at night")
	_ok(is_equal_approx(DayNightScript.clock_hours(0.0), 6.0) and is_equal_approx(DayNightScript.clock_hours(0.25), 12.0),
		"clock reads 06:00 at dawn and 12:00 at midday")
	_ok(DayNightScript.day_number(0.0) == 1 and DayNightScript.day_number(DayNightScript.CYCLE_SECONDS) == 2,
		"day number starts at 1 and ticks up each cycle")
	_ok(DayNightScript.day_number(DayNightScript.CYCLE_SECONDS * 0.74) == 1
			and DayNightScript.day_number(DayNightScript.CYCLE_SECONDS * 0.76) == 2,
		"day increments at midnight (phase 0.75), not at dawn")


# --- ItemDb -----------------------------------------------------------------

func _test_item_db() -> void:
	_suite = "ItemDb"
	_ok(ItemDbScript.is_tool_item(ItemDbScript.Id.SCYTHE) and ItemDbScript.max_stack(ItemDbScript.Id.SCYTHE) == 1,
		"scythe is a tool with stack 1")
	_ok(not ItemDbScript.is_tool_item(ItemDbScript.Id.GRASS) and ItemDbScript.max_stack(ItemDbScript.Id.GRASS) == 999,
		"grass is a non-tool with stack 999")
	_ok(ItemDbScript.max_stack(ItemDbScript.Id.FLOWER) == 999,
		"flower stacks to 999")
	_ok(ItemDbScript.icon_path(ItemDbScript.Id.GRASS) == "res://assets/icons/grass.png",
		"grass icon path resolves")


# --- Inventory --------------------------------------------------------------

func _test_inventory() -> void:
	_suite = "Inventory"
	var inv := InventoryScript.new()
	var all_empty := true
	for i in InventoryScript.SLOT_COUNT:
		if inv.slot_id(i) != InventoryScript.EMPTY:
			all_empty = false
	_ok(all_empty and inv.active_index() == 0, "starts with 10 empty slots, active slot 0")

	inv.set_slot(0, ItemDbScript.Id.SCYTHE, 1)
	_ok(inv.slot_id(0) == ItemDbScript.Id.SCYTHE and inv.active_item() == ItemDbScript.Id.SCYTHE,
		"scythe seeds slot 0 and is the active item")

	inv.add(ItemDbScript.Id.GRASS, 5)
	var left := inv.add(ItemDbScript.Id.GRASS, 3)
	_ok(inv.slot_id(1) == ItemDbScript.Id.GRASS and inv.slot_count(1) == 8 and left == 0,
		"same-item adds merge into one stack")

	var inv2 := InventoryScript.new()
	var leftover := inv2.add(ItemDbScript.Id.GRASS, 1000)
	_ok(inv2.slot_count(0) == 999 and inv2.slot_id(1) == ItemDbScript.Id.GRASS and inv2.slot_count(1) == 1 and leftover == 0,
		"overflow past max_stack spills into the next slot")

	inv.set_active(99)
	var hi := inv.active_index()
	inv.set_active(-4)
	var lo := inv.active_index()
	_ok(hi == InventoryScript.SLOT_COUNT - 1 and lo == 0, "set_active clamps to the valid slot range")

	_ok(inv2.active_item() == ItemDbScript.Id.GRASS and InventoryScript.new().active_item() == InventoryScript.EMPTY,
		"active_item returns the active slot id, EMPTY when blank")


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


# --- PlayerRig --------------------------------------------------------------

func _test_player_rig() -> void:
	_suite = "PlayerRig"
	var rig: Node3D = PlayerRigScript.new()
	get_root().add_child(rig)
	await process_frame         # let rig._ready() build the body in-tree

	var pivots := {
		"leg_l": rig.leg_l, "leg_r": rig.leg_r, "arm_free": rig.arm_free,
		"arm_scythe": rig.arm_scythe, "scythe_pivot": rig.scythe_pivot,
	}
	var all_present := true
	for name in pivots:
		if pivots[name] == null or not (pivots[name] is Node3D):
			all_present = false
	_ok(all_present, "exposes all five animatable pivots")

	_ok(rig.get_child_count() > 10, "builds a populated body hierarchy (%d parts)" % rig.get_child_count())
	_ok(is_equal_approx(rig.arm_scythe.rotation.x, PlayerRigScript.ARM_REST_X),
		"bakes the scythe arm into its rest pose")

	rig.free()


# --- GrassField planting ----------------------------------------------------

func _test_grass_planting() -> void:
	_suite = "GrassField.plant"
	var dummy := Node3D.new()
	get_root().add_child(dummy)        # player ref must be in-tree (bend reads its global_position)
	var gf: Node3D = GrassFieldScript.new()
	gf.player = dummy
	get_root().add_child(gf)
	await process_frame                # let _ready() plant inside the tree

	_ok(gf._count > 100, "plants a populated field (%d blades)" % gf._count)
	_ok(gf.mowed == 0, "mow count starts at 0")
	_ok(gf._mm.instance_count == gf._count, "one MultiMesh instance per blade")

	var all_inside := true
	for i in gf._count:
		var bp: Vector3 = gf._base_pos[i]
		var ang := atan2(bp.z, bp.x)
		if Vector2(bp.x, bp.z).length() > IslandShape.radius(ang) - GrassFieldScript.EDGE_MARGIN + 0.01:
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


# --- FlowerField mowing -----------------------------------------------------

func _test_flower_mow() -> void:
	_suite = "FlowerField"
	var ff: Node3D = FlowerFieldScript.new()
	get_root().add_child(ff)
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	ff.add_flower(0.5, 0.0, 1.0, rng)    # bloom just in front of the swing
	ff.add_flower(20.0, 0.0, 1.0, rng)   # bloom well outside the arc

	var cos_arc := cos(deg_to_rad(70.0))
	var n: int = ff.cut_in_arc(Vector3.ZERO, Vector3(1, 0, 0), 2.2, cos_arc)
	_ok(n == 1, "cut_in_arc mows only the bloom inside the arc (got %d)" % n)

	ff.free()


# --- DayNight node ----------------------------------------------------------

func _test_day_night_node() -> void:
	_suite = "DayNight.node"
	var env := Environment.new()
	var dn: Node3D = DayNightScript.new()
	dn.environment = env
	get_root().add_child(dn)
	await process_frame                      # _ready() builds lights/stars in-tree

	dn._apply(DayNightScript.phase_at(DayNightScript.CYCLE_SECONDS * 0.25))   # midday
	_ok(dn._sun.shadow_enabled and not dn._moon.shadow_enabled,
		"midday: only the sun casts shadows")

	dn._apply(DayNightScript.phase_at(DayNightScript.CYCLE_SECONDS * 0.75))   # deep night
	_ok(dn._moon.shadow_enabled and not dn._sun.shadow_enabled,
		"night: only the moon casts shadows")
	_ok(env.tonemap_exposure > DayNightScript.DAY_EXPOSURE,
		"night raises exposure above the day value")

	dn.free()


# --- Hotbar -----------------------------------------------------------------

func _test_hotbar() -> void:
	_suite = "Hotbar"
	var hb := HotbarScript.new()
	get_root().add_child(hb)
	await process_frame                      # _ready builds slots + seeds the scythe

	_ok(hb._inv.slot_id(0) == ItemDbScript.Id.SCYTHE, "scythe seeded into slot 0 (key 1)")

	hb.add_item(ItemDbScript.Id.GRASS, 2)
	_ok(hb._inv.slot_id(1) == ItemDbScript.Id.GRASS and hb._inv.slot_count(1) == 2,
		"add_item routes a drop into the inventory")

	var seen := {"id": -999}
	hb.active_tool_changed.connect(func(id): seen.id = id)
	hb._select(1)
	_ok(seen.id == ItemDbScript.Id.GRASS, "selecting a slot announces its item as the active tool")

	_ok(hb._key_to_slot(KEY_1) == 0 and hb._key_to_slot(KEY_9) == 8 and hb._key_to_slot(KEY_0) == 9 and hb._key_to_slot(KEY_A) == -1,
		"number keys 1-9/0 map to slots; other keys are ignored")

	hb.free()


# --- DropField --------------------------------------------------------------

func _test_drop_field() -> void:
	_suite = "DropField"
	var target := Node3D.new()
	get_root().add_child(target)             # player ref must be in-tree for global_position
	var df := DropFieldScript.new()
	df.player = target
	get_root().add_child(df)
	await process_frame

	df.spawn(ItemDbScript.Id.GRASS, Vector3(3.0, 0.0, 3.0))
	df._process(0.1)                          # ~22% of the flight: still travelling
	_ok(df._flying.size() == 1, "a spawned token is in flight")

	var got := {"n": 0, "id": -999}
	df.collected.connect(func(id): got.n += 1; got.id = id)
	df._process(1.0)                          # force t >= 1: arrival
	_ok(got.n == 1 and got.id == ItemDbScript.Id.GRASS, "token arrives once and reports its item")
	_ok(df._flying.is_empty(), "the arrived token is removed from the flight list")

	df.free()
	target.free()


# --- Player tool-gating -----------------------------------------------------

func _test_player_tool_gating() -> void:
	_suite = "Player.tool"
	var p: Node3D = PlayerScript.new()
	get_root().add_child(p)
	await process_frame                       # _ready builds the rig

	var swings := {"n": 0}
	p.swing.connect(func(_o, _f): swings.n += 1)

	p.set_active_tool(ItemDbScript.Id.GRASS)
	p._try_swing()
	_ok(not p._rig.scythe_pivot.visible and swings.n == 0,
		"a non-tool slot hides the scythe and SPACE does nothing")

	p.set_active_tool(ItemDbScript.Id.SCYTHE)
	p._try_swing()
	_ok(p._rig.scythe_pivot.visible and swings.n == 1,
		"the scythe slot shows the scythe and SPACE swings")

	p.free()


# --- GrassField drops -------------------------------------------------------

func _test_grass_drops() -> void:
	_suite = "GrassField.drops"
	var dummy := Node3D.new()
	get_root().add_child(dummy)
	var gf: Node3D = GrassFieldScript.new()
	gf.player = dummy
	get_root().add_child(gf)
	await process_frame                       # plant the field in-tree

	var drops := []
	gf.item_dropped.connect(func(id, pos): drops.append({"id": id, "pos": pos}))

	# Sweep several swing origins/directions so a large slice of the field is cut.
	# Fixed planting + drop seeds make the result deterministic and reproducible.
	for o in [Vector3.ZERO, Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3)]:
		for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			gf.on_swing(o, d)

	var ids_valid := true
	for e in drops:
		if e.id != ItemDbScript.Id.GRASS and e.id != ItemDbScript.Id.FLOWER:
			ids_valid = false
	_ok(drops.size() > 0, "mowing the field drops at least one item (%d drops)" % drops.size())
	_ok(ids_valid, "every drop is a grass or flower item")

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
