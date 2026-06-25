class_name CaptainRig
extends Node3D
## Captain Maris "Goldwake" Tully's body — a barrel-chested, round merchant built
## from beveled boxes with per-instance HSL variance (mirrors PlayerRig). Persona
## look: tricorn hat with a marigold + grass sprig, salt-and-honey beard, a brass
## monocle, a dusk-orange coat over a striped vest, mismatched boots, and a glowing
## pollen-sprite that bobs at his shoulder. Pure assembly; exposes the walk pivots.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const ColorUtil := preload("res://src/lib/color_util.gd")

const BEVEL := 0.05

var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var shoulder_sprite: Node3D

var _seed := 700
var _sprite_t := 0.0


func _ready() -> void:
	_build_body()


func _process(delta: float) -> void:
	if shoulder_sprite == null:
		return
	_sprite_t += delta
	shoulder_sprite.position = Vector3(
		0.6 + sin(_sprite_t * 1.7) * 0.12,
		1.5 + sin(_sprite_t * 2.3) * 0.1,
		cos(_sprite_t * 1.7) * 0.12)


func _build_body() -> void:
	var coat := Color(0.86, 0.46, 0.20)      # dusk-orange sailcloth
	var vest := Color(0.80, 0.74, 0.55)      # cream (striped-vest hint)
	var pants := Color(0.30, 0.27, 0.22)
	var skin := Color(0.85, 0.66, 0.50)
	var beard := Color(0.88, 0.82, 0.62)     # salt-and-honey
	var hat := Color(0.28, 0.22, 0.16)
	var boot_a := Color(0.30, 0.20, 0.12)
	var boot_b := Color(0.20, 0.18, 0.22)    # mismatched
	var brass := Color(0.85, 0.66, 0.24)
	var dark := Color(0.10, 0.09, 0.08)

	# Short, round legs (pivots at the hips).
	leg_l = _limb(Vector3(0.18, 0.52, 0.0))
	leg_r = _limb(Vector3(-0.18, 0.52, 0.0))
	leg_l.add_child(_part(Vector3(0.26, 0.40, 0.30), Vector3(0, -0.20, 0), pants))
	leg_r.add_child(_part(Vector3(0.26, 0.40, 0.30), Vector3(0, -0.20, 0), pants))
	leg_l.add_child(_part(Vector3(0.28, 0.16, 0.34), Vector3(0, -0.46, 0.02), boot_a))
	leg_r.add_child(_part(Vector3(0.28, 0.16, 0.34), Vector3(0, -0.46, 0.02), boot_b))

	# Barrel chest + belly: a wide torso, a vest front, a belt.
	add_child(_part(Vector3(0.66, 0.20, 0.40), Vector3(0, 0.54, 0), pants))     # hips
	add_child(_part(Vector3(0.74, 0.66, 0.52), Vector3(0, 0.92, 0), coat))      # barrel torso
	add_child(_part(Vector3(0.40, 0.50, 0.10), Vector3(0, 0.92, 0.22), vest))   # vest front
	add_child(_part(Vector3(0.78, 0.10, 0.56), Vector3(0, 0.66, 0), dark))      # belt

	# Round arms in the coat.
	arm_l = _limb(Vector3(-0.46, 1.18, 0.0))
	arm_r = _limb(Vector3(0.46, 1.18, 0.0))
	arm_l.add_child(_part(Vector3(0.20, 0.50, 0.24), Vector3(0, -0.24, 0), coat))
	arm_r.add_child(_part(Vector3(0.20, 0.50, 0.24), Vector3(0, -0.24, 0), coat))
	arm_l.add_child(_part(Vector3(0.18, 0.14, 0.22), Vector3(0, -0.54, 0), skin))
	arm_r.add_child(_part(Vector3(0.18, 0.14, 0.22), Vector3(0, -0.54, 0), skin))

	# Neck, head, beard, eyes, brass monocle.
	add_child(_part(Vector3(0.20, 0.10, 0.20), Vector3(0, 1.30, 0), skin))
	add_child(_part(Vector3(0.48, 0.44, 0.44), Vector3(0, 1.58, 0), skin))      # head
	add_child(_part(Vector3(0.46, 0.26, 0.16), Vector3(0, 1.40, 0.18), beard))  # beard
	add_child(_part(Vector3(0.08, 0.09, 0.05), Vector3(0.11, 1.62, -0.22), dark))   # eye L
	add_child(_part(Vector3(0.08, 0.09, 0.05), Vector3(-0.11, 1.62, -0.22), dark))  # eye R
	add_child(_part(Vector3(0.16, 0.16, 0.06), Vector3(0.13, 1.60, -0.24), brass))  # monocle rim

	# Tricorn hat: flat crown + wide brim, with a marigold + grass sprig.
	add_child(_part(Vector3(0.56, 0.16, 0.52), Vector3(0, 1.86, 0), hat))       # crown
	add_child(_part(Vector3(0.74, 0.06, 0.66), Vector3(0, 1.80, 0), hat))       # brim
	add_child(_part(Vector3(0.10, 0.10, 0.10), Vector3(0.20, 1.92, -0.18), Color(0.95, 0.55, 0.16)))  # marigold
	add_child(_part(Vector3(0.04, 0.18, 0.04), Vector3(0.26, 1.98, -0.16), Color(0.40, 0.64, 0.30)))  # grass sprig

	_build_sprite()


## A tiny glowing pollen-sprite that bobs near his right shoulder (animated in _process).
func _build_sprite() -> void:
	shoulder_sprite = Node3D.new()
	shoulder_sprite.position = Vector3(0.6, 1.5, 0.0)
	add_child(shoulder_sprite)
	var glow := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.1)
	glow.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.92, 0.5)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.4)
	m.emission_energy_multiplier = 3.0
	glow.material_override = m
	shoulder_sprite.add_child(glow)


# --- builders ---------------------------------------------------------------

func _limb(pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
	return pivot


func _solid(base: Color, rough: float) -> StandardMaterial3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_seed += 1
	var m := StandardMaterial3D.new()
	m.albedo_color = ColorUtil.vary(base, rng)
	m.roughness = clampf(rough + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _part(size: Vector3, pos: Vector3, base: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.beveled_box(size, BEVEL)
	mi.material_override = _solid(base, 0.82)
	mi.position = pos
	return mi
