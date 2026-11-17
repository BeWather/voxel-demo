class_name EntityOverhead
extends Node3D
## Lo que flota sobre una criatura en modo juego cuando el jugador está cerca: sus
## corazones de amistad, el globo con la comida que quiere y su nombre. Todo son imágenes
## que siempre miran a la cámara, para que no haga falta leer.

const PIXEL: float = 0.011

var _hearts: Sprite3D
var _bubble: Sprite3D
var _name: Label3D
var _shown_hearts: int = -1
var _shown_item: int = -2
var _shown_name: String = ""

## Texturas compartidas por todas las criaturas.
static var _heart_textures: Array[ImageTexture] = []
static var _bubble_textures: Array[ImageTexture] = []


## Prepara las texturas (una vez por partida) con los íconos de la mochila.
static func prepare(icons: Array[ImageTexture]) -> void:
	_heart_textures.clear()
	for hearts: int in 4:
		_heart_textures.append(Items.hearts_texture(hearts))
	_bubble_textures.clear()
	for icon: ImageTexture in icons:
		_bubble_textures.append(Items.bubble_texture(icon))


func _init() -> void:
	_hearts = _make_sprite()
	add_child(_hearts)
	_bubble = _make_sprite()
	_bubble.position = Vector3(0.0, 0.55, 0.0)
	add_child(_bubble)
	_name = Label3D.new()
	_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name.pixel_size = 0.0065
	_name.font_size = 44
	_name.outline_size = 12
	_name.modulate = Color(1.0, 0.97, 0.80)
	_name.outline_modulate = Color(0.10, 0.08, 0.12)
	_name.position = Vector3(0.0, -0.26, 0.0)
	_name.no_depth_test = true
	add_child(_name)


func _make_sprite() -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = PIXEL
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.no_depth_test = true
	sprite.render_priority = 2
	return sprite


## Actualiza lo que se muestra. `wanted_item` es la comida del globo (-1 = sin globo).
func refresh(hearts: int, wanted_item: int, pet_name: String) -> void:
	if hearts != _shown_hearts:
		_shown_hearts = hearts
		if hearts >= 0 and hearts < _heart_textures.size():
			_hearts.texture = _heart_textures[hearts]
		_hearts.visible = hearts >= 0
	if wanted_item != _shown_item:
		_shown_item = wanted_item
		_bubble.visible = wanted_item >= 0 and wanted_item < _bubble_textures.size()
		if _bubble.visible:
			_bubble.texture = _bubble_textures[wanted_item]
	if pet_name != _shown_name:
		_shown_name = pet_name
		_name.text = pet_name
	_name.visible = not pet_name.is_empty()


func shows_bubble() -> bool:
	return _bubble.visible


func shown_hearts() -> int:
	return _shown_hearts
