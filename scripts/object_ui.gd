class_name ObjectUI
extends Control
## Interfaz del editor de objetos, construida por código: barra superior (archivo e historial),
## panel lateral (herramientas, color, variantes) y los diálogos de abrir y guardar.
## Las confirmaciones (descartar cambios, reemplazar un objeto) se resuelven aquí; el trabajo
## lo hace ObjectEditor.

signal back_requested
## Se emite cuando se abre o se cierra un diálogo (para pausar la edición).
signal modal_changed(open: bool)

const HINT: String = "Clic izq.: aplicar · Central: orbitar · Der. / Shift+central: desplazar · " \
		+ "Rueda: zoom · 1-4: herramienta · Ctrl+Z / Ctrl+Y · Ctrl+S: guardar"
const COL_TITLE: Color = Color(1.0, 0.80, 0.36)
const MAX_SWATCHES: int = 60

var editor: ObjectEditor
var library: PropLibrary

var _tool_buttons: Array[Button] = []
var _variant_buttons: Array[Button] = []
var _undo_button: Button
var _redo_button: Button
var _restore_button: Button
var _add_variant_button: Button
var _remove_variant_button: Button
var _name_label: Label
var _detail_label: Label
var _info_label: Label
var _message_label: Label
var _status_label: Label
var _color_button: ColorPickerButton
var _color_label: Label
var _swatch_flow: HFlowContainer
var _variant_row: HFlowContainer
var _message_timer: Timer
var _open_modals: int = 0

var _confirm_dialog: ConfirmationDialog
var _confirm_action: Callable
var _error_dialog: AcceptDialog
var _open_dialog: ConfirmationDialog
var _open_list: ItemList
var _open_variant: OptionButton
var _save_dialog: ConfirmationDialog
var _save_name: LineEdit
var _save_key_label: Label


func setup(p_editor: ObjectEditor, p_library: PropLibrary) -> void:
	editor = p_editor
	library = p_library


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = EditorUI.make_theme()
	_build_top_bar()
	_build_side_panel()
	_build_status_bar()
	_build_dialogs()
	_message_timer = Timer.new()
	_message_timer.one_shot = true
	_message_timer.timeout.connect(func() -> void: _message_label.text = "")
	add_child(_message_timer)

	editor.tool_changed.connect(_on_tool_changed)
	editor.color_changed.connect(_on_color_changed)
	editor.history_changed.connect(_on_history_changed)
	editor.status_changed.connect(_on_status_changed)
	editor.document_changed.connect(_refresh_document)
	editor.palette_changed.connect(_refresh_swatches)
	editor.save_requested.connect(_on_save_pressed)
	_on_color_changed(editor.color)
	_refresh_document()


# ================================================================ API pública

## Muestra un aviso breve en la barra superior.
func show_message(text: String, is_error: bool = false) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", EditorUI.COL_ERROR if is_error else EditorUI.COL_OK)
	_message_timer.start(8.0)


## Muestra un error en la barra superior y en una ventana emergente.
func show_error(text: String) -> void:
	show_message(text, true)
	_error_dialog.dialog_text = text
	_error_dialog.popup_centered()


# ================================================================ construcción

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
	return button


func _section(parent: Control, title: String) -> void:
	var label := Label.new()
	label.text = title.to_upper()
	label.add_theme_color_override("font_color", EditorUI.COL_DIM)
	label.add_theme_font_size_override("font_size", 11)
	parent.add_child(label)


static func _spacer(width: int, height: int = 0) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(width, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = EditorUI.TOP_HEIGHT
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var title := Label.new()
	title.text = "Editor de objetos"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COL_TITLE)
	row.add_child(title)
	row.add_child(_spacer(10))

	var new_button: Button = _make_button("Nuevo", "Empieza un objeto vacío")
	new_button.pressed.connect(_on_new_pressed)
	row.add_child(new_button)
	var open_button: Button = _make_button("Abrir", "Abre un objeto de la biblioteca para editarlo")
	open_button.pressed.connect(_on_open_pressed)
	row.add_child(open_button)
	var save_button: Button = _make_button("Guardar", "Guarda sobre el objeto abierto, con todas sus variantes (Ctrl+S)")
	save_button.pressed.connect(_on_save_pressed)
	row.add_child(save_button)
	var save_as_button: Button = _make_button("Guardar como…", "Guarda como un objeto nuevo, con otro nombre")
	save_as_button.pressed.connect(_show_save_dialog)
	row.add_child(save_as_button)
	_restore_button = _make_button("Restaurar original",
			"Descarta la versión modificada de un objeto incorporado y vuelve a su modelo original")
	_restore_button.pressed.connect(_on_restore_pressed)
	row.add_child(_restore_button)
	row.add_child(_spacer(10))

	_undo_button = _make_button("Deshacer", "Ctrl+Z")
	_undo_button.disabled = true
	_undo_button.pressed.connect(func() -> void: editor.undo())
	row.add_child(_undo_button)
	_redo_button = _make_button("Rehacer", "Ctrl+Y o Ctrl+Shift+Z")
	_redo_button.disabled = true
	_redo_button.pressed.connect(func() -> void: editor.redo())
	row.add_child(_redo_button)

	_message_label = Label.new()
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_message_label.clip_text = true
	row.add_child(_message_label)

	var back_button: Button = _make_button("Volver al mapa", "Vuelve al editor de mapas; el mapa queda como estaba")
	back_button.pressed.connect(_on_back_pressed)
	row.add_child(back_button)


func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0
	panel.offset_top = EditorUI.TOP_HEIGHT
	panel.offset_right = EditorUI.SIDE_WIDTH
	panel.offset_bottom = -EditorUI.STATUS_HEIGHT
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	scroll.add_child(column)

	# Objeto abierto.
	_section(column, "Objeto")
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.clip_text = true
	column.add_child(_name_label)
	_detail_label = Label.new()
	_detail_label.add_theme_font_size_override("font_size", 12)
	_detail_label.add_theme_color_override("font_color", EditorUI.COL_DIM)
	_detail_label.clip_text = true
	column.add_child(_detail_label)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", EditorUI.COL_DIM)
	_info_label.clip_text = true
	column.add_child(_info_label)

	# Herramientas.
	column.add_child(_spacer(0, 4))
	_section(column, "Herramientas")
	var tool_group := ButtonGroup.new()
	for i: int in ObjectEditor.TOOL_NAMES.size():
		var button: Button = _make_toggle("%d   %s" % [i + 1, ObjectEditor.TOOL_NAMES[i]], tool_group,
				"Atajo: tecla %d" % (i + 1))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: editor.set_tool(i))
		column.add_child(button)
		_tool_buttons.append(button)
	_tool_buttons[editor.tool].set_pressed_no_signal(true)

	# Color actual.
	column.add_child(_spacer(0, 4))
	_section(column, "Color")
	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 8)
	column.add_child(color_row)
	_color_button = ColorPickerButton.new()
	_color_button.custom_minimum_size = Vector2(120, 30)
	_color_button.edit_alpha = false
	_color_button.focus_mode = Control.FOCUS_NONE
	_color_button.tooltip_text = "Color para colocar y pintar"
	_color_button.color_changed.connect(func(picked: Color) -> void: editor.set_color(picked))
	_color_button.get_popup().visibility_changed.connect(_on_modal_visibility.bind(_color_button.get_popup()))
	color_row.add_child(_color_button)
	_color_label = Label.new()
	_color_label.add_theme_color_override("font_color", EditorUI.COL_DIM)
	color_row.add_child(_color_label)

	# Colores que ya usa el modelo.
	column.add_child(_spacer(0, 4))
	_section(column, "Colores del modelo")
	_swatch_flow = HFlowContainer.new()
	_swatch_flow.add_theme_constant_override("h_separation", 4)
	_swatch_flow.add_theme_constant_override("v_separation", 4)
	column.add_child(_swatch_flow)

	# Variantes.
	column.add_child(_spacer(0, 4))
	_section(column, "Variantes")
	_variant_row = HFlowContainer.new()
	_variant_row.add_theme_constant_override("h_separation", 4)
	_variant_row.add_theme_constant_override("v_separation", 4)
	column.add_child(_variant_row)
	var variant_actions := HBoxContainer.new()
	variant_actions.add_theme_constant_override("separation", 4)
	column.add_child(variant_actions)
	_add_variant_button = _make_button("+ Duplicar", "Agrega una variante que es copia de la actual")
	_add_variant_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_variant_button.pressed.connect(func() -> void: editor.add_variant())
	variant_actions.add_child(_add_variant_button)
	_remove_variant_button = _make_button("− Quitar", "Quita la variante actual")
	_remove_variant_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_remove_variant_button.pressed.connect(_on_remove_variant_pressed)
	variant_actions.add_child(_remove_variant_button)

	column.add_child(_spacer(0, 6))
	var note := Label.new()
	note.text = "El marco amarillo es la celda del mapa (8 × 8 voxeles). Al colocar el objeto, " \
			+ "cada variante se elige al azar."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", EditorUI.COL_DIM)
	column.add_child(note)


func _build_status_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -EditorUI.STATUS_HEIGHT
	panel.offset_bottom = 0
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	_status_label = Label.new()
	_status_label.text = "Voxel: —"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.custom_minimum_size = Vector2(430, 0)
	row.add_child(_status_label)
	var hint := Label.new()
	hint.text = HINT
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", EditorUI.COL_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.clip_text = true
	row.add_child(hint)


func _build_dialogs() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Confirmar"
	_confirm_dialog.cancel_button_text = "Cancelar"
	_confirm_dialog.dialog_autowrap = true
	_confirm_dialog.confirmed.connect(_on_confirmed)
	_register_dialog(_confirm_dialog)

	_error_dialog = AcceptDialog.new()
	_error_dialog.title = "Error"
	_error_dialog.ok_button_text = "Aceptar"
	_register_dialog(_error_dialog)

	# Abrir: lista de objetos y variante.
	_open_dialog = ConfirmationDialog.new()
	_open_dialog.title = "Abrir objeto"
	_open_dialog.ok_button_text = "Abrir"
	_open_dialog.cancel_button_text = "Cancelar"
	_open_dialog.confirmed.connect(_on_open_confirmed)
	var open_box := VBoxContainer.new()
	open_box.add_theme_constant_override("separation", 8)
	_open_list = ItemList.new()
	_open_list.custom_minimum_size = Vector2(400, 300)
	_open_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_open_list.item_selected.connect(_on_open_item_selected)
	_open_list.item_activated.connect(_on_open_item_activated)
	open_box.add_child(_open_list)
	var variant_row := HBoxContainer.new()
	variant_row.add_theme_constant_override("separation", 8)
	var variant_label := Label.new()
	variant_label.text = "Variante"
	variant_row.add_child(variant_label)
	_open_variant = OptionButton.new()
	_open_variant.custom_minimum_size = Vector2(120, 0)
	variant_row.add_child(_open_variant)
	open_box.add_child(variant_row)
	_open_dialog.add_child(open_box)
	_register_dialog(_open_dialog)

	# Guardar como: nombre visible y clave derivada.
	_save_dialog = ConfirmationDialog.new()
	_save_dialog.title = "Guardar como…"
	_save_dialog.ok_button_text = "Guardar"
	_save_dialog.cancel_button_text = "Cancelar"
	_save_dialog.confirmed.connect(_on_save_as_confirmed)
	var save_box := VBoxContainer.new()
	save_box.add_theme_constant_override("separation", 6)
	var name_label := Label.new()
	name_label.text = "Nombre del objeto"
	save_box.add_child(name_label)
	_save_name = LineEdit.new()
	_save_name.max_length = PropIO.MAX_NAME_LENGTH
	_save_name.custom_minimum_size = Vector2(380, 0)
	_save_name.text_changed.connect(_on_save_name_changed)
	save_box.add_child(_save_name)
	_save_key_label = Label.new()
	_save_key_label.add_theme_font_size_override("font_size", 12)
	_save_key_label.add_theme_color_override("font_color", EditorUI.COL_DIM)
	_save_key_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_key_label.custom_minimum_size = Vector2(380, 36)
	save_box.add_child(_save_key_label)
	_save_dialog.add_child(save_box)
	_save_dialog.register_text_enter(_save_name)
	_register_dialog(_save_dialog)


func _register_dialog(dialog: Window) -> void:
	dialog.visibility_changed.connect(_on_modal_visibility.bind(dialog))
	add_child(dialog)


func _on_modal_visibility(window: Window) -> void:
	_open_modals = maxi(_open_modals + (1 if window.visible else -1), 0)
	modal_changed.emit(_open_modals > 0)


# ================================================================ reflejo del editor

func _on_tool_changed(tool: int) -> void:
	if tool >= 0 and tool < _tool_buttons.size():
		_tool_buttons[tool].button_pressed = true


func _on_color_changed(color: Color) -> void:
	_color_button.color = color
	_color_label.text = "#%s" % color.to_html(false)


func _on_history_changed(can_undo: bool, can_redo: bool) -> void:
	_undo_button.disabled = not can_undo
	_redo_button.disabled = not can_redo


func _on_status_changed(text: String) -> void:
	_status_label.text = text
	_info_label.text = editor.info_text()


func _refresh_document() -> void:
	_name_label.text = editor.object_name + ("  • sin guardar" if editor.modified else "")
	_name_label.tooltip_text = _name_label.text
	var id: int = editor.object_id()
	var detail: String
	if id < 0:
		detail = "nuevo, sin guardar"
	elif not library.is_builtin(id):
		detail = "clave: %s · propio" % editor.object_key
	elif library.is_overridden(id):
		detail = "clave: %s · incorporado, modificado" % editor.object_key
	else:
		detail = "clave: %s · incorporado" % editor.object_key
	_detail_label.text = detail
	_detail_label.tooltip_text = detail
	_restore_button.visible = editor.can_restore()

	for button: Button in _variant_buttons:
		_variant_row.remove_child(button)
		button.queue_free()
	_variant_buttons.clear()
	var group := ButtonGroup.new()
	for i: int in editor.variant_count():
		var button: Button = _make_toggle(str(i + 1), group, "Variante %d" % (i + 1))
		button.custom_minimum_size = Vector2(30, 0)
		button.pressed.connect(func() -> void: editor.set_variant(i))
		_variant_row.add_child(button)
		_variant_buttons.append(button)
	_variant_buttons[editor.variant].set_pressed_no_signal(true)
	_add_variant_button.disabled = not editor.can_add_variant()
	_remove_variant_button.disabled = not editor.can_remove_variant()


## Muestras de los colores usados en la variante activa; un clic elige ese color.
func _refresh_swatches(colors: Array[Color]) -> void:
	for child: Node in _swatch_flow.get_children():
		_swatch_flow.remove_child(child)
		child.queue_free()
	for i: int in mini(colors.size(), MAX_SWATCHES):
		var swatch_color: Color = colors[i]
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(24, 24)
		button.tooltip_text = "#%s" % swatch_color.to_html(false)
		var box: StyleBoxFlat = EditorUI._flat(swatch_color, 3, 0, 0)
		box.set_border_width_all(1)
		box.border_color = Color(0.0, 0.0, 0.0, 0.55)
		button.add_theme_stylebox_override("normal", box)
		button.add_theme_stylebox_override("pressed", box)
		var hover: StyleBoxFlat = box.duplicate()
		hover.border_color = Color.WHITE
		button.add_theme_stylebox_override("hover", hover)
		button.pressed.connect(func() -> void: editor.set_color(swatch_color))
		_swatch_flow.add_child(button)
	if colors.is_empty():
		var empty := Label.new()
		empty.text = "(modelo vacío)"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", EditorUI.COL_DIM)
		_swatch_flow.add_child(empty)


# ================================================================ acciones

## Pide confirmación con `text` y, si se acepta, ejecuta `action`.
func _confirm(text: String, ok_text: String, action: Callable) -> void:
	_confirm_action = action
	_confirm_dialog.dialog_text = text
	_confirm_dialog.ok_button_text = ok_text
	_confirm_dialog.popup_centered(Vector2i(440, 140))


func _on_confirmed() -> void:
	var action: Callable = _confirm_action
	_confirm_action = Callable()
	# Diferido: la acción puede abrir otro diálogo y este todavía se está cerrando.
	if action.is_valid():
		action.call_deferred()


## Ejecuta `action`, avisando antes si se perderían cambios sin guardar.
func _guard_unsaved(action: Callable) -> void:
	if editor.modified:
		_confirm("«%s» tiene cambios sin guardar. ¿Descartarlos?" % editor.object_name, "Descartar", action)
	else:
		action.call()


func _on_new_pressed() -> void:
	_guard_unsaved(func() -> void:
		editor.new_object()
		show_message("Objeto nuevo."))


func _on_open_pressed() -> void:
	_guard_unsaved(_show_open_dialog)


func _on_back_pressed() -> void:
	if editor.modified:
		_confirm("«%s» tiene cambios sin guardar: no se van a ver en el mapa hasta guardarlos. " % editor.object_name
				+ "¿Volver al mapa de todos modos?", "Volver al mapa", func() -> void: back_requested.emit())
	else:
		back_requested.emit()


func _on_save_pressed() -> void:
	if editor.is_new():
		_show_save_dialog()
		return
	_report_save(editor.save())


func _report_save(error: String) -> void:
	if error.is_empty():
		show_message("Objeto guardado: %s" % editor.object_name)
	else:
		show_error("No se pudo guardar el objeto. %s" % error)


func _on_restore_pressed() -> void:
	_confirm("Se va a borrar la versión modificada de «%s» y vuelve el modelo original. ¿Continuar?"
			% editor.object_name, "Restaurar", func() -> void:
		var error: String = editor.restore_original()
		if error.is_empty():
			show_message("Objeto restaurado: %s" % editor.object_name)
		else:
			show_error(error))


func _on_remove_variant_pressed() -> void:
	_confirm("¿Quitar la variante %d de «%s»? No se puede deshacer." % [editor.variant + 1, editor.object_name],
			"Quitar", func() -> void: editor.remove_variant())


# ---------------------------------------------------------------- abrir

func _show_open_dialog() -> void:
	_open_list.clear()
	for id: int in library.count():
		var label: String = library.prop_name(id)
		if not library.is_builtin(id):
			label += "   (propio)"
		elif library.is_overridden(id):
			label += "   (modificado)"
		_open_list.add_item(label, EditorUI._swatch(library.swatch(id)))
	var current: int = maxi(editor.object_id(), 0)
	_open_list.select(current)
	_on_open_item_selected(current)
	_open_dialog.popup_centered(Vector2i(440, 460))
	_open_list.ensure_current_is_visible()


func _on_open_item_selected(index: int) -> void:
	_open_variant.clear()
	for i: int in library.variant_count(index):
		_open_variant.add_item("Variante %d" % (i + 1))
	_open_variant.select(0)


func _on_open_item_activated(_index: int) -> void:
	_open_dialog.hide()
	_on_open_confirmed()


func _on_open_confirmed() -> void:
	var selected: PackedInt32Array = _open_list.get_selected_items()
	if selected.is_empty():
		return
	editor.open_object(selected[0], maxi(_open_variant.selected, 0))
	show_message("Objeto abierto: %s" % editor.object_name)


# ---------------------------------------------------------------- guardar como

func _show_save_dialog() -> void:
	_save_name.text = "" if editor.is_new() else editor.object_name
	_on_save_name_changed(_save_name.text)
	_save_dialog.popup_centered(Vector2i(440, 170))
	_save_name.grab_focus()
	_save_name.select_all()


func _on_save_name_changed(text: String) -> void:
	var key: String = PropIO.slugify(text)
	if key.is_empty():
		_save_key_label.text = "Escribe un nombre con letras o números."
	elif key == editor.object_key:
		_save_key_label.text = "Clave: %s (el objeto abierto: se guarda sobre él)." % key
	elif library.has_key(key):
		_save_key_label.text = "Clave: %s — ya existe; se va a pedir confirmación para reemplazarlo." % key
	else:
		_save_key_label.text = "Clave: %s (objeto nuevo)." % key


func _on_save_as_confirmed() -> void:
	var display_name: String = _save_name.text.strip_edges()
	var key: String = PropIO.slugify(display_name)
	if key.is_empty():
		show_error.call_deferred("El nombre necesita al menos una letra o un número.")
		return
	if library.has_key(key) and key != editor.object_key:
		var existing: String = library.prop_name(library.key_to_id(key))
		_confirm.call_deferred("Ya existe el objeto «%s» (clave %s). ¿Reemplazarlo?" % [existing, key],
				"Reemplazar", func() -> void: _report_save(editor.save_as(display_name, key)))
		return
	_report_save(editor.save_as(display_name, key))
