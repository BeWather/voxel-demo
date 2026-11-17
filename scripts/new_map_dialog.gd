class_name NewMapDialog
extends ConfirmationDialog
## Diálogo de "Nuevo": tamaño del mapa (S, M o L) y semilla.

## Se aceptó el diálogo con un tamaño y una semilla válidos.
signal create_requested(size_key: String, map_seed: int)

const MAX_SEED: int = 999999

var _size_option: OptionButton
var _seed_edit: LineEdit
var _note: Label


func _init() -> void:
	title = "Mapa nuevo"
	ok_button_text = "Crear"
	cancel_button_text = "Cancelar"
	confirmed.connect(_on_confirmed)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var size_label := Label.new()
	size_label.text = "Tamaño"
	box.add_child(size_label)
	_size_option = OptionButton.new()
	for key: String in AppConfig.SIZE_KEYS:
		_size_option.add_item(AppConfig.size_label(key))
	_size_option.item_selected.connect(func(_index: int) -> void: _refresh_note())
	box.add_child(_size_option)

	var seed_label := Label.new()
	seed_label.text = "Semilla"
	box.add_child(seed_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_seed_edit = LineEdit.new()
	_seed_edit.max_length = 9
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.custom_minimum_size = Vector2(180, 0)
	_seed_edit.text_submitted.connect(func(_text: String) -> void: _accept())
	row.add_child(_seed_edit)
	var random_button := Button.new()
	random_button.text = "Al azar"
	random_button.pressed.connect(randomize_seed)
	row.add_child(random_button)

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 12)
	_note.add_theme_color_override("font_color", EditorUI.COL_DIM)
	_note.custom_minimum_size = Vector2(340, 36)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)


## Abre el diálogo con `size_key` elegido y una semilla al azar.
func open(size_key: String) -> void:
	select_size(size_key)
	randomize_seed()
	popup_centered(Vector2i(400, 230))
	_seed_edit.grab_focus()


func select_size(size_key: String) -> void:
	var index: int = AppConfig.SIZE_KEYS.find(size_key.to_upper())
	_size_option.select(maxi(index, 0))
	_refresh_note()


func selected_size() -> String:
	return AppConfig.SIZE_KEYS[maxi(_size_option.selected, 0)]


func set_seed_text(text: String) -> void:
	_seed_edit.text = text


func randomize_seed() -> void:
	_seed_edit.text = str(randi() % (MAX_SEED + 1))


## Semilla escrita en el diálogo. Un texto que no es un número se convierte en uno
## (su hash), así cualquier palabra sirve de semilla.
func seed_value() -> int:
	var text: String = _seed_edit.text.strip_edges()
	if text.is_empty():
		return randi() % (MAX_SEED + 1)
	if text.is_valid_int():
		return absi(text.to_int()) % (MAX_SEED + 1)
	return absi(text.hash()) % (MAX_SEED + 1)


func _refresh_note() -> void:
	var side: int = AppConfig.side_for(selected_size())
	if side <= AppConfig.INSTANT_SIDE:
		_note.text = "El mapa actual se reemplaza y el historial de deshacer se vacía."
	else:
		_note.text = "Los mapas grandes tardan unos segundos en generarse. El mapa actual se reemplaza."


func _accept() -> void:
	hide()
	_on_confirmed()


func _on_confirmed() -> void:
	create_requested.emit(selected_size(), seed_value())
