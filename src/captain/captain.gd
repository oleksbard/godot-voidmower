class_name Captain
extends Node3D
## Captain Goldwake's controller: drives a CaptainRig with a walk cycle, walks a
## path of world points, rides the boat, or idles. No player input — the
## CaptainVisit orchestrator tells it what to do. Mirrors the Player split.

const CaptainRigScript := preload("res://src/captain/captain_rig.gd")

signal path_done

enum State { HIDDEN, RIDING, WALKING, IDLE }

const SPEED := 2.6
const TURN_SPEED := 10.0
const WALK_FREQ := 8.0
const WALK_SWING := 0.5
const ARRIVE_DIST := 0.12

var _rig: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _state := State.HIDDEN
var _path: Array[Vector3] = []
var _path_i := 0
var _boat: Node3D
var _walk_phase := 0.0
var _idle_t := 0.0


func _ready() -> void:
	_rig = CaptainRigScript.new()
	add_child(_rig)
	_leg_l = _rig.leg_l
	_leg_r = _rig.leg_r
	_arm_l = _rig.arm_l
	_arm_r = _rig.arm_r
	visible = false


func ride(boat: Node3D) -> void:
	_boat = boat
	_state = State.RIDING
	visible = true


func walk_path(points: Array[Vector3]) -> void:
	if points.is_empty():
		return
	_path = points
	_path_i = 0
	_state = State.WALKING
	visible = true


func idle() -> void:
	_state = State.IDLE
	_idle_t = 0.0
	visible = true


func hide_captain() -> void:
	_state = State.HIDDEN
	visible = false


## Snap to a fixed spot, idling (reconciliation when the clock jumps).
func snap_to(point: Vector3) -> void:
	global_position = point
	idle()


func _process(delta: float) -> void:
	match _state:
		State.RIDING:
			if _boat != null:
				global_position = _boat.deck_point()
		State.WALKING:
			_walk(delta)
		State.IDLE:
			_idle(delta)
		State.HIDDEN:
			pass


func _walk(delta: float) -> void:
	var target: Vector3 = _path[_path_i]
	var to := target - global_position
	to.y = 0.0
	if to.length() <= ARRIVE_DIST:
		_path_i += 1
		if _path_i >= _path.size():
			_state = State.IDLE
			_reset_legs()
			path_done.emit()
		return
	var dir := to.normalized()
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * TURN_SPEED, 0.0, 1.0))
	global_position += dir * SPEED * delta
	_walk_phase += delta * WALK_FREQ
	var s := sin(_walk_phase) * WALK_SWING
	_leg_l.rotation.x = s
	_leg_r.rotation.x = -s
	_arm_l.rotation.x = -s
	_arm_r.rotation.x = s


func _idle(delta: float) -> void:
	_idle_t += delta
	_rig.position.y = sin(_idle_t * 1.5) * 0.02   # gentle breathe on the rig's local Y


func _reset_legs() -> void:
	_leg_l.rotation.x = 0.0
	_leg_r.rotation.x = 0.0
	_arm_l.rotation.x = 0.0
	_arm_r.rotation.x = 0.0
