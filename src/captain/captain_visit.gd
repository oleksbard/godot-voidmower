class_name CaptainVisit
extends Node3D
## Orchestrates the Captain's scheduled visits. There is no dock — the boat
## beaches at the +X shore. Builds and owns the stall (shown only during a
## visit), the boat, and the Captain. Main feeds it the day/time from DayNight;
## it uses VisitSchedule to fire the arrival and departure sequences, and snaps
## to the correct end-state on the very first tick (so starting mid-visit just
## shows the Captain at his stall). Emits presence_changed so the player's
## walkable clamp can block the stall+Captain only while he is here.

const VisitSchedule := preload("res://src/captain/visit_schedule.gd")
const ShoreLayout := preload("res://src/lib/shore_layout.gd")
const Stall := preload("res://src/captain/stall.gd")
const BoatScript := preload("res://src/captain/boat.gd")
const CaptainScript := preload("res://src/captain/captain.gd")

signal presence_changed(active: bool)   # true while the Captain is on the island

enum Phase { IDLE, ARRIVING, DEPARTING }

var _boat: Node3D
var _captain: Node3D
var _stall: Node3D
var _present := false
var _initialised := false
var _phase := Phase.IDLE


func _ready() -> void:
	_stall = Stall.build()
	_stall.position = ShoreLayout.STALL_SPOT
	_stall.visible = false
	add_child(_stall)

	_boat = BoatScript.new()
	add_child(_boat)

	_captain = CaptainScript.new()
	add_child(_captain)

	_boat.arrived.connect(_on_boat_arrived)
	_captain.path_done.connect(_on_captain_path_done)


## Called by Main from DayNight.time_changed.
func on_time(day: int, hour: float) -> void:
	var want := VisitSchedule.present_at(day, hour)
	if not _initialised:
		_initialised = true
		_present = want
		_snap(want)                     # first tick: snap, no animation
		presence_changed.emit(want)
		return
	if want == _present:
		return
	_present = want
	presence_changed.emit(want)         # toggle the player's no-go block
	if want:
		_arrive()
	else:
		_depart()


func _arrive() -> void:
	_phase = Phase.ARRIVING
	_captain.ride(_boat)
	_boat.sail_in()                     # _on_boat_arrived continues the sequence


func _on_boat_arrived() -> void:
	if _phase == Phase.ARRIVING and _present:
		_captain.walk_path(ShoreLayout.arrival_path())   # _on_captain_path_done shows the stall


func _on_captain_path_done() -> void:
	if _phase == Phase.ARRIVING:
		if _present:
			_stall.visible = true
			_captain.idle()
		_phase = Phase.IDLE
	elif _phase == Phase.DEPARTING:
		_captain.ride(_boat)
		_boat.sail_out()
		_phase = Phase.IDLE


func _depart() -> void:
	_phase = Phase.DEPARTING
	_stall.visible = false
	var back: Array[Vector3] = [ShoreLayout.BOARD_SPOT]
	_captain.walk_path(back)            # _on_captain_path_done boards + sails out


func _snap(present: bool) -> void:
	_phase = Phase.IDLE
	if present:
		_boat.snap_berthed()
		_stall.visible = true
		_captain.snap_to(ShoreLayout.CAPTAIN_STAND)
	else:
		_boat.snap_gone()
		_stall.visible = false
		_captain.hide_captain()
