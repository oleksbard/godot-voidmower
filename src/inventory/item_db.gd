class_name ItemDb
extends RefCounted
## Static registry of the three item types: the scythe (a tool) and the grass +
## flower resources dropped by mowing. Pure data — no state, no scene. Reference
## via `const ItemDb := preload("res://src/inventory/item_db.gd")`.

enum Id { SCYTHE, GRASS, FLOWER }

const _DEFS := {
	Id.SCYTHE: {"name": "Scythe", "icon": "res://assets/icons/scythe.png", "is_tool": true, "max_stack": 1},
	Id.GRASS: {"name": "Grass", "icon": "res://assets/icons/grass.png", "is_tool": false, "max_stack": 999},
	Id.FLOWER: {"name": "Flower", "icon": "res://assets/icons/flower.png", "is_tool": false, "max_stack": 999},
}


static func name_of(id: int) -> String:
	return _DEFS[id]["name"]


static func icon_path(id: int) -> String:
	return _DEFS[id]["icon"]


static func is_tool_item(id: int) -> bool:
	return _DEFS[id]["is_tool"]


static func max_stack(id: int) -> int:
	return _DEFS[id]["max_stack"]
