class_name AvatarSelector
extends Control
## Pantalla de selección de avatar: una tarjeta por avatar con vista previa 3D giratoria.
## Clic sobre una tarjeta, o flechas + Enter, para elegir. Esc cancela.

signal chosen(index: int)
signal cancelled

const COLUMNS: int = 6
const CARD_SIZE: Vector2i = Vector2i(158, 176)
const COL_CARD: Color = Color(0.16, 0.18, 0.23)
const COL_SELECTED: Color = Color(0.22, 0.47, 0.80)

var library: CharacterLibrary

var _cards: Array[PanelContainer] = []
var _rigs: Array[CharacterRig] = []
var _selected: int = 0


func setup(p_library: CharacterLibrary) -> void:
	library = p_library


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = EditorUI.make_theme()
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.105, 0.115, 0.145)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Elige tu avatar"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.62, 0.86, 0.55))
	column.add_child(title)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	for i: int in CharacterLibrary.AVATAR_COUNT:
		grid.add_child(_make_card(i))

	var hint := Label.new()
	hint.text = "Clic o flechas + Enter para elegir · Esc para volver al editor"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", EditorUI.COL_DIM)
	column.add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(cancel)
	var play := Button.new()
	play.text = "Jugar"
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(func() -> void: chosen.emit(_selected))
	buttons.add_child(play)
	_refresh_selection()


func _make_card(index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_input.bind(index))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(CARD_SIZE)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = CARD_SIZE
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.handle_input_locally = false
	container.add_child(viewport)

	# Cada vista previa tiene su propio mundo: cámara, luz y fondo.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.24, 0.31)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.85, 0.95)
	env.ambient_light_energy = 0.75
	var cam := Camera3D.new()
	cam.environment = env
	cam.fov = 38.0
	var cam_pos := Vector3(0.0, 1.55, 4.6)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, 1.12, 0.0) - cam_pos, Vector3.UP), cam_pos)
	viewport.add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	light.light_energy = 1.1
	viewport.add_child(light)
	var rig := CharacterRig.new()
	viewport.add_child(rig)
	rig.setup(library.get_avatar_parts(index))
	rig.rotation.y = 0.5
	_rigs.append(rig)

	var label := Label.new()
	label.text = CharacterLibrary.AVATAR_NAMES[index]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	box.add_child(label)
	_cards.append(card)
	return card


## Muestra el selector con `preselect` marcado.
func open(preselect: int) -> void:
	_selected = clampi(preselect, 0, CharacterLibrary.AVATAR_COUNT - 1)
	for rig: CharacterRig in _rigs:
		rig.rotation.y = 0.5
	_refresh_selection()
	visible = true


func close() -> void:
	visible = false


func selected() -> int:
	return _selected


func _select(index: int) -> void:
	_selected = index
	_refresh_selection()


func _refresh_selection() -> void:
	for i: int in _cards.size():
		var style := StyleBoxFlat.new()
		style.bg_color = COL_CARD
		style.set_corner_radius_all(6)
		style.set_content_margin_all(6)
		style.set_border_width_all(3)
		style.border_color = COL_SELECTED if i == _selected else COL_CARD
		_cards[i].add_theme_stylebox_override("panel", style)


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_select(index)
			chosen.emit(index)


func _process(delta: float) -> void:
	if not visible:
		return
	# El avatar elegido gira y camina en el lugar; los demás giran despacio.
	for i: int in _rigs.size():
		if i == _selected:
			_rigs[i].rotation.y += delta * 1.4
			_rigs[i].animate(delta, 2.5)
		else:
			_rigs[i].rotation.y += delta * 0.35
			_rigs[i].animate(delta, 0.0)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed:
		return
	var count: int = CharacterLibrary.AVATAR_COUNT
	match key.keycode:
		KEY_LEFT, KEY_A:
			_select(posmod(_selected - 1, count))
		KEY_RIGHT, KEY_D:
			_select(posmod(_selected + 1, count))
		KEY_UP, KEY_W:
			_select(posmod(_selected - COLUMNS, count))
		KEY_DOWN, KEY_S:
			_select(posmod(_selected + COLUMNS, count))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not key.echo:
				chosen.emit(_selected)
		KEY_ESCAPE:
			cancelled.emit()
		_:
			return
	get_viewport().set_input_as_handled()
