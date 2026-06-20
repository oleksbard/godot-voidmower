extends Node3D
## A field of grass blades the player can walk through and mow.
##
## Each blade is a tall thin box on a pivot anchored at ground level:
##   - BEND: every frame, blades near the player tilt away from them (stronger
##           the closer they are) and spring back upright once the player leaves
##           — so the grass visibly reacts as the character moves through it.
##   - CUT:  swinging the scythe flags blades in the arc ahead as "busy" and
##           plays a cute pop (a little hop + tumble-spin + shrink), and fires a
##           burst of grass-clipping particles.
##   - REGROW: cut blades grow back in from the ground after REGROW_DELAY.
## Tilt lives on the pivot's rotation; height/grow lives on the pivot's Y scale,
## so the two never fight each other. A per-blade "busy" flag keeps the bend
## loop from touching blades mid-cut or mid-regrow.

const Art := preload("res://Main.gd")  # reuse texture/material helpers

signal mowed_changed(count: int)

# Set by Main before this node is added to the tree.
var player: Node3D

const SPACING := 0.5           # smaller = denser grass
const EDGE_MARGIN := 0.6       # keep blades just inside the coastline
const JITTER := 0.15           # small position scatter so it isn't a rigid grid

# Bending
const BEND_RADIUS := 2.4
const MAX_LEAN := deg_to_rad(60.0)
const SPRING := 8.0            # how fast blades settle toward their target tilt

# Cutting
const CUT_RADIUS := 2.2
const ARC_HALF_DEG := 70.0     # half-width of the swing arc in front of player
const CUT_ANIM_TIME := 0.3     # duration of the cute pop before the blade hides

# Regrow / grow-in
const REGROW_DELAY := 8.0
const GROW_TIME := 0.45

var _blades: Array[Node3D] = []
var _regrow_queue: Array = []  # [{node, at}]
var _growing: Array = []       # [{node, t}]
var _cutting: Array = []       # [{node, t, axis}]
var _clock := 0.0
var mowed := 0

var _blade_mesh: BoxMesh
var _blade_mat: StandardMaterial3D
var _clippings: CPUParticles3D
var _anim_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_anim_rng.seed = 4242
	_blade_mesh = BoxMesh.new()
	_blade_mesh.size = Vector3(0.07, 0.6, 0.07)
	_blade_mat = Art.make_material(
		Art.make_gradient_texture(Color(0.20, 0.42, 0.16), Color(0.46, 0.80, 0.34), 70), 1.0
	)
	_build_clippings()
	_plant_field()


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
	# fall inside the real organic coastline (just inside the cliff edge).
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var limit := Art.ISLAND_RADIUS * 1.32
	var x := -limit
	while x <= limit:
		var z := -limit
		while z <= limit:
			var px := x + rng.randf_range(-JITTER, JITTER)
			var pz := z + rng.randf_range(-JITTER, JITTER)
			var ang := atan2(pz, px)
			if Vector2(px, pz).length() <= Art.island_radius(ang) - EDGE_MARGIN:
				_make_blade(px, pz, rng.randf_range(0.0, TAU), rng.randf_range(0.9, 1.12))
			z += SPACING
		x += SPACING


func _make_blade(px: float, pz: float, yaw: float, base_h: float) -> void:
	var pivot := Node3D.new()              # tilt + grow + cut-pop happen here
	pivot.position = Vector3(px, 0.0, pz)
	pivot.scale = Vector3(1.0, base_h, 1.0)
	pivot.set_meta("base_h", base_h)
	pivot.set_meta("busy", false)

	var mi := MeshInstance3D.new()         # the actual blade, lifted to sit on the ground
	mi.mesh = _blade_mesh
	mi.material_override = _blade_mat
	mi.position = Vector3(0.0, 0.3, 0.0)
	mi.rotation.y = yaw                     # random facing so it doesn't look gridded
	pivot.add_child(mi)

	add_child(pivot)
	_blades.append(pivot)


func _process(delta: float) -> void:
	_clock += delta
	_update_bend(delta)
	_update_cutting(delta)
	_update_regrow()
	_update_growth(delta)


func _update_bend(delta: float) -> void:
	if player == null:
		return
	var p := player.global_position
	p.y = 0.0
	var w := clampf(delta * SPRING, 0.0, 1.0)
	for b in _blades:
		if not b.visible or b.get_meta("busy"):
			continue
		var to := b.global_position - p
		to.y = 0.0
		var dist := to.length()
		var target := Quaternion.IDENTITY
		if dist > 0.001 and dist < BEND_RADIUS:
			var push := to / dist                          # horizontal dir away from player
			var strength := 1.0 - dist / BEND_RADIUS        # 0 at edge, 1 on top of player
			var axis := Vector3(push.z, 0.0, -push.x).normalized()
			target = Quaternion(axis, strength * MAX_LEAN)  # tip leans toward `push`
		elif b.quaternion.is_equal_approx(Quaternion.IDENTITY):
			continue                                        # far + already upright: skip work
		b.quaternion = b.quaternion.slerp(target, w)


func on_swing(origin: Vector3, forward: Vector3) -> void:
	var f := forward
	f.y = 0.0
	if f.length() < 0.001:
		return
	f = f.normalized()
	var cos_arc := cos(deg_to_rad(ARC_HALF_DEG))
	var newly := 0
	var sum := Vector3.ZERO
	for b in _blades:
		if not b.visible or b.get_meta("busy"):
			continue
		var to := b.global_position - origin
		to.y = 0.0
		var dist := to.length()
		if dist <= CUT_RADIUS and (dist < 0.001 or f.dot(to / dist) >= cos_arc):
			b.set_meta("busy", true)
			_cutting.append({"node": b, "t": 0.0, "axis": _random_axis()})
			sum += b.global_position
			newly += 1
	if newly > 0:
		mowed += newly
		mowed_changed.emit(mowed)
		var centroid := sum / float(newly)
		_clippings.global_position = Vector3(centroid.x, 0.35, centroid.z)
		_clippings.restart()
		_clippings.emitting = true


func _update_cutting(delta: float) -> void:
	if _cutting.is_empty():
		return
	var still: Array = []
	for c in _cutting:
		c.t += delta / CUT_ANIM_TIME
		var b: Node3D = c.node
		var base_h: float = b.get_meta("base_h")
		if c.t >= 1.0:
			# Pop finished: hide, reset, and queue the regrow.
			b.visible = false
			b.position.y = 0.0
			b.quaternion = Quaternion.IDENTITY
			b.scale = Vector3(1.0, base_h, 1.0)
			b.set_meta("busy", false)
			_regrow_queue.append({"node": b, "at": _clock + REGROW_DELAY})
		else:
			var k: float = c.t
			var fade := 1.0 - k
			b.scale = Vector3(fade, base_h * fade, fade)   # shrink away
			b.position.y = sin(k * PI) * 0.5               # little hop
			b.quaternion = Quaternion(c.axis, k * TAU)     # one cute tumble
			still.append(c)
	_cutting = still


func _update_regrow() -> void:
	if _regrow_queue.is_empty():
		return
	var still: Array = []
	for item in _regrow_queue:
		if _clock >= item.at:
			var b: Node3D = item.node
			b.set_meta("busy", true)
			b.visible = true
			b.quaternion = Quaternion.IDENTITY
			b.scale = Vector3(1.0, 0.05, 1.0)
			_growing.append({"node": b, "t": 0.0})
		else:
			still.append(item)
	_regrow_queue = still


func _update_growth(delta: float) -> void:
	if _growing.is_empty():
		return
	var still: Array = []
	for g in _growing:
		g.t += delta / GROW_TIME
		var b: Node3D = g.node
		var base_h: float = b.get_meta("base_h")
		if g.t >= 1.0:
			b.scale = Vector3(1.0, base_h, 1.0)
			b.set_meta("busy", false)
		else:
			b.scale = Vector3(1.0, lerpf(0.05, base_h, g.t), 1.0)
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
