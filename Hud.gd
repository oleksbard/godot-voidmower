extends CanvasLayer
## Minimal heads-up display: a "Mowed: N" counter plus a controls hint.
## Uses Godot's built-in font (no asset needed) with a dark outline so it stays
## readable over the grass.

var _count_label: Label


func _ready() -> void:
	_count_label = _make_label(28, Vector2(18.0, 12.0))
	_count_label.text = "Mowed: 0"
	add_child(_count_label)

	var hint := _make_label(16, Vector2(18.0, 52.0))
	hint.modulate = Color(1, 1, 1, 0.8)
	hint.text = "WASD / Arrows: move    Space: swing scythe"
	add_child(hint)


func set_count(count: int) -> void:
	_count_label.text = "Mowed: %d" % count


func _make_label(font_size: int, pos: Vector2) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	return label
