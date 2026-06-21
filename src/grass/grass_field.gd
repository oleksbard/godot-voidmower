class_name GrassField
extends Node3D
## A field of grass blades the player can walk through and mow — drawn as a
## single [MultiMesh] (one draw call for thousands of blades). Per-blade state
## lives in parallel arrays indexed by instance; the visible transform of each
## instance is composed on demand from that state.
##
##   - BEND/WIND: each frame, blades near the player tilt away from them (stronger
##           the closer they are); the rest get a cheap, throttled ambient breeze.
##   - CUT:  swinging the scythe hides the instances in the arc ahead (scaled to
##           ~0) and spawns a transient "flying blade" node per cut that plays the
##           cute pop (a little hop + tumble-spin + shrink), plus a burst of
##           grass-clipping particles.
##   - REGROW: cut instances grow back in from the ground after REGROW_DELAY.
##
## Flowers are separate real nodes — see [FlowerField], which this field owns and
## populates during planting (one shared deterministic grid pass).

const TextureFactory := preload("res://src/lib/texture_factory.gd")
const ColorUtil := preload("res://src/lib/color_util.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")
const FlowerFieldScript := preload("res://src/grass/flower_field.gd")

signal mowed_changed(count: int)

# Set by Main before this node is added to the tree.
var player: Node3D

const SPACING := 0.4           # smaller = denser grass
const EDGE_MARGIN := 0.6       # keep blades just inside the coastline
const JITTER := 0.16           # small position scatter so it isn't a rigid grid

# Per-blade shape variation (kills the "identical sticks" look)
const MIN_HEIGHT := 0.62
const MAX_HEIGHT := 1.55
const MIN_WIDTH := 0.7
const MAX_WIDTH := 1.45
const MAX_TILT := deg_to_rad(16.0)   # natural lean baked per blade
const FLOWER_CHANCE := 0.025         # rare blooms scattered among the grass

# Blade geometry
const BLADE_SIZE := Vector3(0.07, 0.6, 0.07)

# Bending
const BEND_RADIUS := 2.4
const MAX_LEAN := deg_to_rad(60.0)
const SPRING := 8.0            # how fast blades settle toward their target tilt

# Ambient wind sway (applied to blades the player isn't disturbing)
const WIND_AXIS := Vector3(0.4, 0.0, 1.0)
const WIND_AMP := deg_to_rad(7.0)
const WIND_FREQ := 1.6
const WIND_STRIDE := 4         # far/wind-only blades refresh 1 frame in N

# Cutting
const CUT_RADIUS := 2.2
const ARC_HALF_DEG := 70.0     # half-width of the swing arc in front of player
const CUT_ANIM_TIME := 0.3     # duration of the cute pop before the blade hides
const CUT_HOP_HEIGHT := 0.5    # how high a cut blade hops during its pop

# Regrow / grow-in
const REGROW_DELAY := 8.0
const GROW_TIME := 0.45
const GROW_FROM := 0.05        # seedling Y-scale a regrowing blade starts from

enum { ALIVE, HIDDEN, GROWING }   # per-instance lifecycle

# Per-blade state, parallel arrays indexed by MultiMesh instance.
var _count := 0
var _base_pos := PackedVector3Array()    # ground position (x, 0, z)
var _base_h := PackedFloat32Array()       # full-grown height scale
var _width := PackedFloat32Array()        # thickness scale
var _yaw := PackedFloat32Array()          # facing
var _tilt_x := PackedFloat32Array()       # baked natural lean
var _tilt_z := PackedFloat32Array()
var _wind_phase := PackedFloat32Array()   # per-blade breeze phase offset
var _state := PackedInt32Array()          # ALIVE / HIDDEN / GROWING
var _lean: Array[Quaternion] = []         # current bend/wind tilt (slerped)

var mowed := 0
var _clock := 0.0
var _frame := 0

var _mm: MultiMesh
var _wind_axis := WIND_AXIS.normalized()
var _clippings: CPUParticles3D
var _pop_mesh: BoxMesh
var _pop_mat: StandardMaterial3D
var _anim_rng := RandomNumberGenerator.new()

var _cutting: Array = []        # transient flying-blade pops [{node, t, axis, base_h}]
var _regrow_queue: Array = []   # [{i, at}]
var _growing: Array = []        # [{i, t}]

var _flowers: Node3D            # FlowerField (typed as Node3D for cold-cache safety)


func _ready() -> void:
	_anim_rng.seed = 4242
	_build_multimesh()
	_build_pop_resources()
	_build_clippings()
	_flowers = FlowerFieldScript.new()
	add_child(_flowers)
	_plant_field()


# --- build ------------------------------------------------------------------

func _build_multimesh() -> void:
	var mesh := BoxMesh.new()
	mesh.size = BLADE_SIZE
	mesh.material = _blade_material()

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true                  # must be set before instance_count
	_mm.mesh = mesh

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	add_child(mmi)


## One shared material for all blades: a neutral vertical gradient (dark base ->
## light tip) that per-instance COLOR tints to a varied green — so the whole
## field is one draw call yet no two blades read as the same flat green.
func _blade_material() -> StandardMaterial3D:
	var grad := TextureFactory.gradient(Color(0.45, 0.45, 0.45), Color(0.95, 0.95, 0.95), 70)
	var m := TextureFactory.material(grad, 1.0)
	m.vertex_color_use_as_albedo = true
	return m


func _build_pop_resources() -> void:
	_pop_mesh = BoxMesh.new()
	_pop_mesh.size = BLADE_SIZE
	_pop_mat = StandardMaterial3D.new()
	_pop_mat.albedo_color = Color(0.36, 0.66, 0.26)
	_pop_mat.roughness = 1.0


func _build_clippings() -> void:
	# One reusable one-shot emitter; we reposition + restart() it per swing.
	var bit := BoxMesh.new()
	bit.size = Vector3(0.11, 0.11, 0.11)
	var bit_mat := StandardMaterial3D.new()
	bit_mat.albedo_color = Color(0.36, 0.72, 0.28)
	bit_mat.roughness = 1.0
	bit.material = bit_mat

	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 22
	p.lifetime = 0.7
	p.mesh = bit
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -13.0, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	_clippings = p
	add_child(_clippings)


func _plant_field() -> void:
	# Cover a grid spanning the island's bounding box, but only keep blades that
	# fall inside the real organic coastline (just inside the cliff edge). Rolls
	# of FLOWER_CHANCE become flowers (handed to the FlowerField); the rest are
	# grass instances. One rng stream -> one deterministic, non-overlapping pass.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var crng := RandomNumberGenerator.new()
	crng.seed = 71
	# Green tints (multiply the neutral gradient); spans several grass tones.
	var palette := [
		Color(0.42, 0.74, 0.30), Color(0.33, 0.60, 0.23), Color(0.57, 0.83, 0.35),
		Color(0.39, 0.78, 0.47), Color(0.63, 0.80, 0.32),
	]
	var colors: Array[Color] = []

	var limit := IslandShape.BASE * 1.32
	var x := -limit
	while x <= limit:
		var z := -limit
		while z <= limit:
			var px := x + rng.randf_range(-JITTER, JITTER)
			var pz := z + rng.randf_range(-JITTER, JITTER)
			var ang := atan2(pz, px)
			if Vector2(px, pz).length() <= IslandShape.radius(ang) - EDGE_MARGIN:
				if rng.randf() < FLOWER_CHANCE:
					_flowers.add_flower(px, pz, rng.randf_range(0.9, 1.1), rng)
				else:
					_base_pos.append(Vector3(px, 0.0, pz))
					_base_h.append(rng.randf_range(MIN_HEIGHT, MAX_HEIGHT))
					_width.append(rng.randf_range(MIN_WIDTH, MAX_WIDTH))
					_yaw.append(rng.randf_range(0.0, TAU))
					_tilt_x.append(rng.randf_range(-MAX_TILT, MAX_TILT))
					_tilt_z.append(rng.randf_range(-MAX_TILT, MAX_TILT))
					_wind_phase.append(px * 0.6 + pz * 0.45)
					_state.append(ALIVE)
					_lean.append(Quaternion.IDENTITY)
					colors.append(ColorUtil.vary(palette[crng.randi() % palette.size()], crng))
			z += SPACING
		x += SPACING

	_count = _base_pos.size()
	_mm.instance_count = _count
	for i in _count:
		_mm.set_instance_color(i, colors[i])
		_mm.set_instance_transform(i, _compose(i, _lean[i], _base_h[i]))


## The full transform of instance `i`: stand a unit blade on the ground at its
## base, apply the baked lean + facing and the current bend, scaled to width and
## the given height. Tilt rotates about the base; the lift keeps the base planted.
func _compose(i: int, lean: Quaternion, height: float) -> Transform3D:
	var w := _width[i]
	var basis := Basis(lean) * Basis.from_euler(Vector3(_tilt_x[i], _yaw[i], _tilt_z[i])) * Basis().scaled(Vector3(w, height, w))
	var origin := _base_pos[i] + basis * Vector3(0.0, BLADE_SIZE.y * 0.5, 0.0)
	return Transform3D(basis, origin)


# --- per-frame --------------------------------------------------------------

func _process(delta: float) -> void:
	_frame += 1
	_clock += delta
	_update_field(delta)
	_update_cutting(delta)
	_update_regrow()
	_update_growth(delta)


## Bend blades near the player away from them; everything else gets a throttled
## ambient breeze (only 1 blade in WIND_STRIDE refreshes per frame — wind is slow
## enough that the stagger is invisible, and it keeps the per-frame cost down).
func _update_field(delta: float) -> void:
	if player == null:
		return
	var p := player.global_position
	p.y = 0.0
	var w := clampf(delta * SPRING, 0.0, 1.0)
	for i in _count:
		if _state[i] != ALIVE:
			continue
		var to := _base_pos[i] - p
		to.y = 0.0
		var dist := to.length()
		var near := dist > 0.001 and dist < BEND_RADIUS
		if not near and (i + _frame) % WIND_STRIDE != 0:
			continue
		var target: Quaternion
		if near:
			var push := to / dist                          # horizontal dir away from player
			var strength := 1.0 - dist / BEND_RADIUS        # 0 at edge, 1 on top of player
			var axis := Vector3(push.z, 0.0, -push.x).normalized()
			target = Quaternion(axis, strength * MAX_LEAN)  # tip leans toward `push`
		else:
			target = Quaternion(_wind_axis, sin(_clock * WIND_FREQ + _wind_phase[i]) * WIND_AMP)
		_lean[i] = _lean[i].slerp(target, w)
		_mm.set_instance_transform(i, _compose(i, _lean[i], _base_h[i]))


func on_swing(origin: Vector3, forward: Vector3) -> void:
	var f := forward
	f.y = 0.0
	if f.length() < 0.001:
		return
	f = f.normalized()
	var cos_arc := cos(deg_to_rad(ARC_HALF_DEG))
	var newly := 0
	var sum := Vector3.ZERO
	for i in _count:
		if _state[i] != ALIVE:
			continue
		var to := _base_pos[i] - origin
		to.y = 0.0
		var dist := to.length()
		if dist <= CUT_RADIUS and (dist < 0.001 or f.dot(to / dist) >= cos_arc):
			_cut_blade(i)
			sum += _base_pos[i]
			newly += 1

	# Flowers get mowed too (separate nodes, same arc).
	var flowers_cut := 0
	if _flowers != null:
		flowers_cut = _flowers.cut_in_arc(origin, f, CUT_RADIUS, cos_arc)

	var total := newly + flowers_cut
	if total > 0:
		mowed += total
		mowed_changed.emit(mowed)
		# Burst at the grass centroid if any grass fell, otherwise at the swing.
		var centroid := (sum / float(newly)) if newly > 0 else origin
		_clippings.global_position = Vector3(centroid.x, 0.35, centroid.z)
		_clippings.restart()
		_clippings.emitting = true


## Hide the instance instantly and hand its pop off to a transient node, then
## queue the regrow. (A MultiMesh instance can't be tweened like a node, so the
## cute hop/tumble/shrink rides on a throwaway node that frees itself.)
func _cut_blade(i: int) -> void:
	_state[i] = HIDDEN
	_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), _base_pos[i]))
	_spawn_pop(i)
	_regrow_queue.append({"i": i, "at": _clock + REGROW_DELAY})


## A throwaway copy of the just-cut blade (pivot + lifted blade child, matching
## the standing blade's pose) that plays the pop in _update_cutting.
func _spawn_pop(i: int) -> void:
	var child := MeshInstance3D.new()
	child.mesh = _pop_mesh
	child.material_override = _pop_mat
	child.position = Vector3(0.0, BLADE_SIZE.y * 0.5, 0.0)
	child.rotation = Vector3(_tilt_x[i], _yaw[i], _tilt_z[i])
	child.scale = Vector3(_width[i], 1.0, _width[i])

	var pivot := Node3D.new()
	pivot.position = _base_pos[i]
	pivot.scale = Vector3(1.0, _base_h[i], 1.0)
	pivot.add_child(child)
	add_child(pivot)
	_cutting.append({"node": pivot, "t": 0.0, "axis": _random_axis(), "base_h": _base_h[i]})


func _update_cutting(delta: float) -> void:
	if _cutting.is_empty():
		return
	var still: Array = []
	for c in _cutting:
		c.t += delta / CUT_ANIM_TIME
		var pivot: Node3D = c.node
		var base_h: float = c.base_h
		if c.t >= 1.0:
			pivot.queue_free()
		else:
			var k: float = c.t
			var fade := 1.0 - k
			pivot.scale = Vector3(fade, base_h * fade, fade)   # shrink away
			pivot.position.y = sin(k * PI) * CUT_HOP_HEIGHT     # little hop
			pivot.quaternion = Quaternion(c.axis, k * TAU)      # one cute tumble
			still.append(c)
	_cutting = still


func _update_regrow() -> void:
	if _regrow_queue.is_empty():
		return
	var still: Array = []
	for item in _regrow_queue:
		if _clock >= item.at:
			var i: int = item.i
			_state[i] = GROWING
			_lean[i] = Quaternion.IDENTITY
			_growing.append({"i": i, "t": 0.0})
			_mm.set_instance_transform(i, _compose(i, _lean[i], GROW_FROM))
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
		if g.t >= 1.0:
			_state[i] = ALIVE
			_mm.set_instance_transform(i, _compose(i, _lean[i], _base_h[i]))
		else:
			_mm.set_instance_transform(i, _compose(i, _lean[i], lerpf(GROW_FROM, _base_h[i], g.t)))
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
