class_name Hud
extends CanvasLayer
## Minimal heads-up display: the current day + time of day.
## Uses Godot's built-in font (no asset needed) with a dark outline so it stays
## readable over the grass.

var _time_label: Label


func _ready() -> void:
	_time_label = _make_label(28, Vector2(18.0, 12.0))
	_time_label.text = "Day 1   06:00"
	add_child(_time_label)


func set_time(day: int, hour: float) -> void:
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	_time_label.text = "Day %d   %02d:%02d" % [day, h, m]


func _make_label(font_size: int, pos: Vector2) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	return label
