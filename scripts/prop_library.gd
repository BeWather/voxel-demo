class_name PropLibrary
extends RefCounted
## Biblioteca de props: modelos mini-voxel (1/8 de bloque) convertidos en ArrayMesh con color
## por vértice. Arranca con los modelos procedurales incorporados y les superpone los objetos
## guardados en `user://props/`: un archivo con la clave de un incorporado lo reemplaza y
## cualquier otra clave se agrega al final como objeto nuevo.
##
## El id de un prop en ejecución es su índice en la biblioteca; los archivos de mapa guardan
## la clave de texto, que es estable.

## Se emite cuando cambian los modelos de un prop o se agrega uno nuevo.
signal prop_changed(id: int)

const VOXEL: float = 0.125
## Máximo de variantes por prop. Fija la cuenta de la clave de malla: id * MAX_VARIANTS + variante.
const MAX_VARIANTS: int = 8
## Variantes que genera cada modelo procedural incorporado.
const BUILTIN_VARIANTS: int = 3

## Volumen de edición de un modelo, en mini-voxeles. El origen es el centro de la base.
const MIN_XZ: int = -24
const MAX_XZ: int = 23
const MAX_Y: int = 47

## Ids de los props incorporados: siempre ocupan los primeros lugares, en este orden.
const OAK: int = 0
const PINE: int = 1
const BUSH: int = 2
const FLOWER_RED: int = 3
const FLOWER_YELLOW: int = 4
const FLOWER_BLUE: int = 5
const TALL_GRASS: int = 6
const ROCK: int = 7
const MUSHROOM: int = 8
const LOG: int = 9
const BUILTIN_COUNT: int = 10

## Claves estables usadas en los archivos de mapa y de objeto.
const BUILTIN_KEYS: Array[String] = [
	"roble", "pino", "arbusto", "flor_roja", "flor_amarilla", "flor_azul",
	"pasto_alto", "roca", "hongo", "tronco",
]
const BUILTIN_NAMES: Array[String] = [
	"Roble", "Pino", "Arbusto", "Flor roja", "Flor amarilla", "Flor azul",
	"Pasto alto", "Roca", "Hongo", "Tronco caído",
]
## Caja de colisión en modo juego (mitad del ancho y alto, en bloques), solo para los
## incorporados. 0 = no bloquea el paso.
const BLOCK_HALF: Array[float] = [0.22, 0.20, 0.0, 0.0, 0.0, 0.0, 0.0, 0.38, 0.0, 0.45]
const BLOCK_HEIGHT: Array[float] = [3.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.55, 0.0, 0.5]

## Caja para seleccionar props con el mouse: mínimos y proporción del ancho del modelo.
## No se usa el ancho completo para que la copa de un árbol no tape a los props vecinos.
const MIN_PICK_HEIGHT: float = 0.5
const MIN_PICK_RADIUS: float = 0.3
const MAX_PICK_RADIUS: float = 1.0
const PICK_RADIUS_FACTOR: float = 0.7

const _BARK: Array[Color] = [Color(0.42, 0.29, 0.17), Color(0.36, 0.25, 0.14), Color(0.47, 0.33, 0.20)]
const _OAK_LEAVES: Array[Color] = [
	Color(0.20, 0.47, 0.16), Color(0.25, 0.55, 0.20), Color(0.31, 0.62, 0.24), Color(0.17, 0.42, 0.15),
]
const _PINE_LEAVES: Array[Color] = [Color(0.11, 0.34, 0.21), Color(0.14, 0.40, 0.24), Color(0.09, 0.29, 0.18)]
const _BUSH_LEAVES: Array[Color] = [Color(0.27, 0.56, 0.22), Color(0.33, 0.63, 0.26), Color(0.22, 0.49, 0.19)]
const _GRASS_BLADES: Array[Color] = [Color(0.38, 0.68, 0.26), Color(0.46, 0.75, 0.30), Color(0.31, 0.60, 0.22)]
const _ROCK_TONES: Array[Color] = [Color(0.55, 0.56, 0.59), Color(0.49, 0.50, 0.53), Color(0.62, 0.63, 0.65)]
const _STEM: Color = Color(0.25, 0.55, 0.20)
const _MOSS: Color = Color(0.36, 0.58, 0.24)


## Definición de un prop. Los datos derivados se recalculan con cada cambio de modelo.
class PropDef extends RefCounted:
	var key: String = ""
	var display_name: String = ""
	var builtin: bool = false
	## Incorporado reemplazado por un archivo de `user://props/`.
	var overridden: bool = false
	## Cada elemento es un modelo Dictionary[int, Color] (clave: voxel_key).
	var variants: Array[Dictionary] = []
	var swatch: Color = Color.GRAY
	var pick_height: float = 0.5
	var pick_radius: float = 0.3


var material: StandardMaterial3D
## Carpeta de los objetos guardados. Vacía = solo los incorporados, sin leer ni escribir disco.
var props_dir: String = ""
## Archivos que no se pudieron cargar al iniciar (un mensaje por archivo).
var load_warnings: Array[String] = []

var _defs: Array[PropDef] = []
var _ids: Dictionary[String, int] = {}
var _meshes: Dictionary[int, ArrayMesh] = {}


func _init(p_props_dir: String = PropIO.PROPS_DIR) -> void:
	material = ChunkMesher.make_opaque_material()
	props_dir = p_props_dir
	for id: int in BUILTIN_COUNT:
		var def := PropDef.new()
		def.key = BUILTIN_KEYS[id]
		def.display_name = BUILTIN_NAMES[id]
		def.builtin = true
		def.variants = _build_builtin_variants(id)
		_ids[def.key] = id
		_defs.append(def)
		_refresh(id)
	_load_user_props()


# ---------------------------------------------------------------- consulta

func count() -> int:
	return _defs.size()


func is_valid(id: int) -> bool:
	return id >= 0 and id < _defs.size()


## Devuelve -1 si la clave no existe.
func key_to_id(key: String) -> int:
	return _ids.get(key, -1)


func has_key(key: String) -> bool:
	return _ids.has(key)


func prop_key(id: int) -> String:
	return _defs[id].key


func prop_name(id: int) -> String:
	return _defs[id].display_name if is_valid(id) else "?"


func variant_count(id: int) -> int:
	return _defs[id].variants.size()


## Variante al azar entre las que el prop tiene de verdad.
func random_variant(id: int) -> int:
	return randi() % variant_count(id)


## Color representativo para la paleta de la interfaz.
func swatch(id: int) -> Color:
	return _defs[id].swatch


## Caja aproximada (en bloques) para seleccionar el prop con el mouse.
func pick_height(id: int) -> float:
	return _defs[id].pick_height


func pick_radius(id: int) -> float:
	return _defs[id].pick_radius


func is_builtin(id: int) -> bool:
	return _defs[id].builtin


## ¿Es un incorporado reemplazado por un archivo? (se puede restaurar el original).
func is_overridden(id: int) -> bool:
	return _defs[id].overridden


## Malla de una variante. Una variante fuera de rango (por ejemplo, un prop colocado antes
## de quitarle variantes al objeto) usa la última disponible.
func get_mesh(id: int, variant: int) -> ArrayMesh:
	var v: int = clampi(variant, 0, variant_count(id) - 1)
	return _meshes[id * MAX_VARIANTS + v]


## Copia del modelo de una variante.
func get_voxels(id: int, variant: int) -> Dictionary[int, Color]:
	var vox: Dictionary[int, Color] = _defs[id].variants[clampi(variant, 0, variant_count(id) - 1)]
	return vox.duplicate()


## Copia de todas las variantes de un prop.
func get_variants(id: int) -> Array[Dictionary]:
	return copy_variants(_defs[id].variants)


static func copy_variants(variants: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in variants:
		var vox: Dictionary[int, Color] = entry
		out.append(vox.duplicate())
	return out


# ---------------------------------------------------------------- cambios

## Guarda un objeto en `props_dir` y lo deja disponible en la biblioteca: si la clave ya
## existe reemplaza sus variantes (y su nombre); si no, lo agrega al final.
## Devuelve {"ok": bool, "error": String, "id": int}.
func save_prop(key: String, display_name: String, variants: Array[Dictionary]) -> Dictionary:
	var problem: String = PropIO.validate(key, display_name, variants)
	if not problem.is_empty():
		return {"ok": false, "error": problem, "id": -1}
	# Los colores se guardan con 8 bits por canal: en memoria queda lo mismo que en el archivo.
	var stored: Array[Dictionary] = PropIO.quantize_variants(variants)
	if not props_dir.is_empty():
		PropIO.ensure_dir(props_dir)
		var error: String = PropIO.save_file(PropIO.path_for(props_dir, key), key, display_name, stored)
		if not error.is_empty():
			return {"ok": false, "error": error, "id": -1}
	var id: int = _apply(key, display_name, stored)
	prop_changed.emit(id)
	return {"ok": true, "error": "", "id": id}


## Borra el archivo que reemplaza a un incorporado y vuelve al modelo procedural.
## Devuelve "" si salió bien o un mensaje de error.
func restore_builtin(id: int) -> String:
	if not is_valid(id) or not _defs[id].builtin:
		return "Solo se pueden restaurar los objetos incorporados."
	var def: PropDef = _defs[id]
	if not props_dir.is_empty():
		var path: String = PropIO.path_for(props_dir, def.key)
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			return "No se pudo borrar %s." % path
	def.display_name = BUILTIN_NAMES[id]
	def.variants = _build_builtin_variants(id)
	def.overridden = false
	_refresh(id)
	prop_changed.emit(id)
	return ""


## Reemplaza o agrega una definición en memoria. Devuelve su id.
func _apply(key: String, display_name: String, variants: Array[Dictionary]) -> int:
	var id: int = key_to_id(key)
	var def: PropDef
	if id >= 0:
		def = _defs[id]
		def.overridden = def.builtin
	else:
		def = PropDef.new()
		def.key = key
		id = _defs.size()
		_ids[key] = id
		_defs.append(def)
	def.display_name = display_name
	def.variants = variants
	_refresh(id)
	return id


func _load_user_props() -> void:
	if props_dir.is_empty():
		return
	for path: String in PropIO.list_files(props_dir):
		var result: Dictionary = PropIO.load_file(path)
		var error: String = result["error"]
		var key: String = result["key"]
		if result["ok"] and key != path.get_file().get_basename():
			error = "la clave «%s» no coincide con el nombre del archivo." % key
		if not error.is_empty():
			var message: String = "Objeto omitido (%s): %s" % [path.get_file(), error]
			load_warnings.append(message)
			push_warning(message)
			continue
		var display_name: String = result["name"]
		var variants: Array[Dictionary] = result["variants"]
		_apply(key, display_name, variants)


## Recalcula las mallas y los datos derivados de un prop.
func _refresh(id: int) -> void:
	var def: PropDef = _defs[id]
	var top: int = 0
	var reach: int = 0
	for variant: int in MAX_VARIANTS:
		_meshes.erase(id * MAX_VARIANTS + variant)
	for variant: int in def.variants.size():
		var vox: Dictionary[int, Color] = def.variants[variant]
		_meshes[id * MAX_VARIANTS + variant] = mesh_from_voxels(vox, material)
		for key: int in vox:
			var cell: Vector3i = voxel_cell(key)
			top = maxi(top, cell.y + 1)
			reach = maxi(reach, maxi(maxi(cell.x + 1, -cell.x), maxi(cell.z + 1, -cell.z)))
	def.swatch = swatch_from_variants(def.variants)
	def.pick_height = maxf(top * VOXEL, MIN_PICK_HEIGHT)
	def.pick_radius = clampf(reach * VOXEL * PICK_RADIUS_FACTOR, MIN_PICK_RADIUS, MAX_PICK_RADIUS)


## Color representativo: el tono dominante del modelo visto desde arriba (el voxel más alto
## de cada columna). Así una flor se identifica por sus pétalos y no por el tallo.
static func swatch_from_variants(variants: Array[Dictionary]) -> Color:
	var counts: Dictionary[int, int] = {}
	var sums: Dictionary[int, Color] = {}
	for entry: Dictionary in variants:
		var vox: Dictionary[int, Color] = entry
		var tops: Dictionary[int, int] = {}
		for key: int in vox:
			var column: int = key & 0xFF00FF
			if not tops.has(column) or ((key >> 8) & 0xFF) > ((tops[column] >> 8) & 0xFF):
				tops[column] = key
		for column: int in tops:
			var color: Color = vox[tops[column]]
			# Cubetas gruesas (3 bits por canal) para agrupar tonos parecidos.
			var bucket: int = (color.r8 >> 5) | ((color.g8 >> 5) << 3) | ((color.b8 >> 5) << 6)
			counts[bucket] = counts.get(bucket, 0) + 1
			sums[bucket] = sums.get(bucket, Color(0.0, 0.0, 0.0, 0.0)) + color
	var best: int = -1
	for bucket: int in counts:
		if best < 0 or counts[bucket] > counts[best] or (counts[bucket] == counts[best] and bucket < best):
			best = bucket
	if best < 0:
		return Color.GRAY
	var total: Color = sums[best] / float(counts[best])
	return Color(total.r, total.g, total.b, 1.0)


# ---------------------------------------------------------------- modelos

## Variantes procedurales de un incorporado. Las semillas son fijas: los mapas existentes y
## la pradera generada se ven siempre igual.
func _build_builtin_variants(id: int) -> Array[Dictionary]:
	var variants: Array[Dictionary] = []
	for variant: int in BUILTIN_VARIANTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (id + 1) + 104729 * (variant + 1)
		variants.append(_build_model(id, rng))
	return variants


func _build_model(id: int, rng: RandomNumberGenerator) -> Dictionary[int, Color]:
	match id:
		OAK:
			return _build_oak(rng)
		PINE:
			return _build_pine(rng)
		BUSH:
			return _build_bush(rng)
		FLOWER_RED:
			return _build_flower(rng, Color(0.88, 0.18, 0.20), Color(0.98, 0.85, 0.25))
		FLOWER_YELLOW:
			return _build_flower(rng, Color(0.98, 0.84, 0.20), Color(0.90, 0.50, 0.12))
		FLOWER_BLUE:
			return _build_flower(rng, Color(0.30, 0.48, 0.95), Color(0.98, 0.92, 0.55))
		TALL_GRASS:
			return _build_tall_grass(rng)
		ROCK:
			return _build_rock(rng)
		MUSHROOM:
			return _build_mushroom(rng)
		_:
			return _build_log(rng)


## Clave de un voxel dentro de un modelo (coordenadas de -128 a 127).
static func voxel_key(x: int, y: int, z: int) -> int:
	return _key(x, y, z)


static func voxel_cell(key: int) -> Vector3i:
	return Vector3i((key & 0xFF) - 128, ((key >> 8) & 0xFF) - 128, ((key >> 16) & 0xFF) - 128)


## ¿El voxel cae dentro del volumen de edición?
static func in_volume(x: int, y: int, z: int) -> bool:
	return x >= MIN_XZ and x <= MAX_XZ and z >= MIN_XZ and z <= MAX_XZ and y >= 0 and y <= MAX_Y


static func _key(x: int, y: int, z: int) -> int:
	return (x + 128) | ((y + 128) << 8) | ((z + 128) << 16)


static func _hash(x: int, y: int, z: int, salt: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (salt * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


static func _put(vox: Dictionary[int, Color], x: int, y: int, z: int, color: Color) -> void:
	if y < 0:
		return
	vox[_key(x, y, z)] = color


## Elipsoide con borde irregular. `accent` reemplaza el color con probabilidad `accent_chance`.
static func _blob(vox: Dictionary[int, Color], center: Vector3, radii: Vector3, palette: Array[Color],
		salt: int, rough: float, accent: Color = Color.BLACK, accent_chance: float = 0.0) -> void:
	var x0: int = floori(center.x - radii.x - 1.0)
	var x1: int = ceili(center.x + radii.x + 1.0)
	var y0: int = maxi(floori(center.y - radii.y - 1.0), 0)
	var y1: int = ceili(center.y + radii.y + 1.0)
	var z0: int = floori(center.z - radii.z - 1.0)
	var z1: int = ceili(center.z + radii.z + 1.0)
	for y: int in range(y0, y1 + 1):
		for z: int in range(z0, z1 + 1):
			for x: int in range(x0, x1 + 1):
				var dx: float = (x + 0.5 - center.x) / radii.x
				var dy: float = (y + 0.5 - center.y) / radii.y
				var dz: float = (z + 0.5 - center.z) / radii.z
				var d: float = dx * dx + dy * dy + dz * dz
				if d >= 1.0 + (_hash(x, y, z, salt) - 0.5) * rough:
					continue
				var pick: float = _hash(x, y, z, salt + 17)
				var color: Color = palette[mini(int(pick * palette.size()), palette.size() - 1)]
				if accent_chance > 0.0 and _hash(x, y, z, salt + 31) < accent_chance:
					color = accent
				_put(vox, x, y, z, color)


func _build_oak(rng: RandomNumberGenerator) -> Dictionary[int, Color]:
	var vox: Dictionary[int, Color] = {}
	var salt: int = rng.randi_range(1, 60000)
	var trunk_h: int = rng.randi_range(11, 14)
	# Tronco de 2x2 que entra en la copa.
	for y: int in trunk_h + 4:
		for z: int in range(-1, 1):
			for x: int in range(-1, 1):
				_put(vox, x, y, z, _BARK[int(_hash(x, y, z, salt) * 2.99)])
	# Base ensanchada (raíces).
	for i: int in range(-1, 1):
		_put(vox, -2, 0, i, _BARK[1])
		_put(vox, 1, 0, i, _BARK[1])
		_put(vox, i, 0, -2, _BARK[1])
		_put(vox, i, 0, 1, _BARK[1])
	# Copa: un elipsoide principal más varios bultos.
	var rx: float = rng.randf_range(8.0, 9.5)
	var ry: float = rng.randf_range(6.0, 7.5)
	var cy: float = trunk_h + 6.0
	_blob(vox, Vector3(0.0, cy, 0.0), Vector3(rx, ry, rx), _OAK_LEAVES, salt, 0.30)
	for i: int in 4:
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(4.0, 6.0)
		var r: float = rng.randf_range(4.5, 6.0)
		var c := Vector3(cos(ang) * dist, cy + rng.randf_range(-2.5, 3.0), sin(ang) * dist)
		_blob(vox, c, Vector3(r, r * 0.85, r), _OAK_LEAVES, salt + i + 1, 0.35)
	return vox


func _build_pine(rng: RandomNumberGenerator) -> Dictionary[int, Color]:
	var vox: Dictionary[int, Color] = {}
	var salt: int = rng.randi_range(1, 60000)
	var height: int = rng.randi_range(27, 31)
	var skirt: int = rng.randi_range(4, 6)
	var tier: float = rng.randf_range(5.5, 7.0)
	var base_r: float = rng.randf_range(7.5, 9.0)
	for y: int in height - 3:
		for z: int in range(-1, 1):
			for x: int in range(-1, 1):
				_put(vox, x, y, z, _BARK[1] if _hash(x, y, z, salt) < 0.6 else _BARK[0])
	# Copa cónica escalonada en pisos.
	for y: int in range(skirt, height):
		var f: float = float(y - skirt) / float(height - skirt)
		var envelope: float = base_r * (1.0 - f) + 0.9
		var saw: float = fposmod(float(y - skirt), tier) / tier
		var radius: float = envelope * (1.0 - 0.45 * saw)
		var reach: int = ceili(radius + 1.0)
		for z: int in range(-reach, reach):
			for x: int in range(-reach, reach):
				var d: float = sqrt((x + 0.5) * (x + 0.5) + (z + 0.5) * (z + 0.5))
				if d < radius + (_hash(x, y, z, salt) - 0.5) * 1.3:
					_put(vox, x, y, z, _PINE_LEAVES[int(_hash(x, y, z, salt + 5) * 2.99)])
	return vox


func _build_bush(rng: RandomNumberGenerator) -> Dictionary[int, Color]:
	var vox: Dictionary[int, Color] = {}
	var salt: int = rng.randi_range(1, 60000)
	var berries: float = 0.05 if rng.randf() < 0.67 else 0.0
	var berry_color := Color(0.82, 0.16, 0.22) if rng.randf() < 0.5 else Color(0.35, 0.30, 0.75)
	var r: float = rng.randf_range(3.6, 4.4)
	_blob(vox, Vector3(0.0, 2.4, 0.0), Vector3(r, 3.2, r), _BUSH_LEAVES, salt, 0.4, berry_color, berries)
	var ang: float = rng.randf_range(0.0, TAU)
	_blob(vox, Vector3(cos(ang) * 2.2, 2.0, sin(ang) * 2.2), Vector3(2.8, 2.6, 2.8), _BUSH_LEAVES,
			salt + 3, 0.4, berry_color, berries)
	return vox


func _build_flower(rng: RandomNumberGenerator, petal: Color, heart: Color) -> Dictionary[int, Color]:
	var vox: Dictionary[int, Color] = {}
	var flowers: int = rng.randi_range(1, 3)
	for i: int in flowers:
		var ox: int = 0 if i == 0 else rng.randi_range(-3, 2)
		var oz: int = 0 if i == 0 else rng.randi_range(-3, 2)
		var h: int = rng.randi_range(3, 5)
		for y: int in h:
			_put(vox, ox, y, oz, _STEM)
		# Una hoja lateral.
		var side: int = 1 if rng.randf() < 0.5 else -1
		if rng.randf() < 0.5:
			_put(vox, ox + side, 1, oz, _STEM.lightened(0.12))
		else:
			_put(vox, ox, 1, oz + side, _STEM.lightened(0.12))
		# Cabeza: centro y cuatro pétalos.
		_put(vox, ox, h, oz, heart)
		_put(vox, ox + 1, h, oz, petal)
		_put(vox, ox - 1, h, oz, petal)
		_put(vox, ox, h, oz + 1, petal)
		_put(vox, ox, h, oz - 1, petal)
		if rng.randf() < 0.4:
			_put(vox, ox, h + 1, oz, petal.lightened(0.2))
	return vox


func _build_tall_grass(rng: RandomNumberGenerator) -> Dictionary[int, Color]:
	var vox: Dictionary[int, Color] = {}
	var blades: int = rng.randi_range(9, 14)
	for i: int in blades:
		var x: int = rng.randi_range(-3, 2)
		var z: int = rng.randi_range(-3, 2)
		var h: int = rng.randi_range(2, 6)
		var color: Color = _GRASS_BLADES[rng.randi_range(0, 2)]
		for y: int in h:
			_put(vox, x, y, z, color.darkened(0.12 * (1.0 - float(y) / float(h))))
		# Algunas hojas se doblan en la punta.
		if h > 3 and rng.randf() < 0.5:
			var lean_x: int = rng.randi_range(-1, 1)
			var lean_z: int = 0 if lean_x != 0 else (1 if rng.randf() < 0.5 else -1)
			_put(vox, x + lean_x, h - 1, z + lean_z, color.lightened(0.1))
	return vox


func _build_rock(rng: RandomNumberGenerator) -> Dictionary[int, Color]:
	var vox: Dictionary[int, Color] = {}
	var salt: int = rng.randi_range(1, 60000)
	var moss: float = 0.07 if rng.randf() < 0.5 else 0.0
	var rx: float = rng.randf_range(3.0, 4.2)
	var ry: float = rng.randf_range(2.6, 3.6)
	var rz: float = rng.randf_range(3.0, 4.2)
	_blob(vox, Vector3(0.0, ry * 0.5, 0.0), Vector3(rx, ry, rz), _ROCK_TONES, salt, 0.35, _MOSS, moss)
	var ang: float = rng.randf_range(0.0, TAU)
	_blob(vox, Vector3(cos(ang) * 2.4, 0.8, sin(ang) * 2.4), Vector3(2.3, 2.0, 2.3), _ROCK_TONES,
			salt + 9, 0.35, _MOSS, moss)
	return vox


func _build_mushroom(rng: RandomNumberGenerator) -> Dictionary[int, Color]:
	var vox: Dictionary[int, Color] = {}
	var salt: int = rng.randi_range(1, 60000)
	var mushrooms: int = rng.randi_range(1, 2)
	var cap: Color = Color(0.82, 0.18, 0.15) if rng.randf() < 0.67 else Color(0.62, 0.42, 0.24)
	var stem := Color(0.93, 0.90, 0.80)
	var spot := Color(0.97, 0.96, 0.92)
	for i: int in mushrooms:
		var ox: int = 0 if i == 0 else rng.randi_range(2, 3) * (1 if rng.randf() < 0.5 else -1)
		var oz: int = 0 if i == 0 else rng.randi_range(-3, 2)
		var h: int = rng.randi_range(2, 3) if i == 0 else 1
		var reach: int = 2 if i == 0 else 1
		for y: int in h:
			_put(vox, ox, y, oz, stem)
		for dz: int in range(-reach, reach + 1):
			for dx: int in range(-reach, reach + 1):
				if absi(dx) + absi(dz) > reach + 1:
					continue
				_put(vox, ox + dx, h, oz + dz, cap.darkened(0.12))
				if absi(dx) < reach and absi(dz) < reach:
					var top: Color = spot if _hash(ox + dx, h, oz + dz, salt) < 0.22 else cap
					_put(vox, ox + dx, h + 1, oz + dz, top)
	return vox


func _build_log(rng: RandomNumberGenerator) -> Dictionary[int, Color]:
	var vox: Dictionary[int, Color] = {}
	var salt: int = rng.randi_range(1, 60000)
	var half: int = rng.randi_range(5, 7)
	var moss: float = rng.randf_range(0.0, 0.35)
	var ring := Color(0.80, 0.66, 0.44)
	for x: int in range(-half, half):
		var is_end: bool = x == -half or x == half - 1
		for y: int in 4:
			for z: int in range(-2, 2):
				var dy: float = y + 0.5 - 2.0
				var dz: float = z + 0.5
				if dy * dy + dz * dz > 4.0:
					continue
				var color: Color = _BARK[int(_hash(x, y, z, salt) * 2.99)]
				if is_end:
					color = ring.darkened(0.25) if dy * dy + dz * dz < 1.0 else ring
				elif y == 3 and _hash(x, y, z, salt + 3) < moss:
					color = _MOSS
				_put(vox, x, y, z, color)
	# Muñón de una rama.
	var stub_x: int = rng.randi_range(-half + 2, half - 3)
	_put(vox, stub_x, 4, 0, _BARK[0])
	if rng.randf() < 0.5:
		_put(vox, stub_x, 5, 0, _BARK[2])
	return vox


# ---------------------------------------------------------------- mallado

## Convierte el modelo en malla dibujando solo las caras expuestas, con oclusión ambiental.
## El origen queda en el centro de la base: el modelo gira alrededor del eje Y de su celda.
## `pivot` (en mini-voxeles) desplaza el origen; lo usan las partes articuladas de los personajes.
static func mesh_from_voxels(vox: Dictionary[int, Color], mesh_material: Material,
		pivot: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var ao: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])

	for key: int in vox:
		var x: int = (key & 0xFF) - 128
		var y: int = ((key >> 8) & 0xFF) - 128
		var z: int = ((key >> 16) & 0xFF) - 128
		var base_col: Color = vox[key]
		var tint: float = 0.92 + 0.16 * _hash(x, y, z, 99)
		var center := Vector3(x + 0.5, y + 0.5, z + 0.5) - pivot
		for f: int in 6:
			var n: Vector3i = ChunkMesher.FACE_NORMAL[f]
			var nx: int = x + n.x
			var ny: int = y + n.y
			var nz: int = z + n.z
			if vox.has(_key(nx, ny, nz)):
				continue
			var u: Vector3i = ChunkMesher.FACE_U[f]
			var v: Vector3i = ChunkMesher.FACE_V[f]
			var start: int = verts.size()
			for k: int in 4:
				var su: int = ChunkMesher.CORNER_U[k]
				var sv: int = ChunkMesher.CORNER_V[k]
				var s1: int = 1 if vox.has(_key(nx + su * u.x, ny + su * u.y, nz + su * u.z)) else 0
				var s2: int = 1 if vox.has(_key(nx + sv * v.x, ny + sv * v.y, nz + sv * v.z)) else 0
				var level: int = 0
				if s1 == 0 or s2 == 0:
					var c: int = 1 if vox.has(_key(nx + su * u.x + sv * v.x,
							ny + su * u.y + sv * v.y, nz + su * u.z + sv * v.z)) else 0
					level = 3 - (s1 + s2 + c)
				ao[k] = level
				var b: float = tint * ChunkMesher.AO_LEVELS[level]
				var corner: Vector3 = (Vector3(n) + Vector3(u) * float(su) + Vector3(v) * float(sv)) * 0.5
				verts.append((center + corner) * VOXEL)
				norms.append(Vector3(n))
				cols.append(Color(base_col.r * b, base_col.g * b, base_col.b * b, 1.0))
			if ao[0] + ao[2] < ao[1] + ao[3]:
				idx.append(start + 1)
				idx.append(start + 3)
				idx.append(start + 2)
				idx.append(start + 1)
				idx.append(start)
				idx.append(start + 3)
			else:
				idx.append(start)
				idx.append(start + 2)
				idx.append(start + 1)
				idx.append(start)
				idx.append(start + 3)
				idx.append(start + 2)

	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mesh_material)
	return mesh
