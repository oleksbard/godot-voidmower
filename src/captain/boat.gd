class_name Boat
extends Node3D
## The Dandelion — Captain Goldwake's stubby wooden skiff. Builds the hull + mast +
## a small dusk-orange sail from beveled boxes, then glides between a faraway void
## point and a beach landing at the +X shore (there is no dock), bobbing gently
## while berthed. Emits arrived/departed at the ends of its trips. Only the
## Captain ever rides it.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const ColorUtil := preload("res://src/lib/color_util.gd")
const ShoreLayout := preload("res://src/lib/shore_layout.gd")

signal arrived
signal departed

const BEVEL := 0.05
const SAIL_TIME := 2.5                          # seconds for a one-way trip
const DECK_OFFSET := Vector3(-0.6, 0.45, 0.0)   # boat-local spot the Captain stands on
const HULL_COL := Color(0.46, 0.30, 0.16)
const TRIM_COL := Color(0.34, 0.22, 0.12)
const SAIL_COL := Color(0.92, 0.55, 0.26)

var _seed := 800
var _t := 1.0                                   # trip progress (1.0 = arrived/idle)
var _from := ShoreLayout.FARAWAY
var _to := ShoreLayout.BERTH
var _sailing := false
var _bob_t := 0.0


func _ready() -> void:
	_build_hull()
	position = ShoreLayout.FARAWAY
	visible = false


func deck_point() -> Vector3:
	return to_global(DECK_OFFSET)


func sail_in() -> void:
	visible = true
	_trip(ShoreLayout.FARAWAY, ShoreLayout.BERTH)


func sail_out() -> void:
	visible = true
	_trip(ShoreLayout.BERTH, ShoreLayout.FARAWAY)


## Snap to berthed/visible immediately (reconciliation when the clock jumps).
func snap_berthed() -> void:
	_sailing = false
	_t = 1.0
	position = ShoreLayout.BERTH
	visible = true


## Snap to hidden/faraway immediately.
func snap_gone() -> void:
	_sailing = false
	_t = 1.0
	position = ShoreLayout.FARAWAY
	visible = false


func _trip(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	_t = 0.0
	_sailing = true
	position = from


func _process(delta: float) -> void:
	if _sailing:
		_t = minf(_t + delta / SAIL_TIME, 1.0)
		position = _from.lerp(_to, ease(_t, -2.0))   # ease in-out
		if _t >= 1.0:
			_sailing = false
			if _to == ShoreLayout.BERTH:
				arrived.emit()
			else:
				visible = false
				departed.emit()
	elif visible:
		_bob_t += delta
		position.y = sin(_bob_t * 1.6) * 0.06
		rotation.z = sin(_bob_t * 1.1) * 0.03


func _build_hull() -> void:
	# Hull: a wide base + a tapered prow (toward the island, -X) + raised gunwales.
	add_child(_part(Vector3(2.4, 0.4, 1.1), Vector3(0, 0.0, 0), HULL_COL))
	add_child(_part(Vector3(0.9, 0.5, 0.8), Vector3(-1.35, 0.05, 0), HULL_COL))   # prow block
	for sz in [-0.5, 0.5]:
		add_child(_part(Vector3(2.2, 0.3, 0.12), Vector3(0, 0.28, sz), TRIM_COL)) # gunwale
	add_child(_part(Vector3(0.7, 0.45, 0.7), Vector3(0.9, 0.3, 0), TRIM_COL))     # little cabin/crate
	# Mast + a small sail.
	add_child(_part(Vector3(0.1, 1.8, 0.1), Vector3(0.1, 1.1, 0), TRIM_COL))      # mast
	add_child(_part(Vector3(0.08, 1.0, 1.1), Vector3(0.12, 1.3, 0), SAIL_COL))    # sail


func _part(size: Vector3, pos: Vector3, base: Color) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_seed += 1
	var m := StandardMaterial3D.new()
	m.albedo_color = ColorUtil.vary(base, rng)
	m.roughness = clampf(0.82 + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.beveled_box(size, BEVEL)
	mi.material_override = m
	mi.position = pos
	return mi
