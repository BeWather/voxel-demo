class_name CharacterLibrary
extends RefCounted
## Modelos articulados mini-voxel (1/8 de bloque) para avatares, animales y aldeanos.
## Cada personaje es una lista de partes: {"role", "side", "pivot" (en bloques), "mesh"}.
## El frente del modelo mira hacia +Z y los pies apoyan en y = 0.

const SHEEP: int = 0
const COW: int = 1
const PIG: int = 2
const CHICKEN: int = 3
const RABBIT: int = 4
const DUCK: int = 5
const FOX: int = 6
const VILLAGER: int = 7
const PONY: int = 8
const UNICORN: int = 9
const DRAGON: int = 10
const ENTITY_COUNT: int = 11
const VILLAGER_VARIANTS: int = 3
const AVATAR_COUNT: int = 12
## Cantidad de aspectos de cada criatura (pelaje del poni, color del dragón…).
const ENTITY_VARIANTS: Array[int] = [1, 1, 1, 1, 1, 1, 1, 3, 3, 1, 2]

## Claves estables usadas en los archivos de mapa.
const ENTITY_KEYS: Array[String] = [
	"oveja", "vaca", "cerdo", "gallina", "conejo", "pato", "zorro", "aldeano",
	"poni", "unicornio", "dragon",
]
const ENTITY_NAMES: Array[String] = [
	"Oveja", "Vaca", "Cerdo", "Gallina", "Conejo", "Pato", "Zorro", "Aldeano",
	"Poni", "Unicornio", "Dragón",
]
const ENTITY_SWATCHES: Array[Color] = [
	Color(0.93, 0.92, 0.88), Color(0.20, 0.18, 0.17), Color(0.93, 0.62, 0.65),
	Color(0.98, 0.97, 0.92), Color(0.62, 0.55, 0.48), Color(0.12, 0.45, 0.27),
	Color(0.88, 0.45, 0.13), Color(0.55, 0.38, 0.24),
	Color(0.60, 0.40, 0.24), Color(0.96, 0.80, 0.92), Color(0.36, 0.72, 0.40),
]
## Caja de colisión (mitad del ancho y alto, en bloques).
## Los animales grandes (poni, unicornio, dragón) son más largos que una celda, pero su
## caja de colisión entra en una: así nunca quedan metidos en un bloque vecino.
const BODY_HALF: Array[float] = [0.30, 0.38, 0.30, 0.20, 0.20, 0.20, 0.25, 0.30, 0.45, 0.45, 0.45]
const BODY_HEIGHT: Array[float] = [1.0, 1.4, 0.85, 0.7, 0.6, 0.7, 0.8, 1.75, 1.75, 1.85, 1.9]
## Velocidad al caminar (bloques por segundo). El aldeano no camina.
const WALK_SPEED: Array[float] = [1.2, 1.0, 1.3, 1.5, 2.0, 1.3, 2.4, 0.0, 1.6, 1.6, 0.8]
## Animales que huyen cuando el jugador se acerca.
const FLEES: Array[bool] = [false, false, false, true, true, false, true, false, false, false, false]

## Criaturas que se pueden montar en modo juego, con su velocidad al paso (bloques por
## segundo; 0 = no se monta) y el punto del lomo donde va sentado el jinete (en voxeles).
const RIDE_SPEED: Array[float] = [0.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 6.0, 6.5, 3.5]
const SEAT: Array[Vector3] = [
	Vector3.ZERO, Vector3(0, 11, -1), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
	Vector3.ZERO, Vector3.ZERO, Vector3(0, 11, -1), Vector3(0, 11, -1), Vector3(0, 11, -3),
]
## Al galope (Shift) la montura va GALLOP_FACTOR veces más rápido.
const GALLOP_FACTOR: float = 1.6

## Avatares: primero las niñas, después los personajes de la primera versión.
const AVATAR_NAMES: Array[String] = [
	"Lola", "Mora", "Abril", "Princesa", "Hada", "Astronauta",
	"Exploradora", "Granjero", "Maga", "Herrero", "Pastora", "Viajero",
]
## Identificadores estables: son lo que se guarda en los ajustes, así agregar o reordenar
## avatares no cambia la elección guardada.
const AVATAR_IDS: Array[String] = [
	"lola", "mora", "abril", "princesa", "hada", "astronauta",
	"exploradora", "granjero", "maga", "herrero", "pastora", "viajero",
]
## Orden de los avatares cuando la elección se guardaba como número (primera versión).
const LEGACY_AVATAR_IDS: Array[String] = [
	"exploradora", "granjero", "maga", "herrero", "pastora", "viajero",
]
const FIRST_ADULT_AVATAR: int = 6
## Alto de la caja de colisión del jugador según el avatar (en bloques).
const CHILD_BODY_HEIGHT: float = 1.45
const ADULT_BODY_HEIGHT: float = 1.7
## Nombres por defecto según el aspecto del aldeano (variante 0, 1 y 2).
const DEFAULT_NPC_NAMES: Array[Array] = [
	["Ramón", "Tomás", "Bruno"], ["Anselmo", "Ignacio", "Fermín"], ["Marta", "Lucía", "Elena"],
]
const DEFAULT_NPC_LINES: Array[String] = [
	"¡Hola! Qué bueno ver una cara nueva por la pradera.",
	"Las ovejas pastan tranquilas, pero las gallinas se asustan con nada.",
	"Si ves al zorro, avísame: anda rondando el estanque.",
]

const _EYE: Color = Color(0.10, 0.10, 0.12)

var material: StandardMaterial3D
var _cache: Dictionary[String, Array] = {}


func _init() -> void:
	material = ChunkMesher.make_opaque_material()


static func is_valid_entity(type: int) -> bool:
	return type >= 0 and type < ENTITY_COUNT


static func entity_key_to_type(key: String) -> int:
	return ENTITY_KEYS.find(key)


## Nombre por defecto para un aldeano nuevo. `pick` elige entre los nombres de su variante.
static func default_npc_name(variant: int, pick: int) -> String:
	var names: Array = DEFAULT_NPC_NAMES[clampi(variant, 0, VILLAGER_VARIANTS - 1)]
	return str(names[posmod(pick, names.size())])


static func variant_count(type: int) -> int:
	return ENTITY_VARIANTS[type] if is_valid_entity(type) else 1


## Índice de un avatar a partir de su identificador, o -1 si no existe.
static func avatar_index(id: String) -> int:
	return AVATAR_IDS.find(id)


static func is_child_avatar(index: int) -> bool:
	return index >= 0 and index < FIRST_ADULT_AVATAR


static func avatar_body_height(index: int) -> float:
	return CHILD_BODY_HEIGHT if is_child_avatar(index) else ADULT_BODY_HEIGHT


## Altura de la cadera del avatar (donde nacen las piernas), en bloques. Al montar, la
## cadera se apoya en el lomo: así una niña y un adulto quedan sentados y no flotando.
static func avatar_hip_height(index: int) -> float:
	return (3.0 if is_child_avatar(index) else 5.0) * PropLibrary.VOXEL


static func is_rideable(type: int) -> bool:
	return is_valid_entity(type) and RIDE_SPEED[type] > 0.0


## Lugar del jinete sobre la criatura, en bloques y en el espacio del modelo.
static func seat_position(type: int) -> Vector3:
	return SEAT[type] * PropLibrary.VOXEL


## Partes de una criatura. `variant` elige el aspecto en las que tienen más de uno.
func get_entity_parts(type: int, variant: int = 0) -> Array[Dictionary]:
	var look: int = clampi(variant, 0, variant_count(type) - 1)
	var cache_key: String = "e%d_%d" % [type, look]
	if not _cache.has(cache_key):
		_cache[cache_key] = _build_entity(type, look)
	var parts: Array[Dictionary] = []
	parts.assign(_cache[cache_key])
	return parts


func get_avatar_parts(index: int) -> Array[Dictionary]:
	var cache_key: String = "a%d" % index
	if not _cache.has(cache_key):
		_cache[cache_key] = _build_humanoid(_avatar_look(index))
	var parts: Array[Dictionary] = []
	parts.assign(_cache[cache_key])
	return parts


# ---------------------------------------------------------------- auxiliares

func _add(parts: Array[Dictionary], role: String, side: float, pivot: Vector3,
		vox: Dictionary[int, Color]) -> void:
	parts.append({
		"role": role,
		"side": side,
		"pivot": pivot * PropLibrary.VOXEL,
		"mesh": PropLibrary.mesh_from_voxels(vox, material, pivot),
	})


## Caja de voxeles desde (x0, y0, z0) con tamaño (sx, sy, sz).
static func _box(vox: Dictionary[int, Color], x0: int, y0: int, z0: int,
		sx: int, sy: int, sz: int, color: Color) -> void:
	for y: int in range(y0, y0 + sy):
		for z: int in range(z0, z0 + sz):
			for x: int in range(x0, x0 + sx):
				vox[PropLibrary._key(x, y, z)] = color


static func _dot(vox: Dictionary[int, Color], x: int, y: int, z: int, color: Color) -> void:
	vox[PropLibrary._key(x, y, z)] = color


## Quita los voxeles de una caja (para abrir huecos, como el visor de un casco).
static func _erase_box(vox: Dictionary[int, Color], x0: int, y0: int, z0: int,
		sx: int, sy: int, sz: int) -> void:
	for y: int in range(y0, y0 + sy):
		for z: int in range(z0, z0 + sz):
			for x: int in range(x0, x0 + sx):
				vox.erase(PropLibrary._key(x, y, z))


## Pata simple con pivote arriba. `side` alterna el balanceo entre patas.
func _leg(parts: Array[Dictionary], side: float, x0: int, z0: int, width: int, height: int,
		color: Color, hoof: Color) -> void:
	var vox: Dictionary[int, Color] = {}
	_box(vox, x0, 0, z0, width, height, width, color)
	_box(vox, x0, 0, z0, width, 1, width, hoof)
	_add(parts, "leg", side, Vector3(x0 + width * 0.5, height, z0 + width * 0.5), vox)


func _build_entity(type: int, variant: int) -> Array[Dictionary]:
	match type:
		SHEEP:
			return _build_sheep()
		COW:
			return _build_cow()
		PIG:
			return _build_pig()
		CHICKEN:
			return _build_chicken()
		RABBIT:
			return _build_rabbit()
		DUCK:
			return _build_duck()
		FOX:
			return _build_fox()
		PONY:
			return _build_pony(variant, false)
		UNICORN:
			return _build_pony(0, true)
		DRAGON:
			return _build_dragon(variant)
		_:
			return _build_humanoid(_villager_look(variant))


# ---------------------------------------------------------------- animales

func _build_sheep() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var wool := Color(0.93, 0.92, 0.88)
	var skin := Color(0.27, 0.24, 0.23)
	_leg(parts, 1.0, -3, 2, 2, 3, skin, skin.darkened(0.3))
	_leg(parts, -1.0, 1, 2, 2, 3, skin, skin.darkened(0.3))
	_leg(parts, -1.0, -3, -4, 2, 3, skin, skin.darkened(0.3))
	_leg(parts, 1.0, 1, -4, 2, 3, skin, skin.darkened(0.3))
	var body: Dictionary[int, Color] = {}
	_box(body, -3, 3, -5, 6, 5, 10, wool)
	# Lana abultada: una capa extra más chica arriba y a los lados.
	_box(body, -2, 8, -4, 4, 1, 8, wool)
	_box(body, -4, 4, -4, 8, 3, 8, wool.darkened(0.04))
	_add(parts, "body", 0.0, Vector3(0, 3, 0), body)
	var tail: Dictionary[int, Color] = {}
	_box(tail, -1, 5, -6, 2, 2, 1, wool)
	_add(parts, "tail", 0.0, Vector3(0, 6, -5), tail)
	var head: Dictionary[int, Color] = {}
	_box(head, -2, 5, 5, 4, 4, 3, skin)
	_box(head, -2, 9, 4, 4, 1, 3, wool)
	_dot(head, -3, 8, 5, skin)
	_dot(head, 2, 8, 5, skin)
	_dot(head, -2, 7, 7, Color(0.95, 0.95, 0.9))
	_dot(head, 1, 7, 7, Color(0.95, 0.95, 0.9))
	_add(parts, "head", 0.0, Vector3(0, 6, 5), head)
	return parts


func _build_cow() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var white := Color(0.94, 0.93, 0.90)
	var black := Color(0.16, 0.15, 0.15)
	var pink := Color(0.93, 0.66, 0.66)
	var hoof := Color(0.20, 0.17, 0.15)
	_leg(parts, 1.0, -3, 4, 2, 5, white, hoof)
	_leg(parts, -1.0, 1, 4, 2, 5, black, hoof)
	_leg(parts, -1.0, -3, -6, 2, 5, black, hoof)
	_leg(parts, 1.0, 1, -6, 2, 5, white, hoof)
	var body: Dictionary[int, Color] = {}
	_box(body, -3, 5, -6, 6, 6, 12, white)
	# Manchas negras en bloques de 2 voxeles.
	for y: int in range(5, 11):
		for z: int in range(-6, 6):
			for x: int in range(-3, 3):
				if PropLibrary._hash((x + 8) >> 1, y >> 1, (z + 8) >> 2, 41) < 0.38:
					_dot(body, x, y, z, black)
	_box(body, -1, 4, -3, 2, 1, 2, pink)
	_add(parts, "body", 0.0, Vector3(0, 5, 0), body)
	var tail: Dictionary[int, Color] = {}
	_box(tail, 0, 6, -7, 1, 5, 1, white)
	_dot(tail, 0, 5, -7, black)
	_add(parts, "tail", 0.0, Vector3(0.5, 11, -6), tail)
	var head: Dictionary[int, Color] = {}
	_box(head, -2, 8, 6, 4, 5, 4, white)
	_box(head, -2, 11, 6, 2, 2, 3, black)
	_box(head, -2, 8, 10, 4, 2, 1, pink)
	_dot(head, -2, 11, 9, _EYE)
	_dot(head, 1, 11, 9, _EYE)
	_dot(head, -3, 13, 7, Color(0.92, 0.88, 0.75))
	_dot(head, 2, 13, 7, Color(0.92, 0.88, 0.75))
	_dot(head, -3, 11, 6, black)
	_dot(head, 2, 11, 6, white)
	_add(parts, "head", 0.0, Vector3(0, 9, 6), head)
	return parts


func _build_pig() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var pink := Color(0.93, 0.62, 0.65)
	var dark := Color(0.82, 0.48, 0.53)
	_leg(parts, 1.0, -3, 2, 2, 2, pink, dark)
	_leg(parts, -1.0, 1, 2, 2, 2, pink, dark)
	_leg(parts, -1.0, -3, -4, 2, 2, pink, dark)
	_leg(parts, 1.0, 1, -4, 2, 2, pink, dark)
	var body: Dictionary[int, Color] = {}
	_box(body, -3, 2, -5, 6, 5, 10, pink)
	_add(parts, "body", 0.0, Vector3(0, 2, 0), body)
	var tail: Dictionary[int, Color] = {}
	_dot(tail, 0, 5, -6, dark)
	_dot(tail, 0, 6, -6, dark)
	_dot(tail, -1, 6, -6, dark)
	_add(parts, "tail", 0.0, Vector3(0.5, 5, -5), tail)
	var head: Dictionary[int, Color] = {}
	_box(head, -2, 3, 5, 4, 4, 3, pink)
	_box(head, -1, 3, 8, 2, 2, 1, dark)
	_dot(head, -2, 5, 7, _EYE)
	_dot(head, 1, 5, 7, _EYE)
	_dot(head, -2, 7, 5, dark)
	_dot(head, 1, 7, 5, dark)
	_add(parts, "head", 0.0, Vector3(0, 4, 5), head)
	return parts


func _build_chicken() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var white := Color(0.98, 0.97, 0.92)
	var yellow := Color(0.96, 0.74, 0.18)
	var red := Color(0.85, 0.16, 0.14)
	_leg(parts, 1.0, -2, 0, 1, 1, yellow, yellow)
	_leg(parts, -1.0, 1, 0, 1, 1, yellow, yellow)
	var body: Dictionary[int, Color] = {}
	_box(body, -2, 1, -2, 4, 3, 5, white)
	_box(body, -1, 3, -3, 2, 2, 1, white.darkened(0.08))
	_dot(body, -1, 5, -3, white.darkened(0.08))
	_dot(body, 0, 5, -3, white.darkened(0.08))
	_add(parts, "body", 0.0, Vector3(0, 1, 0), body)
	for side: int in [-1, 1]:
		var wing: Dictionary[int, Color] = {}
		var wx: int = -3 if side < 0 else 2
		_box(wing, wx, 2, -1, 1, 2, 3, white.darkened(0.12))
		_add(parts, "wing", float(side), Vector3(wx + (1.0 if side < 0 else 0.0), 4, 0), wing)
	var head: Dictionary[int, Color] = {}
	_box(head, -1, 3, 2, 2, 3, 2, white)
	_box(head, -1, 6, 2, 2, 1, 2, red)
	_box(head, -1, 4, 4, 2, 1, 1, yellow)
	_box(head, -1, 3, 4, 2, 1, 1, red)
	_add(parts, "head", 0.0, Vector3(0, 3, 2), head)
	return parts


func _build_rabbit() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var fur := Color(0.64, 0.56, 0.48)
	var light := Color(0.86, 0.82, 0.76)
	# Patas traseras largas y delanteras cortas.
	for side: int in [-1, 1]:
		var lx: int = -2 if side < 0 else 1
		var back: Dictionary[int, Color] = {}
		_box(back, lx, 0, -3, 1, 1, 2, fur.darkened(0.1))
		_add(parts, "leg", float(side), Vector3(lx + 0.5, 1, -2), back)
		var front: Dictionary[int, Color] = {}
		_box(front, lx, 0, 0, 1, 1, 1, fur.darkened(0.1))
		_add(parts, "leg", float(-side), Vector3(lx + 0.5, 1, 0.5), front)
	var body: Dictionary[int, Color] = {}
	_box(body, -2, 1, -3, 4, 3, 5, fur)
	_box(body, -1, 1, -2, 2, 1, 3, light)
	_add(parts, "body", 0.0, Vector3(0, 1, 0), body)
	var tail: Dictionary[int, Color] = {}
	_box(tail, -1, 2, -4, 2, 2, 1, Color(0.97, 0.97, 0.95))
	_add(parts, "tail", 0.0, Vector3(0, 3, -3), tail)
	var head: Dictionary[int, Color] = {}
	_box(head, -2, 3, 1, 4, 3, 3, fur)
	_box(head, -1, 3, 4, 2, 1, 1, light)
	_dot(head, -2, 5, 3, _EYE)
	_dot(head, 1, 5, 3, _EYE)
	_box(head, -2, 6, 1, 1, 3, 1, fur)
	_box(head, 1, 6, 1, 1, 3, 1, fur)
	_add(parts, "head", 0.0, Vector3(0, 3, 1), head)
	return parts


func _build_duck() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var brown := Color(0.56, 0.46, 0.36)
	var belly := Color(0.80, 0.76, 0.68)
	var green := Color(0.10, 0.44, 0.26)
	var orange := Color(0.95, 0.55, 0.12)
	_leg(parts, 1.0, -2, 0, 1, 1, orange, orange)
	_leg(parts, -1.0, 1, 0, 1, 1, orange, orange)
	var body: Dictionary[int, Color] = {}
	_box(body, -2, 1, -3, 4, 3, 6, brown)
	_box(body, -2, 1, -3, 4, 1, 6, belly)
	_box(body, -1, 3, -4, 2, 2, 1, Color(0.20, 0.18, 0.18))
	_add(parts, "body", 0.0, Vector3(0, 1, 0), body)
	for side: int in [-1, 1]:
		var wing: Dictionary[int, Color] = {}
		var wx: int = -3 if side < 0 else 2
		_box(wing, wx, 2, -2, 1, 2, 4, brown.darkened(0.18))
		_dot(wing, wx, 2, -2, Color(0.20, 0.35, 0.75))
		_add(parts, "wing", float(side), Vector3(wx + (1.0 if side < 0 else 0.0), 4, 0), wing)
	var head: Dictionary[int, Color] = {}
	_box(head, -1, 3, 2, 2, 1, 2, brown)
	_box(head, -1, 4, 2, 2, 1, 2, Color(0.96, 0.96, 0.94))
	_box(head, -1, 5, 2, 2, 2, 2, green)
	_box(head, -1, 5, 4, 2, 1, 2, Color(0.95, 0.80, 0.20))
	_add(parts, "head", 0.0, Vector3(0, 3, 2), head)
	return parts


func _build_fox() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var orange := Color(0.88, 0.45, 0.13)
	var white := Color(0.96, 0.94, 0.90)
	var dark := Color(0.22, 0.16, 0.13)
	_leg(parts, 1.0, -2, 3, 1, 2, dark, dark)
	_leg(parts, -1.0, 1, 3, 1, 2, dark, dark)
	_leg(parts, -1.0, -2, -4, 1, 2, dark, dark)
	_leg(parts, 1.0, 1, -4, 1, 2, dark, dark)
	var body: Dictionary[int, Color] = {}
	_box(body, -2, 2, -4, 4, 3, 9, orange)
	_box(body, -1, 2, -3, 2, 1, 7, white)
	_box(body, -1, 2, 4, 2, 2, 1, white)
	_add(parts, "body", 0.0, Vector3(0, 2, 0), body)
	var tail: Dictionary[int, Color] = {}
	_box(tail, -1, 3, -8, 2, 2, 4, orange)
	_box(tail, -1, 3, -10, 2, 2, 2, white)
	_add(parts, "tail", 0.0, Vector3(0, 4, -4), tail)
	var head: Dictionary[int, Color] = {}
	_box(head, -2, 3, 5, 4, 4, 3, orange)
	_box(head, -1, 3, 8, 2, 2, 2, white)
	_box(head, -1, 4, 9, 2, 1, 1, _EYE)
	_dot(head, -2, 5, 7, _EYE)
	_dot(head, 1, 5, 7, _EYE)
	_box(head, -2, 7, 5, 1, 2, 1, orange)
	_box(head, 1, 7, 5, 1, 2, 1, orange)
	_dot(head, -2, 8, 5, dark)
	_dot(head, 1, 8, 5, dark)
	_add(parts, "head", 0.0, Vector3(0, 4, 5), head)
	return parts


# ---------------------------------------------------------------- animales grandes

const _RAINBOW: Array[Color] = [
	Color(0.95, 0.35, 0.40), Color(0.98, 0.62, 0.25), Color(0.98, 0.86, 0.30),
	Color(0.45, 0.80, 0.45), Color(0.35, 0.65, 0.95), Color(0.66, 0.45, 0.90),
]


## Poni (tres pelajes) o unicornio (blanco, con cuerno y crin de colores). La cabeza
## queda a la altura de un adulto y el lomo, a la altura del pecho.
func _build_pony(variant: int, unicorn: bool) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var coat := Color(0.60, 0.40, 0.24)
	var mane := Color(0.20, 0.14, 0.10)
	var hoof := Color(0.18, 0.14, 0.12)
	var muzzle := Color(0.36, 0.25, 0.18)
	var patches: bool = false
	if unicorn:
		coat = Color(0.97, 0.96, 0.98)
		hoof = Color(0.95, 0.72, 0.82)
		muzzle = Color(0.98, 0.84, 0.90)
	elif variant == 1:
		coat = Color(0.95, 0.94, 0.90)
		mane = Color(0.30, 0.24, 0.20)
		muzzle = Color(0.80, 0.70, 0.66)
		patches = true
	elif variant == 2:
		coat = Color(0.90, 0.72, 0.38)
		mane = Color(0.97, 0.94, 0.86)
		muzzle = Color(0.78, 0.58, 0.32)
	_leg(parts, 1.0, -3, 3, 2, 5, coat, hoof)
	_leg(parts, -1.0, 1, 3, 2, 5, coat, hoof)
	_leg(parts, -1.0, -3, -5, 2, 5, coat, hoof)
	_leg(parts, 1.0, 1, -5, 2, 5, coat, hoof)

	var body: Dictionary[int, Color] = {}
	_box(body, -3, 5, -6, 6, 6, 12, coat)
	if patches:
		for y: int in range(5, 11):
			for z: int in range(-6, 6):
				for x: int in range(-3, 3):
					if PropLibrary._hash((x + 8) >> 1, y >> 1, (z + 8) >> 2, 73) < 0.33:
						_dot(body, x, y, z, Color(0.42, 0.28, 0.18))
	_add(parts, "body", 0.0, Vector3(0, 5, 0), body)

	var tail: Dictionary[int, Color] = {}
	for y: int in range(3, 11):
		_box(tail, -1, y, -8, 2, 1, 2, _RAINBOW[y % _RAINBOW.size()] if unicorn else mane)
	_add(parts, "tail", 0.0, Vector3(0, 10, -6), tail)

	# Cuello, cabeza y crin se mueven juntos.
	var head: Dictionary[int, Color] = {}
	_box(head, -2, 8, 4, 4, 6, 3, coat)
	_box(head, -2, 11, 6, 4, 4, 5, coat)
	_box(head, -2, 11, 10, 4, 2, 2, muzzle)
	_dot(head, -2, 13, 8, _EYE)
	_dot(head, 1, 13, 8, _EYE)
	_dot(head, -2, 15, 6, coat)
	_dot(head, 1, 15, 6, coat)
	for y: int in range(9, 16):
		_box(head, -1, y, 3, 2, 1, 1, _RAINBOW[y % _RAINBOW.size()] if unicorn else mane)
	_box(head, -1, 15, 4, 2, 1, 4, _RAINBOW[1] if unicorn else mane)
	if unicorn:
		var gold := Color(0.98, 0.84, 0.35)
		_box(head, -1, 15, 8, 2, 1, 2, gold)
		_box(head, -1, 16, 8, 2, 1, 1, gold)
		_dot(head, -1, 17, 8, gold)
		_dot(head, -1, 18, 8, gold.lightened(0.3))
	_add(parts, "head", 0.0, Vector3(0, 10, 5), head)
	return parts


## Dragón pequeño y simpático: panza clara, ojos grandes, cuernitos, cresta, alas y cola.
func _build_dragon(variant: int) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var skin := Color(0.36, 0.72, 0.40)
	var belly := Color(0.98, 0.90, 0.58)
	var accent := Color(0.96, 0.58, 0.22)
	if variant == 1:
		skin = Color(0.62, 0.45, 0.86)
		belly = Color(0.98, 0.80, 0.88)
		accent = Color(0.35, 0.72, 0.95)
	var claw := Color(0.97, 0.95, 0.88)
	_leg(parts, 1.0, -4, 1, 3, 3, skin, claw)
	_leg(parts, -1.0, 1, 1, 3, 3, skin, claw)
	_leg(parts, -1.0, -4, -5, 3, 3, skin, claw)
	_leg(parts, 1.0, 1, -5, 3, 3, skin, claw)

	# Cuerpo erguido, como sentado.
	var body: Dictionary[int, Color] = {}
	_box(body, -3, 3, -5, 6, 4, 9, skin)
	_box(body, -3, 7, -4, 6, 4, 7, skin)
	_box(body, -2, 3, 4, 4, 7, 1, belly)
	_box(body, -2, 3, -4, 4, 1, 8, belly)
	# Cresta a lo largo del lomo.
	for z: int in range(-4, 2, 2):
		_box(body, -1, 11, z, 2, 1, 1, accent)
	_add(parts, "body", 0.0, Vector3(0, 3, 0), body)

	var tail: Dictionary[int, Color] = {}
	_box(tail, -2, 3, -8, 4, 3, 3, skin)
	_box(tail, -1, 3, -11, 2, 2, 3, skin)
	_box(tail, -1, 3, -13, 2, 1, 2, skin)
	_box(tail, -2, 3, -15, 4, 1, 2, accent)
	_add(parts, "tail", 0.0, Vector3(0, 4, -5), tail)

	for side: int in [-1, 1]:
		var wing: Dictionary[int, Color] = {}
		# Alas amplias: un hueso arriba y la membrana que se angosta hacia abajo.
		var x0: int = -11 if side < 0 else 3
		_box(wing, x0, 12, -3, 8, 1, 2, skin)
		_box(wing, x0, 9, -3, 8, 3, 1, accent)
		_box(wing, x0 + (2 if side < 0 else 0), 7, -3, 6, 2, 1, accent)
		_box(wing, x0 + (4 if side < 0 else 0), 5, -3, 4, 2, 1, accent.darkened(0.1))
		_add(parts, "wing_big", float(side), Vector3(-3 if side < 0 else 3, 11, -2), wing)

	var head: Dictionary[int, Color] = {}
	_box(head, -3, 10, 0, 6, 5, 5, skin)
	_box(head, -2, 10, 5, 4, 3, 2, skin)
	_box(head, -2, 10, 7, 4, 1, 1, belly)
	_dot(head, -2, 12, 6, _EYE)
	_dot(head, 1, 12, 6, _EYE)
	# Ojos grandes: blanco con pupila.
	_box(head, -3, 12, 3, 1, 2, 2, Color(0.98, 0.98, 0.98))
	_box(head, 2, 12, 3, 1, 2, 2, Color(0.98, 0.98, 0.98))
	_dot(head, -3, 12, 4, _EYE)
	_dot(head, 2, 12, 4, _EYE)
	_box(head, -3, 15, 1, 1, 2, 1, claw)
	_box(head, 2, 15, 1, 1, 2, 1, claw)
	_box(head, -1, 15, 0, 2, 1, 3, accent)
	_add(parts, "head", 0.0, Vector3(0, 10, 1), head)
	return parts


# ---------------------------------------------------------------- humanoides

## Aspecto de un avatar: del 0 al 5 las niñas, del 6 al 11 los de la primera versión.
static func _avatar_look(index: int) -> Dictionary:
	match index:
		0:
			return {"child": true, "skin": Color(0.93, 0.74, 0.60), "hair": Color(0.45, 0.28, 0.14),
				"hair_style": "coletas", "tie": Color(0.96, 0.40, 0.62), "shirt": Color(0.98, 0.82, 0.25),
				"pants": Color(0.26, 0.48, 0.86), "shoes": Color(0.86, 0.22, 0.24), "hat": "",
				"shorts": true, "short_sleeves": true, "blush": true}
		1:
			return {"child": true, "skin": Color(0.62, 0.42, 0.30), "hair": Color(0.12, 0.09, 0.08),
				"hair_style": "trenzas", "tie": Color(0.95, 0.25, 0.25), "shirt": Color(0.90, 0.26, 0.30),
				"pants": Color(0.95, 0.94, 0.90), "shoes": Color(0.97, 0.97, 0.95), "hat": "",
				"skirt": Color(0.90, 0.26, 0.30), "short_sleeves": true, "shorts": true, "blush": true}
		2:
			return {"child": true, "skin": Color(0.42, 0.28, 0.20), "hair": Color(0.20, 0.13, 0.09),
				"hair_style": "rizos", "shirt": Color(0.98, 0.58, 0.20), "pants": Color(0.16, 0.62, 0.62),
				"shoes": Color(0.98, 0.85, 0.25), "hat": "", "overalls": true, "blush": true}
		3:
			return {"child": true, "skin": Color(0.97, 0.82, 0.72), "hair": Color(0.96, 0.80, 0.36),
				"hair_style": "largo", "shirt": Color(0.98, 0.62, 0.80), "pants": Color(0.98, 0.80, 0.88),
				"shoes": Color(0.92, 0.42, 0.66), "hat": "corona", "hat_color": Color(0.98, 0.84, 0.30),
				"skirt": Color(0.96, 0.48, 0.72), "long_skirt": true, "blush": true}
		4:
			return {"child": true, "skin": Color(0.88, 0.68, 0.52), "hair": Color(0.86, 0.36, 0.16),
				"hair_style": "coletas", "tie": Color(0.40, 0.80, 0.45), "shirt": Color(0.56, 0.84, 0.50),
				"pants": Color(0.70, 0.56, 0.92), "shoes": Color(0.45, 0.72, 0.40), "hat": "flores",
				"skirt": Color(0.70, 0.56, 0.92), "wings": Color(0.74, 0.93, 0.98), "shorts": true, "blush": true}
		5:
			return {"child": true, "skin": Color(0.80, 0.58, 0.42), "hair": Color(0.25, 0.16, 0.10),
				"hair_style": "corto", "shirt": Color(0.95, 0.95, 0.97), "pants": Color(0.95, 0.95, 0.97),
				"shoes": Color(0.55, 0.58, 0.64), "hat": "escafandra", "hat_color": Color(0.95, 0.95, 0.97),
				"backpack": Color(0.78, 0.80, 0.85), "apron": Color(0.25, 0.50, 0.90), "blush": true}
		_:
			return _adult_look(index - FIRST_ADULT_AVATAR)


static func _adult_look(index: int) -> Dictionary:
	match index:
		0:
			return {"skin": Color(0.87, 0.67, 0.50), "hair": Color(0.35, 0.22, 0.12), "hair_style": "largo",
				"shirt": Color(0.62, 0.66, 0.38), "pants": Color(0.42, 0.30, 0.20), "shoes": Color(0.22, 0.16, 0.12),
				"hat": "sombrero", "hat_color": Color(0.74, 0.62, 0.40), "backpack": Color(0.75, 0.22, 0.18)}
		1:
			return {"skin": Color(0.95, 0.78, 0.64), "hair": Color(0.85, 0.68, 0.30), "hair_style": "corto",
				"shirt": Color(0.80, 0.22, 0.20), "pants": Color(0.24, 0.38, 0.66), "shoes": Color(0.30, 0.20, 0.12),
				"hat": "paja", "hat_color": Color(0.90, 0.78, 0.42), "overalls": true}
		2:
			return {"skin": Color(0.96, 0.84, 0.76), "hair": Color(0.20, 0.14, 0.30), "hair_style": "largo",
				"shirt": Color(0.50, 0.28, 0.70), "pants": Color(0.34, 0.18, 0.50), "shoes": Color(0.20, 0.12, 0.28),
				"hat": "punta", "hat_color": Color(0.38, 0.20, 0.58), "skirt": Color(0.42, 0.22, 0.62), "long_skirt": true}
		3:
			return {"skin": Color(0.52, 0.36, 0.26), "hair": Color(0.12, 0.10, 0.09), "hair_style": "calvo",
				"shirt": Color(0.58, 0.60, 0.64), "pants": Color(0.25, 0.25, 0.28), "shoes": Color(0.14, 0.13, 0.13),
				"hat": "casco", "hat_color": Color(0.66, 0.68, 0.72), "beard": true, "apron": Color(0.42, 0.28, 0.18)}
		4:
			return {"skin": Color(0.80, 0.58, 0.42), "hair": Color(0.82, 0.40, 0.14), "hair_style": "rodete",
				"shirt": Color(0.95, 0.94, 0.90), "pants": Color(0.30, 0.44, 0.72), "shoes": Color(0.36, 0.24, 0.15),
				"hat": "", "skirt": Color(0.24, 0.42, 0.74)}
		_:
			return {"skin": Color(0.72, 0.52, 0.38), "hair": Color(0.15, 0.12, 0.10), "hair_style": "corto",
				"shirt": Color(0.22, 0.48, 0.34), "pants": Color(0.38, 0.38, 0.40), "shoes": Color(0.25, 0.18, 0.12),
				"hat": "capucha", "hat_color": Color(0.18, 0.40, 0.28), "backpack": Color(0.48, 0.34, 0.20)}


static func _villager_look(variant: int) -> Dictionary:
	match variant:
		0:
			return {"skin": Color(0.90, 0.72, 0.56), "hair": Color(0.40, 0.26, 0.14), "hair_style": "corto",
				"shirt": Color(0.58, 0.40, 0.24), "pants": Color(0.36, 0.26, 0.18), "shoes": Color(0.22, 0.16, 0.12),
				"hat": "paja", "hat_color": Color(0.88, 0.76, 0.42), "skirt": Color(0.50, 0.34, 0.20), "long_skirt": true}
		1:
			return {"skin": Color(0.84, 0.66, 0.54), "hair": Color(0.78, 0.78, 0.76), "hair_style": "corto",
				"shirt": Color(0.30, 0.52, 0.32), "pants": Color(0.40, 0.30, 0.20), "shoes": Color(0.20, 0.15, 0.12),
				"hat": "", "beard": true}
		_:
			return {"skin": Color(0.93, 0.76, 0.62), "hair": Color(0.36, 0.20, 0.10), "hair_style": "rodete",
				"shirt": Color(0.95, 0.93, 0.88), "pants": Color(0.60, 0.20, 0.20), "shoes": Color(0.24, 0.16, 0.12),
				"hat": "", "skirt": Color(0.72, 0.20, 0.22), "apron": Color(0.95, 0.93, 0.88)}


## Humanoide: piernas, torso, brazos y cabeza. El adulto mide 14 voxeles (1,75 bloques);
## con "child", 11 voxeles (1,375 bloques) y la misma cabeza, que así queda más grande
## en proporción.
func _build_humanoid(look: Dictionary) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var skin: Color = look["skin"]
	var hair: Color = look["hair"]
	var shirt: Color = look["shirt"]
	var pants: Color = look["pants"]
	var shoes: Color = look["shoes"]
	var hair_style: String = look["hair_style"]
	var hat: String = look["hat"]
	var hat_color: Color = look.get("hat_color", Color.WHITE)
	var tie: Color = look.get("tie", hair)
	var child: bool = look.get("child", false)
	var leg_h: int = 3 if child else 5
	var torso_h: int = 4 if child else 5
	# hip: donde empieza el torso. h: donde empieza la cabeza.
	var hip: int = leg_h
	var h: int = leg_h + torso_h

	for side: int in [-1, 1]:
		var x0: int = -2 if side < 0 else 0
		var leg: Dictionary[int, Color] = {}
		_box(leg, x0, 1, -1, 2, leg_h - 1, 2, pants)
		if look.get("shorts", false):
			_box(leg, x0, 1, -1, 2, leg_h - 2, 2, skin)
		_box(leg, x0, 0, -1, 2, 1, 3, shoes)
		_add(parts, "leg", float(side), Vector3(x0 + 1, hip, 0), leg)

	var torso: Dictionary[int, Color] = {}
	_box(torso, -2, hip, -1, 4, torso_h, 2, shirt)
	_box(torso, -2, hip, -1, 4, 1, 2, pants.darkened(0.2))
	if look.get("overalls", false):
		_box(torso, -2, hip, -1, 4, torso_h - 2, 2, pants)
		_box(torso, -2, h - 2, 0, 1, 2, 1, pants)
		_box(torso, 1, h - 2, 0, 1, 2, 1, pants)
	if look.has("apron"):
		var apron: Color = look["apron"]
		_box(torso, -1, hip, 1, 2, torso_h - 1, 1, apron)
	if look.has("backpack"):
		var pack: Color = look["backpack"]
		_box(torso, -2, hip + 1, -3, 4, torso_h - 1, 2, pack)
		_box(torso, -1, hip + 2, -4, 2, 2, 1, pack.darkened(0.2))
	if look.has("skirt"):
		var skirt: Color = look["skirt"]
		var bottom: int = 1 if look.get("long_skirt", false) else maxi(hip - 2, 1)
		_box(torso, -3, bottom, -2, 6, hip - bottom, 4, skirt)
		_box(torso, -2, hip, -1, 4, 1, 2, skirt.darkened(0.15))
	_add(parts, "body", 0.0, Vector3(0, hip, 0), torso)

	for side: int in [-1, 1]:
		var x0: int = -4 if side < 0 else 2
		var arm: Dictionary[int, Color] = {}
		_box(arm, x0, hip + 1, -1, 2, torso_h - 1, 2, shirt)
		if look.get("short_sleeves", false):
			_box(arm, x0, hip + 1, -1, 2, torso_h - 3, 2, skin)
		_box(arm, x0, hip, -1, 2, 1, 2, skin)
		_add(parts, "arm", float(-side), Vector3(x0 + 1, h, 0), arm)

	# Alas de hada: dos láminas en la espalda que aletean.
	if look.has("wings"):
		var wing_color: Color = look["wings"]
		for side: int in [-1, 1]:
			var wing: Dictionary[int, Color] = {}
			var x0: int = -5 if side < 0 else 1
			_box(wing, x0, hip + 1, -2, 4, torso_h, 1, wing_color)
			_box(wing, x0 + (0 if side < 0 else 1), h + 1, -2, 3, 1, 1, wing_color)
			_box(wing, x0 + (1 if side < 0 else 0), hip, -2, 3, 1, 1, wing_color.darkened(0.12))
			_add(parts, "wing_back", float(side), Vector3(-1 if side < 0 else 1, hip + 2, -2), wing)

	var head: Dictionary[int, Color] = {}
	_box(head, -2, h, -2, 4, 4, 4, skin)
	_dot(head, -2, h + 2, 1, _EYE)
	_dot(head, 1, h + 2, 1, _EYE)
	if look.get("blush", false):
		_dot(head, -2, h + 1, 1, skin.lerp(Color(0.98, 0.45, 0.50), 0.45))
		_dot(head, 1, h + 1, 1, skin.lerp(Color(0.98, 0.45, 0.50), 0.45))
	if hair_style != "calvo":
		_box(head, -2, h + 4, -2, 4, 1, 4, hair)
		_box(head, -2, h + 2, -3, 4, 3, 1, hair)
		_box(head, -3, h + 2, -2, 1, 2, 3, hair)
		_box(head, 2, h + 2, -2, 1, 2, 3, hair)
	match hair_style:
		"largo":
			_box(head, -2, h - 3, -3, 4, 5, 1, hair)
			_box(head, -3, h - 1, -2, 1, 3, 2, hair)
			_box(head, 2, h - 1, -2, 1, 3, 2, hair)
		"rodete":
			_box(head, -1, h + 4, -4, 2, 2, 2, hair)
		"coletas":
			# Dos coletas a los costados, con su gomita de color.
			_box(head, -5, h, -1, 2, 3, 2, hair)
			_box(head, 3, h, -1, 2, 3, 2, hair)
			_box(head, -4, h + 3, -1, 1, 1, 2, tie)
			_box(head, 3, h + 3, -1, 1, 1, 2, tie)
		"trenzas":
			# Dos trenzas finas que caen por delante de los hombros.
			_box(head, -3, h - 3, 0, 1, 5, 1, hair)
			_box(head, 2, h - 3, 0, 1, 5, 1, hair)
			_dot(head, -3, h - 3, 0, tie)
			_dot(head, 2, h - 3, 0, tie)
		"rizos":
			# Pelo con volumen arriba, a los costados y atrás.
			_box(head, -3, h + 3, -3, 6, 2, 5, hair)
			_box(head, -2, h + 5, -2, 4, 1, 3, hair)
			_box(head, -4, h + 1, -2, 1, 3, 3, hair)
			_box(head, 3, h + 1, -2, 1, 3, 3, hair)
			_box(head, -2, h + 1, -4, 4, 3, 1, hair)
	if look.get("beard", false):
		_box(head, -2, h, 2, 4, 1, 1, hair)
		_box(head, -1, h - 1, 2, 2, 1, 1, hair)
		_dot(head, -2, h + 1, 2, hair)
		_dot(head, 1, h + 1, 2, hair)
	match hat:
		"sombrero":
			_box(head, -3, h + 5, -3, 6, 1, 6, hat_color)
			_box(head, -2, h + 6, -2, 4, 2, 4, hat_color)
			_box(head, -2, h + 6, -2, 4, 1, 4, hat_color.darkened(0.35))
		"paja":
			_box(head, -4, h + 5, -4, 8, 1, 8, hat_color)
			_box(head, -2, h + 6, -2, 4, 1, 4, hat_color.darkened(0.08))
		"punta":
			_box(head, -4, h + 5, -4, 8, 1, 8, hat_color)
			_box(head, -2, h + 6, -2, 4, 2, 4, hat_color)
			_box(head, -2, h + 6, -2, 4, 1, 4, Color(0.95, 0.80, 0.25))
			_box(head, -1, h + 8, -1, 2, 2, 2, hat_color)
			_dot(head, -1, h + 10, -1, hat_color)
		"casco":
			_box(head, -3, h + 1, -3, 6, 3, 4, hat_color)
			_box(head, -2, h + 4, -2, 4, 1, 4, hat_color)
			_box(head, -2, h + 4, -3, 4, 1, 5, hat_color.darkened(0.1))
			_box(head, -1, h + 5, -2, 2, 1, 4, Color(0.78, 0.18, 0.16))
			# La cara queda libre.
			_box(head, -2, h + 1, 1, 4, 2, 1, skin)
			_dot(head, -2, h + 2, 1, _EYE)
			_dot(head, 1, h + 2, 1, _EYE)
		"capucha":
			_box(head, -3, h, -3, 6, 5, 5, hat_color)
			_box(head, -2, h + 5, -3, 4, 1, 4, hat_color)
			_box(head, -2, h, -2, 4, 4, 4, skin)
			_box(head, -2, h + 3, -2, 4, 1, 4, hair)
			_box(head, -2, h + 4, -2, 4, 1, 4, hat_color)
			_dot(head, -2, h + 2, 1, _EYE)
			_dot(head, 1, h + 2, 1, _EYE)
		"corona":
			# Aro dorado con puntas y una piedra al frente.
			_box(head, -2, h + 5, -2, 4, 1, 4, hat_color)
			_erase_box(head, -1, h + 5, -1, 2, 1, 2)
			for corner: Vector2i in [Vector2i(-2, -2), Vector2i(1, -2), Vector2i(-2, 1), Vector2i(1, 1)]:
				_dot(head, corner.x, h + 6, corner.y, hat_color)
			_dot(head, -1, h + 5, 1, Color(0.90, 0.20, 0.35))
			_dot(head, 0, h + 5, 1, Color(0.30, 0.60, 0.95))
		"flores":
			# Corona de flores alrededor de la cabeza.
			var petals: Array[Color] = [Color(0.98, 0.55, 0.75), Color(0.98, 0.88, 0.35), Color(0.98, 0.98, 0.95)]
			var n: int = 0
			for z: int in range(-3, 3):
				for x: int in range(-3, 3):
					if x == -3 or x == 2 or z == -3 or z == 2:
						_dot(head, x, h + 4, z, petals[n % 3])
						n += 1
		"escafandra":
			# Casco redondo con el frente abierto: se ve la cara.
			_box(head, -3, h - 1, -3, 6, 7, 6, hat_color)
			_box(head, -2, h + 6, -2, 4, 1, 4, hat_color)
			_erase_box(head, -2, h, 2, 4, 4, 1)
			_box(head, -2, h, -2, 4, 4, 4, skin)
			_box(head, -2, h + 3, -2, 4, 1, 4, hair)
			_dot(head, -2, h + 2, 1, _EYE)
			_dot(head, 1, h + 2, 1, _EYE)
			_dot(head, -2, h + 1, 1, skin.lerp(Color(0.98, 0.45, 0.50), 0.45))
			_dot(head, 1, h + 1, 1, skin.lerp(Color(0.98, 0.45, 0.50), 0.45))
			_box(head, -3, h + 2, -1, 1, 1, 2, Color(0.25, 0.50, 0.90))
			_box(head, 2, h + 2, -1, 1, 1, 2, Color(0.25, 0.50, 0.90))
	_add(parts, "head", 0.0, Vector3(0, h, 0), head)
	return parts
