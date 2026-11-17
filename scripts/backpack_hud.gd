class_name BackpackHud
extends HBoxContainer
## Mochila del modo juego: una fila de casilleros con el ícono de cada cosa, cuántas hay y
## la tecla que la elige. El casillero elegido se marca con un borde; al juntar algo, su
## casillero da un saltito.

const SLOT_SIZE: Vector2 = Vector2(50, 50)
const COL_SLOT: Color = Color(0.09, 0.10, 0.13, 0.88)
const COL_BORDER: Color = Color(0.30, 0.33, 0.40, 0.9)
const COL_SELECTED: Color = Color(1.0, 0.85, 0.30)

var _slots: Array[PanelContainer] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _shown: Array[int] = []
var _selected: int = -1


func setup(icons: Array[ImageTexture]) -> void:
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i: int in Items.COUNT:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.pivot_offset = SLOT_SIZE * 0.5
		add_child(slot)
		var icon := TextureRect.new()
		icon.texture = icons[i]
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var key := Label.new()
		key.text = str(i + 1)
		key.add_theme_font_size_override("font_size", 10)
		key.add_theme_color_override("font_color", EditorUI.COL_DIM)
		key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		slot.add_child(key)
		var count := Label.new()
		count.add_theme_font_size_override("font_size", 15)
		count.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		count.add_theme_constant_override("outline_size", 5)
		count.size_flags_horizontal = Control.SIZE_SHRINK_END
		count.size_flags_vertical = Control.SIZE_SHRINK_END
		slot.add_child(count)
		_slots.append(slot)
		_icons.append(icon)
		_counts.append(count)
		_shown.append(-1)
	select(0)


## Muestra las cantidades de la mochila. Un casillero cuya cantidad subió da un saltito.
func refresh(backpack: Dictionary) -> void:
	for i: int in Items.COUNT:
		var amount: int = backpack.get(Items.KEYS[i], 0)
		if amount == _shown[i]:
			continue
		var grew: bool = _shown[i] >= 0 and amount > _shown[i]
		_shown[i] = amount
		_counts[i].text = str(amount)
		_icons[i].modulate = Color(1.0, 1.0, 1.0, 1.0 if amount > 0 else 0.28)
		_counts[i].modulate = Color(1.0, 1.0, 1.0, 1.0 if amount > 0 else 0.45)
		if grew and is_inside_tree():
			var tween: Tween = create_tween()
			_slots[i].scale = Vector2(1.35, 1.35)
			tween.tween_property(_slots[i], "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func select(index: int) -> void:
	if index == _selected:
		return
	_selected = index
	for i: int in _slots.size():
		var style := StyleBoxFlat.new()
		style.bg_color = COL_SLOT
		style.set_corner_radius_all(6)
		style.set_content_margin_all(4)
		style.set_border_width_all(3 if i == index else 1)
		style.border_color = COL_SELECTED if i == index else COL_BORDER
		_slots[i].add_theme_stylebox_override("panel", style)


func selected() -> int:
	return _selected


func shown_count(index: int) -> int:
	return _shown[index]
