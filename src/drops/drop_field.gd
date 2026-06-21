class_name DropField
extends Node3D
## The transient "loot flies to you" pickups. When a mowed tile rolls a drop,
## Main calls spawn(): a small PROCEDURAL token appears at the cut spot, arcs up
## and into the player, then emits collected() and frees itself. Mirrors the
## GrassField/FlowerField pattern (a player ref set by Main; self-freeing nodes).
## The 2D item icons are NOT used here — the 3D world stays procedural.

const ItemDb := preload("res://src/inventory/item_db.gd")

signal collected(item_id: int)

const FLY_TIME := 0.45        # seconds from spawn to the player
const POP_HEIGHT := 0.9       # arc apex above the straight-line path
const SPIN_TURNS := 1.5       # tumbles during the flight
const TARGET_Y := 1.0         # aim at the player's chest, not their feet

var player: Node3D            # set by Main before this node is added

var _flying: Array = []       # [{node, t, from, id}]


func spawn(item_id: int, world_pos: Vector3) -> void:
	var token := _make_token(item_id)
	token.position = world_pos
	add_child(token)
	_flying.append({"node": token, "t": 0.0, "from": world_pos, "id": item_id})


func _process(delta: float) -> void:
	if _flying.is_empty():
		return
	var target := (player.global_position + Vector3(0.0, TARGET_Y, 0.0)) if player != null else Vector3.ZERO
	var still: Array = []
	for f in _flying:
		f.t += delta / FLY_TIME
		var node: Node3D = f.node
		if f.t >= 1.0:
			collected.emit(f.id)
			node.queue_free()
			continue
		var k: float = f.t
		var pos: Vector3 = f.from.lerp(target, k)
		pos.y += sin(k * PI) * POP_HEIGHT             # arc up then down into the player
		node.position = pos
		node.rotation.y = k * TAU * SPIN_TURNS
		node.scale = Vector3.ONE * lerpf(1.0, 0.2, k)  # shrink as it lands
		still.append(f)
	_flying = still


## A small emissive procedural token: a green tuft for grass, a tiny bloom for a
## flower — recognisable at a glance, no image assets.
func _make_token(item_id: int) -> Node3D:
	var root := Node3D.new()
	if item_id == ItemDb.Id.FLOWER:
		var center := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.18, 0.18, 0.18)
		center.mesh = cm
		center.material_override = _mat(Color(0.96, 0.80, 0.24))
		root.add_child(center)
		for off in [Vector3(0.16, 0, 0), Vector3(-0.16, 0, 0), Vector3(0, 0, 0.16), Vector3(0, 0, -0.16)]:
			var petal := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.16, 0.08, 0.16)
			petal.mesh = pm
			petal.material_override = _mat(Color(0.95, 0.52, 0.72))
			petal.position = off
			root.add_child(petal)
	else:
		for i in 3:
			var blade := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.08, 0.34, 0.08)
			blade.mesh = bm
			blade.material_override = _mat(Color(0.36, 0.72, 0.28))
			blade.position = Vector3((i - 1) * 0.09, 0.17, 0.0)
			blade.rotation.z = (i - 1) * 0.25
			root.add_child(blade)
	return root


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.8
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.5
	return m
