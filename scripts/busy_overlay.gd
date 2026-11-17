class_name BusyOverlay
extends Control
## Cartel de progreso ("Generando… 43%") que tapa la interfaz mientras se arma un mapa.
## Mientras está visible consume los clics, así no se puede editar ni abrir otra cosa.

var _label: Label
var _bar: ProgressBar


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = EditorUI.make_theme()
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.105, 0.115, 0.145, 0.97)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(320, 14)
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.19, 0.21, 0.26)
	back.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.72, 0.42)
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)


## Muestra el cartel con un texto y un avance entre 0 y 1.
func show_progress(text: String, fraction: float) -> void:
	var clamped: float = clampf(fraction, 0.0, 1.0)
	_label.text = "%s… %d%%" % [text, floori(clamped * 100.0)]
	_bar.value = clamped
	visible = true


func hide_progress() -> void:
	visible = false


func current_text() -> String:
	return _label.text
