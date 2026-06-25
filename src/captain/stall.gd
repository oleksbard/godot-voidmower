class_name Stall
extends RefCounted
## Static builder for the Captain's market stall: a wooden counter on legs, two
## posts carrying a striped dusk-orange/cream awning, a crate, and a few tiny
## "seed-packet" boxes spilling on the counter. Pure procedural geometry —
## beveled boxes with per-instance HSL + roughness variance. The orchestrator
## shows it only while the Captain is visiting. Reference via
## `const Stall := preload(...)`.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const ColorUtil := preload("res://src/lib/color_util.gd")

const BEVEL := 0.04
const WOOD_COL := Color(0.46, 0.31, 0.17)
const POST_COL := Color(0.34, 0.23, 0.13)
const AWNING_A := Color(0.92, 0.50, 0.22)   # dusk orange
const AWNING_B := Color(0.93, 0.86, 0.72)   # cream


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Stall"
	var rng := RandomNumberGenerator.new()
	rng.seed = 5050

	# Counter + legs.
	root.add_child(_at(_box(Vector3(1.8, 0.12, 0.9), WOOD_COL, rng), Vector3(0.0, 0.9, 0.0)))
	for sx in [-0.78, 0.78]:
		for sz in [-0.36, 0.36]:
			root.add_child(_at(_box(Vector3(0.12, 0.9, 0.12), POST_COL, rng), Vector3(sx, 0.45, sz)))

	# Two awning posts + a striped awning of alternating slats.
	for sx in [-0.85, 0.85]:
		root.add_child(_at(_box(Vector3(0.1, 1.9, 0.1), POST_COL, rng), Vector3(sx, 0.95, -0.36)))
	var slats := 6
	for i in slats:
		var col := AWNING_A if i % 2 == 0 else AWNING_B
		var slat := _box(Vector3(1.9 / slats * 0.96, 0.06, 0.95), col, rng)
		slat.position = Vector3(-0.95 + (i + 0.5) * (1.9 / slats), 1.95, -0.1)
		slat.rotation.x = -0.32
		root.add_child(slat)

	# A crate + a few tiny "seed packet" boxes spilling on the counter.
	root.add_child(_at(_box(Vector3(0.5, 0.5, 0.5), POST_COL, rng), Vector3(-0.6, 0.25, 0.2)))
	for i in 4:
		var packet := _box(Vector3(0.16, 0.04, 0.12), _packet_col(i), rng)
		packet.position = Vector3(-0.2 + i * 0.22, 1.0, 0.15)
		packet.rotation.y = rng.randf_range(-0.4, 0.4)
		root.add_child(packet)
	return root


# --- builders ---------------------------------------------------------------

static func _packet_col(i: int) -> Color:
	var cols := [Color(0.93, 0.42, 0.18), Color(0.96, 0.74, 0.22), Color(0.40, 0.64, 0.30), Color(0.62, 0.45, 0.72)]
	return cols[i % cols.size()]


static func _box(size: Vector3, base: Color, rng: RandomNumberGenerator) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = ColorUtil.vary(base, rng)
	m.roughness = clampf(0.85 + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.beveled_box(size, BEVEL)
	mi.material_override = m
	return mi


static func _at(mi: MeshInstance3D, pos: Vector3) -> MeshInstance3D:
	mi.position = pos
	return mi
