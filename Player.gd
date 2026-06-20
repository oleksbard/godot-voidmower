extends Node3D
## The mower: a little character holding a scythe.
##
## Assembled from many small boxes (boots, two legs, hips, torso, two arms,
## neck, head with hair + eyes) for a finer, more humanoid silhouette than a few
## chunky blocks. Moves top-down with WASD / arrows, turning to face the way it
## walks, with a simple walk cycle (legs + free arm swing, slight body bob).
## SPACE swings the scythe; on the press we emit `swing(origin, forward)` so the
## GrassField can cut whatever is in the arc ahead. The character is clamped to
## the real island outline (Main.island_radius).
##
## All visual parts hang under `_rig`; movement/turning happen on the root, so
## the walk bob never moves the root origin the camera follows (no shake).

const Art := preload("res://Main.gd")  # reuse texture/material helpers

signal swing(origin: Vector3, forward: Vector3)

const SPEED := 6.0
const TURN_SPEED := 12.0
const EDGE_MARGIN := 0.7        # stay this far inside the coastline

# Scythe sweep
const SWING_DURATION := 0.32
const SCYTHE_REST_DEG := 70.0
const SCYTHE_SWING_DEG := -80.0
const ARM_REST_X := 0.5         # scythe arm's resting forward reach (+X = forward)

# Walk cycle
const WALK_FREQ := 9.0
const WALK_SWING := 0.5
const BOB_HEIGHT := 0.05

var current_velocity := Vector3.ZERO

var _rig: Node3D
var _scythe_pivot: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_free: Node3D
var _arm_scythe: Node3D
var _walk_phase := 0.0
var _walk_amt := 0.0
var _swinging := false
var _swing_t := 0.0


func _ready() -> void:
	_build_body()


func _build_body() -> void:
	_rig = Node3D.new()
	add_child(_rig)

	var skin := _mat(Color(0.86, 0.67, 0.52), 11)
	var shirt := _mat(Color(0.20, 0.45, 0.74), 12)
	var pants := _mat(Color(0.24, 0.26, 0.34), 13)
	var boots := _mat(Color(0.30, 0.20, 0.12), 14)
	var hair := _mat(Color(0.33, 0.21, 0.11), 15)
	var dark := _mat(Color(0.10, 0.09, 0.08), 16)

	# Legs (pivots at the hips so they can swing).
	_leg_l = _limb(Vector3(0.14, 0.66, 0.0))
	_leg_r = _limb(Vector3(-0.14, 0.66, 0.0))
	for leg in [_leg_l, _leg_r]:
		leg.add_child(_box(Vector3(0.22, 0.46, 0.26), Vector3(0, -0.23, 0), pants))
		leg.add_child(_box(Vector3(0.24, 0.16, 0.30), Vector3(0, -0.54, 0.02), boots))

	# Hips + torso.
	_rig.add_child(_box(Vector3(0.46, 0.18, 0.28), Vector3(0, 0.70, 0), pants))
	_rig.add_child(_box(Vector3(0.50, 0.62, 0.30), Vector3(0, 0.97, 0), shirt))

	# Free arm (animated) + scythe arm (static, reaching forward to hold it).
	_arm_free = _limb(Vector3(-0.35, 1.24, 0.0))
	_arm_free.add_child(_box(Vector3(0.15, 0.46, 0.20), Vector3(0, -0.23, 0), shirt))
	_arm_free.add_child(_box(Vector3(0.15, 0.12, 0.20), Vector3(0, -0.52, 0), skin))

	_arm_scythe = _limb(Vector3(0.35, 1.24, 0.0))
	_arm_scythe.rotation.x = ARM_REST_X
	_arm_scythe.add_child(_box(Vector3(0.15, 0.46, 0.20), Vector3(0, -0.23, 0), shirt))
	_arm_scythe.add_child(_box(Vector3(0.15, 0.12, 0.20), Vector3(0, -0.52, 0), skin))

	# Neck + head + hair + eyes (eyes on the -Z front, which also shows facing).
	_rig.add_child(_box(Vector3(0.16, 0.10, 0.16), Vector3(0, 1.32, 0), skin))
	_rig.add_child(_box(Vector3(0.46, 0.46, 0.42), Vector3(0, 1.60, 0), skin))
	_rig.add_child(_box(Vector3(0.50, 0.14, 0.46), Vector3(0, 1.84, 0), hair))
	_rig.add_child(_box(Vector3(0.50, 0.40, 0.12), Vector3(0, 1.62, 0.17), hair))
	_rig.add_child(_box(Vector3(0.08, 0.09, 0.05), Vector3(0.10, 1.62, -0.21), dark))
	_rig.add_child(_box(Vector3(0.08, 0.09, 0.05), Vector3(-0.10, 1.62, -0.21), dark))

	_build_scythe()


func _build_scythe() -> void:
	_scythe_pivot = Node3D.new()
	_scythe_pivot.position = Vector3(0.40, 1.05, 0.05)
	_scythe_pivot.rotation_degrees = Vector3(0.0, SCYTHE_REST_DEG, 0.0)
	_rig.add_child(_scythe_pivot)

	var wood := _mat(Color(0.45, 0.30, 0.16), 21)
	var metal := _mat(Color(0.74, 0.76, 0.80), 22)

	_scythe_pivot.add_child(_box(Vector3(0.06, 0.06, 1.3), Vector3(0, 0, -0.6), wood))
	var blade := _box(Vector3(0.60, 0.07, 0.14), Vector3(-0.24, 0, -1.2), metal)
	blade.rotation_degrees = Vector3(0.0, -38.0, 0.0)
	_scythe_pivot.add_child(blade)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_try_swing()


func _process(delta: float) -> void:
	_handle_movement(delta)
	_animate_walk(delta)
	_animate_swing(delta)


func _handle_movement(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0

	var move := Vector3.ZERO
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		move = Vector3(dir.x, 0.0, dir.y)
		# Face travel direction. Godot's forward is -Z, so the yaw that aligns
		# -Z with `move` is atan2(-x, -z).
		var target_yaw := atan2(-move.x, -move.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * TURN_SPEED, 0.0, 1.0))

	current_velocity = move * SPEED
	position += current_velocity * delta
	_clamp_to_island()


func _clamp_to_island() -> void:
	var h := Vector2(position.x, position.z)
	if h.length() < 0.001:
		return
	var ang := atan2(position.z, position.x)
	var max_r := Art.island_radius(ang) - EDGE_MARGIN
	if h.length() > max_r:
		h = h.normalized() * max_r
		position.x = h.x
		position.z = h.y


func _animate_walk(delta: float) -> void:
	var frac := clampf(current_velocity.length() / SPEED, 0.0, 1.0)
	_walk_amt = lerpf(_walk_amt, frac, clampf(delta * 10.0, 0.0, 1.0))
	if frac > 0.01:
		_walk_phase += delta * WALK_FREQ
	var s := sin(_walk_phase) * WALK_SWING * _walk_amt
	_leg_l.rotation.x = s
	_leg_r.rotation.x = -s
	_arm_free.rotation.x = -s
	_rig.position.y = absf(sin(_walk_phase)) * BOB_HEIGHT * _walk_amt


func _try_swing() -> void:
	if _swinging:
		return
	_swinging = true
	_swing_t = 0.0
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	swing.emit(global_position, forward.normalized())


func _animate_swing(delta: float) -> void:
	if not _swinging:
		return
	_swing_t += delta / SWING_DURATION
	if _swing_t >= 1.0:
		_swinging = false
		_scythe_pivot.rotation_degrees.y = SCYTHE_REST_DEG
		_arm_scythe.rotation = Vector3(ARM_REST_X, 0.0, 0.0)
		return
	var a := sin(_swing_t * PI)   # smooth out-and-back sweep
	_scythe_pivot.rotation_degrees.y = lerpf(SCYTHE_REST_DEG, SCYTHE_SWING_DEG, a)
	# Drive the holding arm with the same curve so it visibly swings the scythe:
	# a forward thrust (X) plus a sweep across the body (Y).
	_arm_scythe.rotation.x = lerpf(ARM_REST_X, 1.0, a)
	_arm_scythe.rotation.y = lerpf(0.0, -0.9, a)


# --- builders ---------------------------------------------------------------

func _limb(pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	_rig.add_child(pivot)
	return pivot


func _mat(color: Color, rng_seed: int) -> StandardMaterial3D:
	return Art.make_material(Art.make_pixel_texture(color, 0.05, rng_seed), 1.0)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi
