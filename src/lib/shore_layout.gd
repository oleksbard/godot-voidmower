class_name ShoreLayout
extends RefCounted
## Where the Captain's visit happens on the island's +X (screen-right) shore.
## There is NO dock — *The Dandelion* beaches at the shore and the Captain walks
## straight onto the grass. Holds the boat landing/board points, the Captain's
## idle stand, the stall spot, the arrival path, and the player's walkable clamp
## (the island disc, minus a no-go circle around the stall+Captain while he is
## visiting so the player can't walk into them). Pure + testable.

const IslandShape := preload("res://src/lib/island_shape.gd")

const EDGE_MARGIN := 0.7                          # keep the player this far inside the coast

const FARAWAY := Vector3(42.0, 0.0, 0.0)          # boat hidden start/end out in the void
const BERTH := Vector3(12.2, 0.0, 0.0)            # boat beached at the +X shore
const BOARD_SPOT := Vector3(11.6, 0.0, 0.0)       # on the grass beside the beached boat
const CAPTAIN_STAND := Vector3(10.4, 0.0, 0.6)    # where the Captain idles by his stall
const STALL_SPOT := Vector3(10.4, 0.0, 2.2)       # the stall structure sits behind him

# A no-go circle (XZ) covering the stall + Captain, active only while he visits.
const BLOCK_CENTER := Vector3(10.4, 0.0, 1.4)
const BLOCK_RADIUS := 1.7


## The walk after stepping off the boat; departure walks to BOARD_SPOT then boards.
static func arrival_path() -> Array[Vector3]:
	var p: Array[Vector3] = [CAPTAIN_STAND]
	return p


## Clamp a world position to the walkable region: the island disc, and — when
## `block` is true (the Captain is present) — pushed out of the stall/Captain
## no-go circle so the player can't walk into them.
static func clamp_walkable(pos: Vector3, block: bool) -> Vector3:
	pos = _clamp_to_island(pos)
	if block:
		pos = _push_out(pos, BLOCK_CENTER, BLOCK_RADIUS)
	return pos


static func _clamp_to_island(pos: Vector3) -> Vector3:
	var h := Vector2(pos.x, pos.z)
	if h.length() < 0.001:
		return pos
	var ang := atan2(pos.z, pos.x)
	var max_r := IslandShape.radius(ang) - EDGE_MARGIN
	if h.length() > max_r:
		h = h.normalized() * max_r
		pos.x = h.x
		pos.z = h.y
	return pos


## Push `pos` out to the rim of the circle (centre+radius) in the XZ plane. The
## circle sits well inside the coast, so a pushed point stays on the island.
## ponytail: simple radial push; a player rushing the rim slides along it, which
## is the right feel for a soft obstacle — no full collision solver needed.
static func _push_out(pos: Vector3, center: Vector3, radius: float) -> Vector3:
	var d := Vector2(pos.x - center.x, pos.z - center.z)
	var dist := d.length()
	if dist >= radius:
		return pos
	if dist < 0.001:
		d = Vector2(1.0, 0.0)
		dist = 1.0
	var out := d / dist * radius
	pos.x = center.x + out.x
	pos.z = center.z + out.y
	return pos
