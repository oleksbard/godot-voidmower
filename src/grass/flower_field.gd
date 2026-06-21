class_name FlowerField
extends Node3D
## The rare blooms scattered among the grass. Each flower is a small multi-part
## node (stem + a ring of four petals + a center), so — unlike the grass, which
## is one MultiMesh — flowers stay as real nodes. They sway gently in the wind
## and, like the grass, can be mowed: a swing pops them and they regrow.
##
## Planted by [GrassField], which owns the grid: it calls `add_flower()` for the
## cells it rolls as bloom cells (one shared deterministic pass) and forwards
## each scythe swing via `cut_in_arc()`.

signal flower_dropped(world_pos: Vector3)

const ColorUtil := preload("res://src/lib/color_util.gd")

# Flower geometry: a stem, a ring of 4 petals, a center.
const STEM_SIZE := Vector3(0.05, 0.5, 0.05)
const PETAL_SIZE := Vector3(0.12, 0.06, 0.12)
const CENTER_SIZE := Vector3(0.12, 0.12, 0.12)
const STEM_CENTER_Y := 0.25     # stem mesh centred at half its height
const PETAL_RING_Y := 0.54      # height of the petal ring at the stem top
const PETAL_RADIUS := 0.12      # petal offset from the stem axis

# Gentle wind sway (stiffer + slower than grass — these are woody stems).
const WIND_AXIS := Vector3(0.4, 0.0, 1.0)
const WIND_AMP := deg_to_rad(5.0)
const WIND_FREQ := 1.3

# Mowing — matches the grass pop so a swing reads as one motion.
const CUT_ANIM_TIME := 0.3
const CUT_HOP_HEIGHT := 0.5
const REGROW_DELAY := 45.0      # match the grass: long wait...
const GROW_TIME := 15.0          # ...then grow fully back in over 15s
const GROW_FROM := 0.05
const FLOWER_DROP_CHANCE := 0.05   # chance a mown flower yields a flower item

enum { ALIVE, HIDDEN, GROWING }

# Shared resources — meshes/mats reused across all blooms; petal colour varies.
var _stem_mesh: BoxMesh
var _petal_mesh: BoxMesh
var _center_mesh: BoxMesh
var _stem_mat: StandardMaterial3D
var _center_mat: StandardMaterial3D
var _flower_colors: Array = []

var _flowers: Array[Node3D] = []   # the per-bloom pivots
var _base_h := PackedFloat32Array()
var _state := PackedInt32Array()
var _cutting: Array = []           # [{i, t, axis}]
var _regrow_queue: Array = []      # [{i, at}]
var _growing: Array = []           # [{i, t}]

var _wind_axis := WIND_AXIS.normalized()
var _clock := 0.0
var _anim_rng := RandomNumberGenerator.new()
var _drop_rng := RandomNumberGenerator.new()


func _init() -> void:
	# Built in _init (not _ready) so add_flower() works the instant GrassField
	# adds us and starts planting, without waiting a frame.
	_anim_rng.seed = 2024
	_drop_rng.seed = 7777
	_stem_mesh = BoxMesh.new()
	_stem_mesh.size = STEM_SIZE
	_petal_mesh = BoxMesh.new()
	_petal_mesh.size = PETAL_SIZE
	_center_mesh = BoxMesh.new()
	_center_mesh.size = CENTER_SIZE
	_stem_mat = StandardMaterial3D.new()
	_stem_mat.albedo_color = Color(0.24, 0.46, 0.20)
	_stem_mat.roughness = 1.0
	_center_mat = StandardMaterial3D.new()
	_center_mat.albedo_color = Color(0.95, 0.82, 0.25)
	_center_mat.roughness = 0.8
	_flower_colors = [
		Color(0.86, 0.22, 0.22), Color(0.96, 0.96, 0.92), Color(0.95, 0.52, 0.72),
		Color(0.62, 0.33, 0.82), Color(0.96, 0.80, 0.24), Color(0.42, 0.52, 0.92),
	]


## Plant one bloom at (px, pz). `height` stretches the stem a little; `rng` seeds
## the petal colour + facing so the field stays deterministic.
func add_flower(px: float, pz: float, height: float, rng: RandomNumberGenerator) -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(px, 0.0, pz)
	pivot.scale = Vector3(1.0, height, 1.0)
	pivot.add_child(_make_flower(rng))
	add_child(pivot)
	_flowers.append(pivot)
	_base_h.append(height)
	_state.append(ALIVE)


## Pop every living bloom inside the swing arc (same radius/arc as the grass).
## Returns how many were cut so the caller can fold them into the mow count.
func cut_in_arc(origin: Vector3, forward: Vector3, cut_radius: float, cos_arc: float) -> int:
	var f := forward
	f.y = 0.0
	if f.length() < 0.001:
		return 0
	f = f.normalized()
	var n := 0
	for i in _flowers.size():
		if _state[i] != ALIVE:
			continue
		var to := _flowers[i].global_position - origin
		to.y = 0.0
		var dist := to.length()
		if dist <= cut_radius and (dist < 0.001 or f.dot(to / dist) >= cos_arc):
			_state[i] = HIDDEN
			_cutting.append({"i": i, "t": 0.0, "axis": _random_axis()})
			if _drop_rng.randf() < FLOWER_DROP_CHANCE:
				flower_dropped.emit(_flowers[i].global_position)
			n += 1
	return n


func _make_flower(rng: RandomNumberGenerator) -> Node3D:
	var g := Node3D.new()

	var stem := MeshInstance3D.new()
	stem.mesh = _stem_mesh
	stem.material_override = _stem_mat
	stem.position = Vector3(0.0, STEM_CENTER_Y, 0.0)
	g.add_child(stem)

	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = ColorUtil.vary(_flower_colors[rng.randi() % _flower_colors.size()], rng)
	pmat.roughness = 0.7
	var hy := PETAL_RING_Y
	for off in [Vector3(PETAL_RADIUS, 0, 0), Vector3(-PETAL_RADIUS, 0, 0), Vector3(0, 0, PETAL_RADIUS), Vector3(0, 0, -PETAL_RADIUS)]:
		var petal := MeshInstance3D.new()
		petal.mesh = _petal_mesh
		petal.material_override = pmat
		petal.position = Vector3(off.x, hy, off.z)
		g.add_child(petal)

	var center := MeshInstance3D.new()
	center.mesh = _center_mesh
	center.material_override = _center_mat
	center.position = Vector3(0.0, hy + 0.02, 0.0)
	g.add_child(center)

	g.rotation.y = rng.randf_range(0.0, TAU)
	return g


func _process(delta: float) -> void:
	_clock += delta
	_update_wind()
	_update_cutting(delta)
	_update_regrow()
	_update_growth(delta)


func _update_wind() -> void:
	for i in _flowers.size():
		if _state[i] != ALIVE:
			continue                    # don't fight the pop / grow-in
		var f := _flowers[i]
		# Per-bloom phase so the patch ripples instead of swaying as one.
		var phase := f.position.x * 0.5 + f.position.z * 0.4
		f.quaternion = Quaternion(_wind_axis, sin(_clock * WIND_FREQ + phase) * WIND_AMP)


func _update_cutting(delta: float) -> void:
	if _cutting.is_empty():
		return
	var still: Array = []
	for c in _cutting:
		c.t += delta / CUT_ANIM_TIME
		var pivot: Node3D = _flowers[c.i]
		var base_h: float = _base_h[c.i]
		if c.t >= 1.0:
			pivot.visible = false
			pivot.position.y = 0.0
			pivot.quaternion = Quaternion.IDENTITY
			pivot.scale = Vector3(1.0, base_h, 1.0)
			_regrow_queue.append({"i": c.i, "at": _clock + REGROW_DELAY})
		else:
			var k: float = c.t
			var fade := 1.0 - k
			pivot.scale = Vector3(fade, base_h * fade, fade)
			pivot.position.y = sin(k * PI) * CUT_HOP_HEIGHT
			pivot.quaternion = Quaternion(c.axis, k * TAU)
			still.append(c)
	_cutting = still


func _update_regrow() -> void:
	if _regrow_queue.is_empty():
		return
	var still: Array = []
	for item in _regrow_queue:
		if _clock >= item.at:
			var i: int = item.i
			var pivot: Node3D = _flowers[i]
			pivot.visible = true
			pivot.quaternion = Quaternion.IDENTITY
			pivot.scale = Vector3(1.0, GROW_FROM, 1.0)
			_state[i] = GROWING
			_growing.append({"i": i, "t": 0.0})
		else:
			still.append(item)
	_regrow_queue = still


func _update_growth(delta: float) -> void:
	if _growing.is_empty():
		return
	var still: Array = []
	for g in _growing:
		g.t += delta / GROW_TIME
		var i: int = g.i
		var base_h: float = _base_h[i]
		if g.t >= 1.0:
			_flowers[i].scale = Vector3(1.0, base_h, 1.0)
			_state[i] = ALIVE
		else:
			_flowers[i].scale = Vector3(1.0, lerpf(GROW_FROM, base_h, g.t), 1.0)
			still.append(g)
	_growing = still


func _random_axis() -> Vector3:
	var a := Vector3(
		_anim_rng.randf_range(-1.0, 1.0),
		_anim_rng.randf_range(-0.3, 0.3),
		_anim_rng.randf_range(-1.0, 1.0)
	)
	if a.length() < 0.01:
		return Vector3.RIGHT
	return a.normalized()
