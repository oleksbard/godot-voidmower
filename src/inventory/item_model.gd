class_name ItemModel
extends RefCounted
## Builds a small low-poly 3D model for an inventory item from beveled boxes (+ a
## couple of built-in primitives), with per-instance HSL variance so it matches
## the game's procedural look. The shapes echo the brand icons in assets/icons/
## (a curved-blade scythe, a tied sheaf of grass, a layered bloom on a stem) —
## but they are pure geometry, no textures.
##
## The hotbar renders one of these per slot in its own SubViewport, so the
## inventory shows real 3D models and NOTHING image-based loads at runtime — the
## "procedural geometry only, zero image assets" rule now holds even in the UI.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const ColorUtil := preload("res://src/lib/color_util.gd")
const ItemDb := preload("res://src/inventory/item_db.gd")

const BEVEL := 0.03


## A fresh model for `item_id`, centred on the origin and sized to roughly fill a
## ~1.2-unit cube (the hotbar camera frames that). Spins cleanly about its own Y.
## Returns null for an unknown id.
static func build(item_id: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + item_id            # deterministic per item, varied between items
	match item_id:
		ItemDb.Id.SCYTHE:
			return _scythe(rng)
		ItemDb.Id.GRASS:
			return _grass(rng)
		ItemDb.Id.FLOWER:
			return _flower(rng)
	return null


# --- models -----------------------------------------------------------------

## A curved-blade scythe: a leaning wooden snath with a grip knob and an L-shaped
## steel hook off the top (heel + inward-bending tip, the player's scythe recipe).
static func _scythe(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var wood := Color(0.50, 0.33, 0.16)
	var metal := _metal_mat()

	var snath := Node3D.new()
	snath.basis = Basis(Vector3.BACK, deg_to_rad(26.0))   # lean across the frame
	root.add_child(snath)
	snath.add_child(_box(Vector3(0.075, 1.2, 0.075), Vector3.ZERO, wood, rng))
	snath.add_child(_box(Vector3(0.15, 0.15, 0.11), Vector3(0.0, -0.62, 0.0), wood, rng))

	var blade_root := Node3D.new()
	blade_root.position = Vector3(0.0, 0.6, 0.0)          # at the snath tip
	snath.add_child(blade_root)
	blade_root.add_child(_box_mat(Vector3(0.5, 0.055, 0.14), Vector3(0.25, 0.0, 0.0), metal))
	var bend := Basis(Vector3.UP, deg_to_rad(-40.0))      # tip curves back inward
	var tip := _box_mat(Vector3(0.56, 0.05, 0.12), Vector3.ZERO, metal)
	tip.transform = Transform3D(bend, Vector3(0.48, 0.0, 0.0) + bend * Vector3(0.27, 0.0, 0.0))
	blade_root.add_child(tip)
	return root


## A tied sheaf: blades fanned out radially (so it reads from every spin angle)
## with a twine ring around the middle.
static func _grass(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var blades := 9
	for i in blades:
		var a := TAU * i / float(blades) + rng.randf_range(-0.15, 0.15)
		var lean := rng.randf_range(0.10, 0.30)
		var h := rng.randf_range(0.85, 1.12)
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, -0.5, 0.0)          # all blades rise from the base
		pivot.basis = Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, lean)
		pivot.add_child(_box(Vector3(0.075, h, 0.06), Vector3(0.0, h * 0.5, 0.0), Color(0.32, 0.58, 0.20), rng))
		root.add_child(pivot)

	var band := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.23
	band.mesh = torus
	band.material_override = _solid(Color(0.66, 0.48, 0.24), 0.7, rng)   # tan twine
	band.position = Vector3(0.0, -0.05, 0.0)             # ties the bundle around its middle
	# TorusMesh already lies flat in XZ (hole up the Y axis) — exactly a rope wrapped
	# around the upright blades, so no rotation is needed.
	root.add_child(band)
	return root


## A layered bloom: a green stem with two leaves, a warm centre, and two rings of
## petals tilted up and out (radial, so it stays a flower from every spin angle).
static func _flower(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var leaf_col := Color(0.32, 0.55, 0.22)
	root.add_child(_box(Vector3(0.06, 0.82, 0.06), Vector3(0.0, -0.21, 0.0), Color(0.30, 0.52, 0.20), rng))
	for s in [-1.0, 1.0]:
		var leaf := _box(Vector3(0.3, 0.05, 0.14), Vector3(s * 0.17, -0.26, 0.0), leaf_col, rng)
		leaf.rotation = Vector3(0.0, 0.0, s * 0.5)
		root.add_child(leaf)

	var head_y := 0.34
	root.add_child(_box(Vector3(0.2, 0.12, 0.2), Vector3(0.0, head_y, 0.0), Color(0.96, 0.74, 0.22), rng))
	for layer in 2:
		var count := 6
		var radius := 0.2 if layer == 0 else 0.13
		var col := Color(0.93, 0.42, 0.18) if layer == 0 else Color(0.97, 0.56, 0.28)
		for i in count:
			var a := TAU * i / float(count) + (0.0 if layer == 0 else PI / count)
			var pivot := Node3D.new()
			pivot.position = Vector3(0.0, head_y, 0.0)
			pivot.basis = Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.6)   # tilt petals up
			pivot.add_child(_box(Vector3(0.15, 0.05, 0.2), Vector3(0.0, 0.0, -radius), col, rng))
			root.add_child(pivot)
	return root


# --- builders ---------------------------------------------------------------

static func _solid(base: Color, rough: float, rng: RandomNumberGenerator) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = ColorUtil.vary(base, rng)
	m.roughness = clampf(rough + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # the beveled mesh needs both faces
	return m


## Light, mostly-matte steel — bright enough to read against the dark slot.
static func _metal_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.84, 0.86, 0.90)
	m.metallic = 0.3
	m.roughness = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _box(size: Vector3, pos: Vector3, base: Color, rng: RandomNumberGenerator) -> MeshInstance3D:
	return _box_mat(size, pos, _solid(base, 0.8, rng))


static func _box_mat(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.beveled_box(size, BEVEL)
	mi.material_override = mat
	mi.position = pos
	return mi
