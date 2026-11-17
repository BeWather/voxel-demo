class_name Items
extends RefCounted
## Cosas que se juntan en modo juego (flores, hongos, pasto, manzanas), la comida que le
## gusta a cada criatura y los puntos de amistad. También arma los íconos de la mochila.

const FLOWER_RED: int = 0
const FLOWER_YELLOW: int = 1
const FLOWER_BLUE: int = 2
const MUSHROOM: int = 3
const GRASS: int = 4
const APPLE: int = 5
const COUNT: int = 6
## Máximo de cada cosa en la mochila.
const CAP: int = 20

## Claves estables usadas en los archivos de mapa.
const KEYS: Array[String] = ["flor_roja", "flor_amarilla", "flor_azul", "hongo", "pasto", "manzana"]
const NAMES: Array[String] = ["flor roja", "flor amarilla", "flor azul", "hongo", "pasto", "manzana"]

## Amistad: de 0 a MAX_POINTS puntos; cada POINTS_PER_HEART puntos es un corazón (0 a 3).
const POINTS_PER_HEART: int = 4
const MAX_POINTS: int = 12
const FAVOURITE_POINTS: int = 4
const LIKED_POINTS: int = 2
const PET_POINTS: int = 1
## Corazones necesarios para dejar de huir, para seguir al jugador y para dejarse montar
## (unicornio y dragón).
const HEARTS_NO_FLEE: int = 1
const HEARTS_FRIEND: int = 2
const HEARTS_BEST: int = 3

## Comida preferida de cada tipo de criatura (índice de CharacterLibrary; -1 = ninguna)...
const FAVOURITE: Array[int] = [
	GRASS, GRASS, APPLE, MUSHROOM, FLOWER_YELLOW, GRASS, MUSHROOM, -1, APPLE, APPLE, MUSHROOM,
]
## ...y otras cosas que también acepta (dan menos amistad).
const ALSO_LIKED: Array[Array] = [
	[FLOWER_YELLOW], [APPLE], [MUSHROOM], [APPLE], [FLOWER_RED, FLOWER_BLUE], [FLOWER_BLUE],
	[APPLE], [], [GRASS], [FLOWER_BLUE], [FLOWER_RED],
]
## Nombres sugeridos al hacerse amiga de una criatura.
const PET_NAMES: Array[Array] = [
	["Nube", "Copito", "Lana"], ["Manchita", "Margarita", "Lola"], ["Trufa", "Rosita", "Gordi"],
	["Pepa", "Clara", "Pluma"], ["Saltarín", "Algodón", "Canela"], ["Cuac", "Pato Lucas", "Charco"],
	["Rojito", "Astuto", "Fuego"], ["Amigo"], ["Trueno", "Estrella", "Miel"], ["Arcoíris", "Luna", "Brillo"],
	["Chispa", "Dino", "Humito"],
]


static func key_to_item(key: String) -> int:
	return KEYS.find(key)


## Qué se junta de un prop (por su id incorporado), o -1 si no se puede juntar.
static func item_for_prop(prop_id: int) -> int:
	match prop_id:
		PropLibrary.FLOWER_RED:
			return FLOWER_RED
		PropLibrary.FLOWER_YELLOW:
			return FLOWER_YELLOW
		PropLibrary.FLOWER_BLUE:
			return FLOWER_BLUE
		PropLibrary.MUSHROOM:
			return MUSHROOM
		PropLibrary.TALL_GRASS:
			return GRASS
		_:
			return -1


static func favourite(type: int) -> int:
	return FAVOURITE[type] if type >= 0 and type < FAVOURITE.size() else -1


## Puntos de amistad que da una comida a un tipo de criatura (0 = no la quiere).
static func food_points(type: int, item: int) -> int:
	if type < 0 or type >= FAVOURITE.size() or item < 0:
		return 0
	if FAVOURITE[type] == item:
		return FAVOURITE_POINTS
	return LIKED_POINTS if ALSO_LIKED[type].has(item) else 0


static func hearts_for(points: int) -> int:
	@warning_ignore("integer_division")
	return clampi(points, 0, MAX_POINTS) / POINTS_PER_HEART


static func suggested_name(type: int, pick: int) -> String:
	var names: Array = PET_NAMES[clampi(type, 0, PET_NAMES.size() - 1)]
	return str(names[posmod(pick, names.size())])


## Mochila vacía: una entrada por cosa, en cero.
static func empty_backpack() -> Dictionary:
	var bag: Dictionary = {}
	for key: String in KEYS:
		bag[key] = 0
	return bag


## Modelo mini-voxel de la manzana (también se usa para colgarla de los robles).
static func apple_voxels() -> Dictionary[int, Color]:
	var vox: Dictionary[int, Color] = {}
	var red := Color(0.86, 0.16, 0.18)
	for y: int in range(0, 3):
		for z: int in range(-1, 2):
			for x: int in range(-1, 2):
				if absi(x) + absi(z) == 2 and y != 1:
					continue
				vox[PropLibrary.voxel_key(x, y, z)] = red.lightened(0.12) if (x == -1 and y == 2) else red
	vox[PropLibrary.voxel_key(0, 3, 0)] = Color(0.40, 0.26, 0.14)
	vox[PropLibrary.voxel_key(1, 3, 0)] = Color(0.30, 0.62, 0.25)
	return vox


## Ícono a partir de un modelo mini-voxel: su vista de frente, un cuadrado por voxel.
static func icon_from_voxels(vox: Dictionary[int, Color], size: int = 32) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	if vox.is_empty():
		return ImageTexture.create_from_image(image)
	var low := Vector3i(999, 999, 999)
	var high := Vector3i(-999, -999, -999)
	for key: int in vox:
		var cell: Vector3i = PropLibrary.voxel_cell(key)
		low = low.min(cell)
		high = high.max(cell)
	var span: Vector3i = high - low + Vector3i.ONE
	var scale: int = maxi(1, size / maxi(span.x, span.y))
	var offset := Vector2i((size - span.x * scale) / 2, (size - span.y * scale) / 2)
	# De cada columna (x, y) se ve el voxel de más adelante.
	var front: Dictionary[Vector2i, int] = {}
	for key: int in vox:
		var cell: Vector3i = PropLibrary.voxel_cell(key)
		var spot := Vector2i(cell.x, cell.y)
		if not front.has(spot) or cell.z > PropLibrary.voxel_cell(front[spot]).z:
			front[spot] = key
	for spot: Vector2i in front:
		var color: Color = vox[front[spot]]
		var px: int = offset.x + (spot.x - low.x) * scale
		var py: int = size - offset.y - (spot.y - low.y + 1) * scale
		image.fill_rect(Rect2i(px, py, scale, scale), Color(color.r, color.g, color.b, 1.0))
	return ImageTexture.create_from_image(image)


## Íconos de las seis cosas, en el orden de KEYS, a partir de los modelos de la biblioteca.
static func build_icons(library: PropLibrary) -> Array[ImageTexture]:
	var icons: Array[ImageTexture] = []
	for prop_id: int in [PropLibrary.FLOWER_RED, PropLibrary.FLOWER_YELLOW, PropLibrary.FLOWER_BLUE,
			PropLibrary.MUSHROOM, PropLibrary.TALL_GRASS]:
		icons.append(icon_from_voxels(library.get_voxels(prop_id, 0)))
	icons.append(icon_from_voxels(apple_voxels()))
	return icons


const _HEART_ROWS: Array[String] = [
	".XX.XX.",
	"XXXXXXX",
	"XXXXXXX",
	".XXXXX.",
	"..XXX..",
	"...X...",
]


## Dibujo de un corazón (lleno o vacío) de 7 x 6 "píxeles", ampliado `scale` veces.
static func heart_image(filled: bool, scale: int = 3) -> Image:
	var image := Image.create(7 * scale + 2, 6 * scale + 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var fill := Color(0.95, 0.22, 0.35) if filled else Color(0.25, 0.22, 0.26, 0.85)
	var edge := Color(0.35, 0.05, 0.12) if filled else Color(0.95, 0.95, 0.97, 0.9)
	# Primero el borde (el dibujo corrido un píxel hacia cada lado) y encima el relleno.
	for pass_index: int in 2:
		for row: int in _HEART_ROWS.size():
			for col: int in 7:
				if _HEART_ROWS[row][col] != "X":
					continue
				if pass_index == 0:
					image.fill_rect(Rect2i(col * scale, row * scale, scale + 2, scale + 2), edge)
				else:
					image.fill_rect(Rect2i(col * scale + 1, row * scale + 1, scale, scale), fill)
	return image


## Fila de tres corazones con `hearts` llenos.
static func hearts_texture(hearts: int) -> ImageTexture:
	var full: Image = heart_image(true)
	var empty: Image = heart_image(false)
	var strip := Image.create(full.get_width() * 3 + 4, full.get_height(), false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.0, 0.0, 0.0, 0.0))
	for i: int in 3:
		var source: Image = full if i < hearts else empty
		strip.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(i * (full.get_width() + 2), 0))
	return ImageTexture.create_from_image(strip)


## Globo de pensamiento con un ícono adentro (lo que la criatura quiere comer).
static func bubble_texture(icon: ImageTexture) -> ImageTexture:
	var size: int = 44
	var image := Image.create(size, size + 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var white := Color(1.0, 1.0, 1.0, 0.96)
	var edge := Color(0.25, 0.28, 0.35, 0.95)
	image.fill_rect(Rect2i(2, 0, size - 4, size), edge)
	image.fill_rect(Rect2i(0, 2, size, size - 4), edge)
	image.fill_rect(Rect2i(4, 2, size - 8, size - 4), white)
	image.fill_rect(Rect2i(2, 4, size - 4, size - 8), white)
	image.fill_rect(Rect2i(8, size, 8, 4), edge)
	image.fill_rect(Rect2i(9, size - 1, 6, 4), white)
	image.fill_rect(Rect2i(4, size + 5, 4, 3), edge)
	var picture: Image = icon.get_image()
	picture.convert(Image.FORMAT_RGBA8)
	image.blend_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), Vector2i((size - picture.get_width()) / 2, (size - picture.get_height()) / 2))
	return ImageTexture.create_from_image(image)
