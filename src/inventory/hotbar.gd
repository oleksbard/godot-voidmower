class_name Hotbar
extends CanvasLayer
## The bottom-of-screen hotbar: 10 slots selected with keys 1-9 and 0. Owns the
## Inventory data model, renders it Stardew-style (a chunky framed strip, stack
## counts, a warm gold frame on the active slot that lifts slightly), and
## announces the active tool so the player can show/hide + gate the scythe.
##
## Each slot shows its item as a small procedural low-poly 3D model rendered in
## its own SubViewport (see ItemModel); the active slot's model spins about its
## own axis. NOTHING image-based is loaded here — the 3D models keep the whole
## "procedural geometry, zero image assets" rule intact, even in the UI.

const Inventory := preload("res://src/inventory/inventory.gd")
const ItemDb := preload("res://src/inventory/item_db.gd")
const ItemModel := preload("res://src/inventory/item_model.gd")

signal active_tool_changed(item_id: int)   # an ItemDb.Id, or Inventory.EMPTY for a blank slot

const SLOT_PX := 64
const ICON_PX := 56
const SLOT_PAD := 6
const BOTTOM_MARGIN := 18
const ACTIVE_RAISE := 8                     # the active slot lifts this many px

const VIEW_PX := 128                         # SubViewport render size (downscaled into ICON_PX)
const SPIN_SPEED := 1.3                      # active-model spin (rad/s)

const BG_COL := Color(0.10, 0.09, 0.08, 0.78)
const ACTIVE_COL := Color(1.0, 0.80, 0.35)  # warm gold
const IDLE_BORDER := Color(0.0, 0.0, 0.0, 0.5)
const NUM_COL := Color(0.85, 0.85, 0.82)

var _inv: Inventory
var _root: Control
var _viewport_holder: Node                  # parents the SubViewports (off-screen render targets)
var _panels: Array[Panel] = []
var _views: Array[SubViewport] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _models: Array[Node3D] = []             # current model per slot (null when empty)
var _slot_ids: Array[int] = []              # last-rendered item id per slot (to detect changes)


func _ready() -> void:
	_inv = Inventory.new()
	_inv.set_slot(0, ItemDb.Id.SCYTHE, 1)   # scythe in slot 1, active by default

	_viewport_holder = Node.new()
	add_child(_viewport_holder)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	for i in Inventory.SLOT_COUNT:
		_build_slot(i)

	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()
	active_tool_changed.emit(_inv.active_item())


func _process(delta: float) -> void:
	var model := _models[_inv.active_index()]
	if model != null:
		model.rotate_y(SPIN_SPEED * delta)   # only the active slot keeps re-rendering


func _build_slot(index: int) -> void:
	var panel := Panel.new()
	panel.size = Vector2(SLOT_PX, SLOT_PX)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _slot_style(false))
	_root.add_child(panel)

	var view := _build_view()
	_viewport_holder.add_child(view)

	var icon := TextureRect.new()           # samples its slot's SubViewport
	icon.texture = view.get_texture()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2((SLOT_PX - ICON_PX) * 0.5, (SLOT_PX - ICON_PX) * 0.5)
	icon.size = Vector2(ICON_PX, ICON_PX)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)

	var num := Label.new()                  # slot number 1..9,0 in the top-left
	num.text = str((index + 1) % 10)
	num.position = Vector2(4, 0)
	num.add_theme_font_size_override("font_size", 13)
	num.add_theme_color_override("font_color", NUM_COL)
	num.add_theme_color_override("font_outline_color", Color.BLACK)
	num.add_theme_constant_override("outline_size", 4)
	panel.add_child(num)

	var count := Label.new()                # stack count in the bottom-right (>1 only)
	count.add_theme_font_size_override("font_size", 15)
	count.add_theme_color_override("font_color", Color.WHITE)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 4)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.position = Vector2(SLOT_PX - 30, SLOT_PX - 24)
	count.size = Vector2(26, 20)
	panel.add_child(count)

	_panels.append(panel)
	_views.append(view)
	_icons.append(icon)
	_counts.append(count)
	_models.append(null)
	_slot_ids.append(Inventory.EMPTY)


## A self-contained mini-scene: own 3D world, transparent background, an
## orthographic 3/4 camera and a warm key + cool fill light (no environment, so
## the lights carry the golden-hour look). Idle slots render once and freeze.
func _build_view() -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(VIEW_PX, VIEW_PX)
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.55
	cam.transform = Transform3D(Basis(), Vector3(1.1, 0.95, 1.9)).looking_at(Vector3.ZERO, Vector3.UP)
	view.add_child(cam)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.82)
	key.light_energy = 1.7
	key.rotation_degrees = Vector3(-48.0, -40.0, 0.0)
	view.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.70, 0.88)
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(-15.0, 145.0, 0.0)
	view.add_child(fill)
	return view


func _slot_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COL
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(3 if active else 2)
	sb.border_color = ACTIVE_COL if active else IDLE_BORDER
	return sb


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var total := Inventory.SLOT_COUNT * SLOT_PX + (Inventory.SLOT_COUNT - 1) * SLOT_PAD
	var x0 := (vp.x - total) * 0.5
	var y := vp.y - SLOT_PX - BOTTOM_MARGIN
	for i in _panels.size():
		var raised := -ACTIVE_RAISE if i == _inv.active_index() else 0
		_panels[i].position = Vector2(x0 + i * (SLOT_PX + SLOT_PAD), y + raised)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var index := _key_to_slot(event.keycode)
	if index >= 0:
		_select(index)


## KEY_1..KEY_9 -> slots 0..8, KEY_0 -> slot 9, anything else -> -1.
func _key_to_slot(keycode: int) -> int:
	if keycode == KEY_0:
		return 9
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	return -1


func _select(index: int) -> void:
	_inv.set_active(index)
	_layout()
	_refresh()
	active_tool_changed.emit(_inv.active_item())


## Add items dropped by mowing (Main binds the count to 1 per collected token).
func add_item(item_id: int, n: int) -> void:
	_inv.add(item_id, n)
	_refresh()


func _refresh() -> void:
	var active := _inv.active_index()
	for i in _panels.size():
		var id := _inv.slot_id(i)
		var c := _inv.slot_count(i)
		_panels[i].add_theme_stylebox_override("panel", _slot_style(i == active))
		if id != _slot_ids[i]:
			_set_model(i, id)
		if i == active:
			_views[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS
		else:
			if _models[i] != null:
				_models[i].rotation = Vector3.ZERO          # idle slots sit upright...
			_views[i].render_target_update_mode = SubViewport.UPDATE_ONCE   # ...rendered once, then frozen
		_counts[i].text = str(c) if c > 1 else ""


## Swap the model in slot `i`'s viewport to match item `id` (or clear it).
func _set_model(index: int, id: int) -> void:
	if _models[index] != null:
		_models[index].queue_free()
		_models[index] = null
	if id != Inventory.EMPTY:
		var model := ItemModel.build(id)
		if model != null:
			_views[index].add_child(model)
			_models[index] = model
	_slot_ids[index] = id
