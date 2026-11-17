class_name EditorUI
extends Control
## Interfaz del editor, construida por código: barra superior, panel lateral y línea de estado.

signal tool_selected(tool: int)
signal block_selected(id: int)
signal prop_selected(id: int)
signal entity_selected(type: int)
signal play_requested
signal object_editor_requested
## Se aceptó el editor de diálogo de un aldeano.
signal npc_edited(cell: Vector3i, npc_name: String, lines: Array)
signal brush_changed(brush_size: int)
signal new_requested
signal undo_requested
signal redo_requested
signal save_path_chosen(path: String)
signal load_path_chosen(path: String)
## Se emite cuando se abre o se cierra un diálogo (para pausar la edición).
signal modal_changed(open: bool)

const TOP_HEIGHT: int = 44
const STATUS_HEIGHT: int = 30
const SIDE_WIDTH: int = 272
const TOOL_HINT_SECONDS: float = 12.0
const HINT: String = "Clic izq.: aplicar · Central: orbitar · Der. / Shift+central: desplazar · " \
		+ "Rueda: zoom · WASD: mover · Q/E: girar · R: rotar · Ctrl+Z / Ctrl+Y · F5: jugar"

const COL_PANEL: Color = Color(0.105, 0.115, 0.145, 0.96)
const COL_BUTTON: Color = Color(0.19, 0.21, 0.26)
const COL_HOVER: Color = Color(0.26, 0.29, 0.36)
const COL_ACTIVE: Color = Color(0.22, 0.47, 0.80)
const COL_TEXT: Color = Color(0.88, 0.90, 0.94)
const COL_DIM: Color = Color(0.58, 0.62, 0.70)
const COL_ERROR: Color = Color(1.0, 0.45, 0.40)
const COL_OK: Color = Color(0.55, 0.90, 0.60)

## Biblioteca de props que muestra la paleta. Se asigna antes de agregar el nodo al árbol.
var library: PropLibrary

var _prop_grid: GridContainer
var _tool_buttons: Array[Button] = []
var _block_buttons: Dictionary[int, Button] = {}
var _prop_buttons: Array[Button] = []
var _entity_buttons: Array[Button] = []
var _npc_dialog: ConfirmationDialog
var _npc_name_edit: LineEdit
var _npc_lines_edit: TextEdit
var _npc_cell: Vector3i = Vector3i.ZERO
var _brush_buttons: Array[Button] = []
var _undo_button: Button
var _redo_button: Button
var _seed_label: Label
var _message_label: Label
var _status_label: Label
var _save_dialog: FileDialog
var _load_dialog: FileDialog
var _error_dialog: AcceptDialog
var _message_timer: Timer
var _hint_label: Label
var _unsaved_label: Label
var _hint_timer: Timer
var _open_modals: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = make_theme()
	_build_top_bar()
	_build_side_panel()
	_build_status_bar()
	_build_dialogs()
	_message_timer = Timer.new()
	_message_timer.one_shot = true
	_message_timer.timeout.connect(_on_message_timeout)
	add_child(_message_timer)
	_hint_timer = Timer.new()
	_hint_timer.one_shot = true
	_hint_timer.timeout.connect(_on_hint_timeout)
	add_child(_hint_timer)


# ================================================================ API pública

## Los botones forman grupos: activar uno desactiva el resto. Solo se conecta la señal
## `pressed` (clic del usuario), así que estos cambios por código no generan eventos.
func set_tool(tool: int) -> void:
	if tool >= 0 and tool < _tool_buttons.size():
		_tool_buttons[tool].button_pressed = true


func set_block(id: int) -> void:
	if _block_buttons.has(id):
		_block_buttons[id].button_pressed = true


func set_prop(id: int) -> void:
	if id >= 0 and id < _prop_buttons.size():
		_prop_buttons[id].button_pressed = true


## Vuelve a armar la paleta de props con el contenido actual de la biblioteca (los objetos
## se pueden editar y agregar desde el editor de objetos) y deja marcado `selected`.
func refresh_props(selected: int) -> void:
	if _prop_grid == null or library == null:
		return
	for button: Button in _prop_buttons:
		_prop_grid.remove_child(button)
		button.queue_free()
	_prop_buttons.clear()
	var prop_group := ButtonGroup.new()
	for id: int in library.count():
		var button: Button = _make_toggle(library.prop_name(id), prop_group)
		button.icon = _swatch(library.swatch(id))
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func() -> void: prop_selected.emit(id))
		_prop_grid.add_child(button)
		_prop_buttons.append(button)
	_prop_buttons[clampi(selected, 0, _prop_buttons.size() - 1)].set_pressed_no_signal(true)


func set_entity(type: int) -> void:
	if type >= 0 and type < _entity_buttons.size():
		_entity_buttons[type].button_pressed = true


func set_brush(brush_size: int) -> void:
	if brush_size >= 1 and brush_size <= _brush_buttons.size():
		_brush_buttons[brush_size - 1].button_pressed = true


## Muestra en la línea de estado qué hace la herramienta elegida; después de unos segundos
## vuelve la línea de controles.
func show_tool_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.add_theme_color_override("font_color", COL_TEXT)
	_hint_timer.start(TOOL_HINT_SECONDS)


func _on_hint_timeout() -> void:
	_hint_label.text = HINT
	_hint_label.add_theme_color_override("font_color", COL_DIM)


func hint_text() -> String:
	return _hint_label.text


func set_status(text: String) -> void:
	_status_label.text = text


func set_seed(map_seed: int) -> void:
	_seed_label.text = "Semilla: %d" % map_seed


## Marca en la barra superior que hay cambios sin guardar (ediciones o progreso del juego).
func set_unsaved(unsaved: bool) -> void:
	if _unsaved_label == null:
		_unsaved_label = Label.new()
		_unsaved_label.text = "● Sin guardar"
		_unsaved_label.tooltip_text = "Hay cambios o progreso del juego que todavía no se guardaron"
		_unsaved_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_unsaved_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30))
		var row: Node = _seed_label.get_parent()
		row.add_child(_unsaved_label)
		row.move_child(_unsaved_label, _seed_label.get_index() + 1)
	_unsaved_label.visible = unsaved


func is_unsaved_shown() -> bool:
	return _unsaved_label != null and _unsaved_label.visible


func set_history(can_undo: bool, can_redo: bool) -> void:
	_undo_button.disabled = not can_undo
	_redo_button.disabled = not can_redo


## Muestra un aviso breve en la barra superior.
func show_message(text: String, is_error: bool = false) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", COL_ERROR if is_error else COL_OK)
	_message_timer.start(8.0)


## Muestra un error en la barra superior y en una ventana emergente.
func show_error(text: String) -> void:
	show_message(text, true)
	_error_dialog.dialog_text = text
	_error_dialog.popup_centered()


## Abre el editor de nombre y diálogo de un aldeano.
func open_npc_editor(cell: Vector3i, npc_name: String, lines: Array) -> void:
	_npc_cell = cell
	_npc_name_edit.text = npc_name
	var text_lines: PackedStringArray = PackedStringArray()
	for line: Variant in lines:
		text_lines.append(str(line))
	_npc_lines_edit.text = "\n".join(text_lines)
	_npc_dialog.popup_centered(Vector2i(520, 380))
	_npc_name_edit.grab_focus()


func open_save_dialog() -> void:
	MapIO.ensure_maps_dir()
	_save_dialog.current_dir = MapIO.MAPS_DIR
	_save_dialog.popup_centered(Vector2i(760, 480))


func open_load_dialog() -> void:
	MapIO.ensure_maps_dir()
	_load_dialog.current_dir = MapIO.MAPS_DIR
	_load_dialog.popup_centered(Vector2i(760, 480))


# ================================================================ construcción

## Tema oscuro compartido por el editor, el selector de avatar y el modo juego.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13
	t.set_stylebox("panel", "PanelContainer", _flat(COL_PANEL, 0, 8, 6))
	t.set_stylebox("normal", "Button", _flat(COL_BUTTON, 4, 7, 3))
	t.set_stylebox("hover", "Button", _flat(COL_HOVER, 4, 7, 3))
	t.set_stylebox("pressed", "Button", _flat(COL_ACTIVE, 4, 7, 3))
	t.set_stylebox("hover_pressed", "Button", _flat(COL_ACTIVE.lightened(0.12), 4, 7, 3))
	t.set_stylebox("disabled", "Button", _flat(Color(0.15, 0.16, 0.19), 4, 7, 3))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.42, 0.45, 0.50))
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_constant("h_separation", "Button", 6)
	return t


static func _flat(color: Color, radius: int, margin_h: int, margin_v: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	return box


static func _swatch(color: Color) -> ImageTexture:
	var image := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.55))
	image.fill_rect(Rect2i(1, 1, 12, 12), Color(color.r, color.g, color.b, 1.0))
	return ImageTexture.create_from_image(image)


func _make_button(text: String, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	# Sin foco de teclado: las teclas quedan para los atajos del editor.
	button.focus_mode = Control.FOCUS_NONE
	return button


func _make_toggle(text: String, group: ButtonGroup, tooltip: String = "") -> Button:
	var button: Button = _make_button(text, tooltip)
	button.toggle_mode = true
	button.button_group = group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	return button


func _section(parent: Control, title: String) -> void:
	var label := Label.new()
	label.text = title.to_upper()
	label.add_theme_color_override("font_color", COL_DIM)
	label.add_theme_font_size_override("font_size", 11)
	parent.add_child(label)


func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = TOP_HEIGHT
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var title := Label.new()
	title.text = "Editor Voxel"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.62, 0.86, 0.55))
	row.add_child(title)
	row.add_child(_spacer(10))

	var new_button: Button = _make_button("Nuevo", "Genera una pradera nueva con una semilla al azar")
	new_button.pressed.connect(func() -> void: new_requested.emit())
	row.add_child(new_button)
	var save_button: Button = _make_button("Guardar", "Guarda el mapa en user://maps")
	save_button.pressed.connect(open_save_dialog)
	row.add_child(save_button)
	var load_button: Button = _make_button("Cargar", "Carga un mapa guardado")
	load_button.pressed.connect(open_load_dialog)
	row.add_child(load_button)
	row.add_child(_spacer(10))

	_undo_button = _make_button("Deshacer", "Ctrl+Z")
	_undo_button.disabled = true
	_undo_button.pressed.connect(func() -> void: undo_requested.emit())
	row.add_child(_undo_button)
	_redo_button = _make_button("Rehacer", "Ctrl+Y o Ctrl+Shift+Z")
	_redo_button.disabled = true
	_redo_button.pressed.connect(func() -> void: redo_requested.emit())
	row.add_child(_redo_button)
	row.add_child(_spacer(10))

	var play_button: Button = _make_button("Jugar", "Recorre el mapa con un avatar (F5)")
	play_button.add_theme_stylebox_override("normal", _flat(Color(0.20, 0.50, 0.28), 4, 10, 3))
	play_button.add_theme_stylebox_override("hover", _flat(Color(0.26, 0.62, 0.35), 4, 10, 3))
	play_button.add_theme_stylebox_override("pressed", _flat(Color(0.18, 0.44, 0.25), 4, 10, 3))
	play_button.pressed.connect(func() -> void: play_requested.emit())
	row.add_child(play_button)
	row.add_child(_spacer(10))

	_seed_label = Label.new()
	_seed_label.text = "Semilla: —"
	_seed_label.add_theme_color_override("font_color", COL_DIM)
	row.add_child(_seed_label)

	_message_label = Label.new()
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_message_label.clip_text = true
	row.add_child(_message_label)

	# Al final de la barra: no corre el resto de los botones.
	var objects_button: Button = _make_button("Editor de objetos",
			"Edita los modelos de los props (árboles, flores, rocas…) o crea objetos nuevos")
	objects_button.pressed.connect(func() -> void: object_editor_requested.emit())
	row.add_child(objects_button)


static func _spacer(width: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(width, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0
	panel.offset_top = TOP_HEIGHT
	panel.offset_right = SIDE_WIDTH
	panel.offset_bottom = -STATUS_HEIGHT
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3)
	scroll.add_child(column)

	# Herramientas (dos columnas).
	_section(column, "Herramientas")
	var tool_grid := GridContainer.new()
	tool_grid.columns = 2
	tool_grid.add_theme_constant_override("h_separation", 4)
	tool_grid.add_theme_constant_override("v_separation", 4)
	column.add_child(tool_grid)
	var tool_group := ButtonGroup.new()
	for i: int in EditorController.TOOL_NAMES.size():
		var button: Button = _make_toggle("%d  %s" % [i + 1, EditorController.TOOL_NAMES[i]], tool_group,
				"%s (tecla %d)\n%s" % [EditorController.TOOL_NAMES[i], i + 1, EditorController.TOOL_HINTS[i]])
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func() -> void: tool_selected.emit(i))
		tool_grid.add_child(button)
		_tool_buttons.append(button)
	_tool_buttons[0].set_pressed_no_signal(true)

	# Tamaño de pincel.
	column.add_child(_spacer(2))
	_section(column, "Pincel (bloques)")
	var brush_row := HBoxContainer.new()
	brush_row.add_theme_constant_override("separation", 4)
	column.add_child(brush_row)
	var brush_group := ButtonGroup.new()
	for size_value: int in range(1, EditorController.MAX_BRUSH + 1):
		var button: Button = _make_toggle(str(size_value), brush_group,
				"Pincel de %d x %d" % [size_value, size_value])
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.pressed.connect(func() -> void: brush_changed.emit(size_value))
		brush_row.add_child(button)
		_brush_buttons.append(button)
	_brush_buttons[0].set_pressed_no_signal(true)

	# Paleta de bloques.
	column.add_child(_spacer(2))
	_section(column, "Bloques")
	var block_grid := GridContainer.new()
	block_grid.columns = 2
	block_grid.add_theme_constant_override("h_separation", 4)
	block_grid.add_theme_constant_override("v_separation", 4)
	column.add_child(block_grid)
	var block_group := ButtonGroup.new()
	for id: int in range(1, Blocks.COUNT):
		var button: Button = _make_toggle(Blocks.NAMES[id], block_group)
		button.icon = _swatch(Blocks.COLORS[id])
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func() -> void: block_selected.emit(id))
		block_grid.add_child(button)
		_block_buttons[id] = button
	_block_buttons[Blocks.GRASS].set_pressed_no_signal(true)

	# Paleta de props.
	column.add_child(_spacer(2))
	_section(column, "Props")
	_prop_grid = GridContainer.new()
	_prop_grid.columns = 2
	_prop_grid.add_theme_constant_override("h_separation", 4)
	_prop_grid.add_theme_constant_override("v_separation", 4)
	column.add_child(_prop_grid)
	refresh_props(0)

	# Paleta de criaturas.
	column.add_child(_spacer(2))
	_section(column, "Criaturas")
	var entity_grid := GridContainer.new()
	entity_grid.columns = 2
	entity_grid.add_theme_constant_override("h_separation", 4)
	entity_grid.add_theme_constant_override("v_separation", 4)
	column.add_child(entity_grid)
	var entity_group := ButtonGroup.new()
	for type: int in CharacterLibrary.ENTITY_COUNT:
		var tip: String = ""
		if type == CharacterLibrary.VILLAGER:
			tip = "Con \"Colocar criatura\", un clic sobre un aldeano ya colocado edita su nombre y diálogo"
		var button: Button = _make_toggle(CharacterLibrary.ENTITY_NAMES[type], entity_group, tip)
		button.icon = _swatch(CharacterLibrary.ENTITY_SWATCHES[type])
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func() -> void: entity_selected.emit(type))
		entity_grid.add_child(button)
		_entity_buttons.append(button)
	_entity_buttons[0].set_pressed_no_signal(true)


func _build_status_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -STATUS_HEIGHT
	panel.offset_bottom = 0
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	_status_label = Label.new()
	_status_label.text = "Celda: —"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.custom_minimum_size = Vector2(380, 0)
	row.add_child(_status_label)
	var hint := Label.new()
	_hint_label = hint
	hint.text = HINT
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.clip_text = true
	row.add_child(hint)


func _build_dialogs() -> void:
	_save_dialog = _make_file_dialog("Guardar mapa", FileDialog.FILE_MODE_SAVE_FILE)
	_save_dialog.file_selected.connect(_on_save_selected)
	_load_dialog = _make_file_dialog("Cargar mapa", FileDialog.FILE_MODE_OPEN_FILE)
	_load_dialog.file_selected.connect(func(path: String) -> void: load_path_chosen.emit(path))
	_build_npc_dialog()
	_error_dialog = AcceptDialog.new()
	_error_dialog.title = "Error"
	_error_dialog.ok_button_text = "Aceptar"
	_error_dialog.visibility_changed.connect(_on_modal_visibility.bind(_error_dialog))
	add_child(_error_dialog)


func _build_npc_dialog() -> void:
	_npc_dialog = ConfirmationDialog.new()
	_npc_dialog.title = "Editar aldeano"
	_npc_dialog.ok_button_text = "Guardar"
	_npc_dialog.cancel_button_text = "Cancelar"
	_npc_dialog.visibility_changed.connect(_on_modal_visibility.bind(_npc_dialog))
	_npc_dialog.confirmed.connect(_on_npc_confirmed)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var name_label := Label.new()
	name_label.text = "Nombre"
	box.add_child(name_label)
	_npc_name_edit = LineEdit.new()
	_npc_name_edit.max_length = 32
	box.add_child(_npc_name_edit)
	var lines_label := Label.new()
	lines_label.text = "Diálogo (una línea por renglón)"
	box.add_child(lines_label)
	_npc_lines_edit = TextEdit.new()
	_npc_lines_edit.custom_minimum_size = Vector2(480, 200)
	_npc_lines_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_npc_lines_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(_npc_lines_edit)
	_npc_dialog.add_child(box)
	add_child(_npc_dialog)


func _on_npc_confirmed() -> void:
	var lines: Array = []
	for line: String in _npc_lines_edit.text.split("\n"):
		var clean: String = line.strip_edges()
		if not clean.is_empty():
			lines.append(clean)
	npc_edited.emit(_npc_cell, _npc_name_edit.text.strip_edges(), lines)


func _make_file_dialog(title: String, mode: FileDialog.FileMode) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.use_native_dialog = false
	dialog.add_filter("*.json", "Mapa del Editor Voxel")
	dialog.ok_button_text = "Guardar" if mode == FileDialog.FILE_MODE_SAVE_FILE else "Abrir"
	dialog.cancel_button_text = "Cancelar"
	dialog.visibility_changed.connect(_on_modal_visibility.bind(dialog))
	add_child(dialog)
	return dialog


func _on_save_selected(path: String) -> void:
	var final_path: String = path
	if final_path.get_extension().to_lower() != "json":
		final_path += ".json"
	save_path_chosen.emit(final_path)


func _on_modal_visibility(window: Window) -> void:
	_open_modals = maxi(_open_modals + (1 if window.visible else -1), 0)
	modal_changed.emit(_open_modals > 0)


func _on_message_timeout() -> void:
	_message_label.text = ""
