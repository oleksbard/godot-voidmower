class_name Player
extends Node3D
## The mower's controller: input, movement, animation, and the swing signal.
##
## The visual body is built by [PlayerRig] (a child node); this script only
## drives it. Moves top-down with WASD / arrows, turning to face travel, with a
## walk cycle (legs + free arm swing, slight body bob). SPACE swings the scythe —
## the holding arm drives it — and emits `swing(origin, forward)` so the
## GrassField can cut the arc ahead. Clamped to the real island outline.
##
## Movement/turning happen on this root; the walk bob moves the *rig's* local Y,
## so the root the camera follows never shakes.

const PlayerRigScript := preload("res://src/player/player_rig.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")

signal swing(origin: Vector3, forward: Vector3)

const SPEED := 6.0
const TURN_SPEED := 12.0
const EDGE_MARGIN := 0.7

# Scythe sweep. The scythe is gripped in the hand, so swinging the arm sweeps
# the whole scythe — no separate scythe rotation needed.
const SWING_DURATION := 0.32
const ARM_SWING_X := 1.05     # forward thrust at the peak of the swing
const ARM_SWING_Y := -1.35    # sweep across at the peak of the swing

# Walk cycle
const WALK_FREQ := 9.0
const WALK_SWING := 0.5
const BOB_HEIGHT := 0.05

var current_velocity := Vector3.ZERO

var _rig: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_free: Node3D
var _arm_scythe: Node3D
var _walk_phase := 0.0
var _walk_amt := 0.0
var _swinging := false
var _swing_t := 0.0


func _ready() -> void:
	_rig = PlayerRigScript.new()
	add_child(_rig)                  # rig._ready() builds the body synchronously
	_leg_l = _rig.leg_l
	_leg_r = _rig.leg_r
	_arm_free = _rig.arm_free
	_arm_scythe = _rig.arm_scythe


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
		var target_yaw := atan2(-move.x, -move.z)   # Godot forward is -Z
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * TURN_SPEED, 0.0, 1.0))

	current_velocity = move * SPEED
	position += current_velocity * delta
	_clamp_to_island()


func _clamp_to_island() -> void:
	var h := Vector2(position.x, position.z)
	if h.length() < 0.001:
		return
	var ang := atan2(position.z, position.x)
	var max_r := IslandShape.radius(ang) - EDGE_MARGIN
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
		_arm_scythe.rotation = Vector3(PlayerRigScript.ARM_REST_X, 0.0, 0.0)
		return
	var a := sin(_swing_t * PI)   # smooth out-and-back sweep
	_arm_scythe.rotation.x = lerpf(PlayerRigScript.ARM_REST_X, ARM_SWING_X, a)   # forward thrust
	_arm_scythe.rotation.y = lerpf(0.0, ARM_SWING_Y, a)                          # sweep across
