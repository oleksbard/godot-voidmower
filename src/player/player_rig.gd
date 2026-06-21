class_name PlayerRig
extends Node3D
## The mower's body: a little humanoid holding a scythe, assembled from many
## small *beveled* boxes (boots, two legs, hips, torso, two arms, neck, head with
## hair + eyes). Each part gets a solid material with per-instance HSL + roughness
## variance so nothing looks stamped.
##
## This script is **pure assembly** — it builds the mesh hierarchy, bakes the
## rest pose, and exposes the animatable pivots (`leg_l`, `leg_r`, `arm_free`,
## `arm_scythe`, `scythe_pivot`). Input, movement, and the walk/swing animation
## live in player.gd, which reads these pivots each frame. The walk bob moves
## *this* node's local Y, so the root the camera follows never shakes.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const ColorUtil := preload("res://src/lib/color_util.gd")

const BEVEL := 0.045

# Rest pose the controller lerps the swing away from and back to.
const ARM_REST_X := 0.5

# The scythe is gripped *in the scythe hand* (parented to that arm), so it stays
# connected to the hand through the whole swing. We place it at the hand, cancel
# the arm's rest tilt, yaw the snath out front, and pitch its tip down to the
# ground — then re-level the blade flat there so its cutting edge sweeps along
# the ground like a real scythe (not held flat like a hockey stick).
const SCYTHE_GRIP_POS := Vector3(0.0, -0.5, 0.0)     # at the hand, arm-local
const SCYTHE_YAW_DEG := 70.0                          # snath swung out front
const SCYTHE_PITCH_DEG := -10.0                       # snath lies near-flat (visible top-down), slight droop
const BLADE_YAW_DEG := 70.0                           # hook ~perpendicular to the snath

# Limb pivots the controller animates. Public: this is the rig's interface.
var leg_l: Node3D
var leg_r: Node3D
var arm_free: Node3D
var arm_scythe: Node3D
var scythe_pivot: Node3D

var _seed := 100


func _ready() -> void:
	_build_body()


func _build_body() -> void:
	var skin := Color(0.86, 0.67, 0.52)
	var shirt := Color(0.20, 0.45, 0.74)
	var pants := Color(0.24, 0.26, 0.34)
	var boots := Color(0.30, 0.20, 0.12)
	var hair := Color(0.33, 0.21, 0.11)
	var dark := Color(0.10, 0.09, 0.08)

	# Legs (pivots at the hips so they can swing).
	leg_l = _limb(Vector3(0.14, 0.66, 0.0))
	leg_r = _limb(Vector3(-0.14, 0.66, 0.0))
	for leg in [leg_l, leg_r]:
		leg.add_child(_part(Vector3(0.22, 0.46, 0.26), Vector3(0, -0.23, 0), pants))
		leg.add_child(_part(Vector3(0.24, 0.16, 0.30), Vector3(0, -0.54, 0.02), boots))

	# Hips + torso.
	add_child(_part(Vector3(0.46, 0.18, 0.28), Vector3(0, 0.70, 0), pants))
	add_child(_part(Vector3(0.50, 0.62, 0.30), Vector3(0, 0.97, 0), shirt))

	# Free arm (animated) + scythe arm (static reach, animated during a swing).
	arm_free = _limb(Vector3(-0.35, 1.24, 0.0))
	arm_free.add_child(_part(Vector3(0.15, 0.46, 0.20), Vector3(0, -0.23, 0), shirt))
	arm_free.add_child(_part(Vector3(0.15, 0.12, 0.20), Vector3(0, -0.52, 0), skin))

	arm_scythe = _limb(Vector3(0.35, 1.24, 0.0))
	arm_scythe.rotation.x = ARM_REST_X
	arm_scythe.add_child(_part(Vector3(0.15, 0.46, 0.20), Vector3(0, -0.23, 0), shirt))
	arm_scythe.add_child(_part(Vector3(0.15, 0.12, 0.20), Vector3(0, -0.52, 0), skin))

	# Neck + head + hair + eyes (eyes on the -Z front, which also shows facing).
	add_child(_part(Vector3(0.16, 0.10, 0.16), Vector3(0, 1.32, 0), skin))
	add_child(_part(Vector3(0.46, 0.46, 0.42), Vector3(0, 1.60, 0), skin))
	add_child(_part(Vector3(0.50, 0.14, 0.46), Vector3(0, 1.84, 0), hair))
	add_child(_part(Vector3(0.50, 0.40, 0.12), Vector3(0, 1.62, 0.17), hair))
	add_child(_part(Vector3(0.08, 0.09, 0.05), Vector3(0.10, 1.62, -0.21), dark))
	add_child(_part(Vector3(0.08, 0.09, 0.05), Vector3(-0.10, 1.62, -0.21), dark))

	_build_scythe()


func _build_scythe() -> void:
	# Rest orientation of the snath in world space: yawed out front, tip pitched
	# down to the ground. Grip cancels the arm's rest tilt so the arm still drives
	# the swing.
	var snath := Basis(Vector3.UP, deg_to_rad(SCYTHE_YAW_DEG)) * Basis(Vector3.RIGHT, deg_to_rad(SCYTHE_PITCH_DEG))
	scythe_pivot = Node3D.new()
	scythe_pivot.transform = Transform3D(Basis(Vector3.RIGHT, -ARM_REST_X) * snath, SCYTHE_GRIP_POS)
	arm_scythe.add_child(scythe_pivot)   # gripped in the hand, not floating beside it

	var wood := _solid(Color(0.45, 0.30, 0.16), 0.85)
	# Light, mostly-matte steel so the blade stays bright against the dark sky
	# (a mirror blade just reflects the black void and reads as a shadow).
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.84, 0.86, 0.90)
	metal.metallic = 0.3
	metal.roughness = 0.5
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED

	scythe_pivot.add_child(_part_mat(Vector3(0.05, 0.05, 1.32), Vector3(0, 0, -0.62), wood))

	# Scythe blade: an L-shaped hook off the snath tip — NOT a symmetric mop head.
	# A flat, re-levelled root at the tip; the blade sweeps out to ONE side in two
	# thin segments that curve forward, so it reads as a scythe with a leading edge.
	var blade_root := Node3D.new()
	blade_root.transform = Transform3D(snath.inverse() * Basis(Vector3.UP, deg_to_rad(BLADE_YAW_DEG)), Vector3(0, 0, -1.2))
	scythe_pivot.add_child(blade_root)

	var heel := _part_mat(Vector3(0.5, 0.05, 0.14), Vector3(0.25, 0.0, 0.0), metal)
	blade_root.add_child(heel)

	var bend := Basis(Vector3.UP, deg_to_rad(-38.0))    # the tip curves back inward (concave edge leads)
	var joint := Vector3(0.48, 0.0, 0.0)
	var tip := _part_mat(Vector3(0.58, 0.045, 0.12), Vector3.ZERO, metal)
	tip.transform = Transform3D(bend, joint + bend * Vector3(0.28, 0.0, 0.0))
	blade_root.add_child(tip)


# --- builders ---------------------------------------------------------------

func _limb(pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
	return pivot


## Solid material with per-instance HSL + roughness variance.
func _solid(base: Color, rough: float) -> StandardMaterial3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_seed += 1
	var m := StandardMaterial3D.new()
	m.albedo_color = ColorUtil.vary(base, rng)
	m.roughness = clampf(rough + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # required for the beveled mesh
	return m


func _part(size: Vector3, pos: Vector3, base: Color) -> MeshInstance3D:
	return _part_mat(size, pos, _solid(base, 0.82))


func _part_mat(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.beveled_box(size, BEVEL)
	mi.material_override = mat
	mi.position = pos
	return mi
