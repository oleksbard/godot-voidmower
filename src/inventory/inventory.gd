class_name Inventory
extends RefCounted
## The hotbar's data model: SLOT_COUNT slots (each an item id + count) and one
## active slot. Pure logic — no scene, no signals — so it unit-tests directly.
## Stacking respects ItemDb.max_stack. Reference via a preload const.

const ItemDb := preload("res://src/inventory/item_db.gd")

const SLOT_COUNT := 10
const EMPTY := -1   # slot id sentinel: this slot holds no item

var _ids := PackedInt32Array()
var _counts := PackedInt32Array()
var _active := 0


func _init() -> void:
	_ids.resize(SLOT_COUNT)
	_counts.resize(SLOT_COUNT)
	_ids.fill(EMPTY)
	_counts.fill(0)


func active_index() -> int:
	return _active


func set_active(index: int) -> void:
	_active = clampi(index, 0, SLOT_COUNT - 1)


func active_item() -> int:
	return _ids[_active]


func slot_id(index: int) -> int:
	return _ids[index]


func slot_count(index: int) -> int:
	return _counts[index]


## Place `id` x `count` directly into a slot (used to seed the scythe at start).
func set_slot(index: int, id: int, count: int) -> void:
	_ids[index] = id
	_counts[index] = count


## Add `n` of `id`, merging into existing matching stacks (up to max_stack) first,
## then the first empty slots. Returns the leftover that didn't fit (0 in practice).
func add(id: int, n: int) -> int:
	var cap := ItemDb.max_stack(id)
	for i in SLOT_COUNT:
		if n <= 0:
			break
		if _ids[i] == id and _counts[i] < cap:
			var put := mini(cap - _counts[i], n)
			_counts[i] += put
			n -= put
	for i in SLOT_COUNT:
		if n <= 0:
			break
		if _ids[i] == EMPTY:
			var put := mini(cap, n)
			_ids[i] = id
			_counts[i] = put
			n -= put
	return n
