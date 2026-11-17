class_name Blocks
extends RefCounted
## Tabla de tipos de bloque: id, nombre, color base y banderas.

const AIR: int = 0
const GRASS: int = 1
const DIRT: int = 2
const STONE: int = 3
const SAND: int = 4
const WATER: int = 5
const SNOW: int = 6
const WOOD: int = 7
const PATH: int = 8
const COUNT: int = 9

## Índice de la cara superior (+Y) según el orden de caras de ChunkMesher.
const FACE_TOP: int = 2

const NAMES: Array[String] = [
	"Aire", "Pasto", "Tierra", "Piedra", "Arena", "Agua", "Nieve", "Madera", "Camino",
]

const COLORS: Array[Color] = [
	Color(0.0, 0.0, 0.0, 0.0),
	Color(0.36, 0.66, 0.24),
	Color(0.50, 0.35, 0.21),
	Color(0.47, 0.48, 0.52),
	Color(0.82, 0.72, 0.46),
	Color(0.10, 0.36, 0.72, 0.78),
	Color(0.94, 0.96, 0.99),
	Color(0.64, 0.46, 0.26),
	Color(0.72, 0.63, 0.46),
]


static func is_valid(id: int) -> bool:
	return id >= 0 and id < COUNT


static func block_name(id: int) -> String:
	return NAMES[id] if is_valid(id) else "?"


## Transparente: no tapa las caras de los vecinos (aire y agua).
static func is_transparent(id: int) -> bool:
	return id == AIR or id == WATER


## Sólido: puede sostener un prop (ni aire ni agua).
static func is_solid(id: int) -> bool:
	return id != AIR and id != WATER


## Color de una cara. El pasto es verde arriba y color tierra en los lados y abajo.
static func face_color(id: int, face: int) -> Color:
	if id == GRASS and face != FACE_TOP:
		return COLORS[DIRT]
	return COLORS[id]
