class_name MapIO
extends RefCounted
## Guardado y carga de mapas en JSON.
## Los bloques van comprimidos por chunk como pares [id, cantidad, id, cantidad, ...].

const FORMAT: String = "editor_voxel_mapa"
## Versión que se escribe. La versión 1 (sin criaturas) todavía se puede cargar.
const VERSION: int = 2
const OLDEST_VERSION: int = 1
const MAPS_DIR: String = "user://maps"
const MAX_SIZE: int = 512


static func ensure_maps_dir() -> void:
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)


## Convierte el mundo y sus props en un diccionario listo para JSON.
## `entities` es opcional; sin ella el mapa se guarda sin criaturas.
static func serialize(world: VoxelWorld, props: PropLayer, map_seed: int,
		entities: EntityLayer = null) -> Dictionary:
	var chunk_list: Array = []
	var keys: Array = world.chunks.keys()
	keys.sort()
	for key: Vector3i in keys:
		var data: PackedByteArray = world.chunks[key]
		if data.count(0) == data.size():
			continue  # Los chunks vacíos no se guardan.
		chunk_list.append({"pos": [key.x, key.y, key.z], "rle": _rle_encode(data)})

	var prop_list: Array = []
	var cells: Array = props.props.keys()
	cells.sort()
	for cell: Vector3i in cells:
		var p: Dictionary = props.props[cell]
		var id: int = p["id"]
		var variant: int = p["variant"]
		var rot: int = p["rot"]
		prop_list.append({
			"cell": [cell.x, cell.y, cell.z],
			"id": props.library.prop_key(id),
			"variant": variant,
			"rot": rot,
		})

	var entity_list: Array = []
	if entities != null:
		var entity_cells: Array = entities.entities.keys()
		entity_cells.sort()
		for cell: Vector3i in entity_cells:
			var e: Dictionary = entities.entities[cell]
			var type: int = e["type"]
			var variant: int = e["variant"]
			var rot: int = e["rot"]
			var npc_name: String = e["name"]
			var lines: Array = e["lines"]
			entity_list.append({
				"cell": [cell.x, cell.y, cell.z],
				"type": CharacterLibrary.ENTITY_KEYS[type],
				"variant": variant,
				"rot": rot,
				"name": npc_name,
				"lines": lines.duplicate(),
			})

	return {
		"format": FORMAT,
		"version": VERSION,
		"size": [world.size_x, world.size_y, world.size_z],
		"seed": map_seed,
		"chunks": chunk_list,
		"props": prop_list,
		"entities": entity_list,
	}


## Valida `data` y, solo si todo es correcto, reemplaza el mundo y los props.
## Un prop cuyo objeto no está en la biblioteca se omite, y una variante que el objeto ya no
## tiene se ajusta a la última; las dos cosas se informan en "warning".
## Devuelve {"ok": bool, "error": String, "seed": int, "warning": String}.
static func deserialize(data: Variant, world: VoxelWorld, props: PropLayer,
		entities: EntityLayer = null) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return _fail("El archivo no contiene un mapa.")
	var d: Dictionary = data
	if str(d.get("format", "")) != FORMAT:
		return _fail("El archivo no es un mapa del Editor Voxel.")
	var version: Variant = d.get("version")
	if not _is_number(version) or int(version) < OLDEST_VERSION or int(version) > VERSION:
		return _fail("Versión de mapa no soportada: %s (este editor lee de la %d a la %d)." % [
				str(version), OLDEST_VERSION, VERSION])

	var size_v: Vector3i = _to_vec3i(d.get("size"))
	if size_v.x < 1 or size_v.y < 1 or size_v.z < 1 \
			or size_v.x > MAX_SIZE or size_v.y > MAX_SIZE or size_v.z > MAX_SIZE:
		return _fail("Tamaño de mapa inválido.")

	var raw_chunks: Variant = d.get("chunks")
	if typeof(raw_chunks) != TYPE_ARRAY:
		return _fail("Falta la lista de chunks.")
	var new_chunks: Dictionary[Vector3i, PackedByteArray] = {}
	var chunk_array: Array = raw_chunks
	for entry: Variant in chunk_array:
		if typeof(entry) != TYPE_DICTIONARY:
			return _fail("Chunk mal formado.")
		var chunk: Dictionary = entry
		var pos: Vector3i = _to_vec3i(chunk.get("pos"), Vector3i(-1, -1, -1))
		var origin: Vector3i = pos * VoxelWorld.CHUNK_SIZE
		if pos.x < 0 or pos.y < 0 or pos.z < 0 \
				or origin.x >= size_v.x or origin.y >= size_v.y or origin.z >= size_v.z:
			return _fail("Chunk fuera del mapa.")
		var bytes: PackedByteArray = _rle_decode(chunk.get("rle"))
		if bytes.size() != VoxelWorld.CHUNK_VOLUME:
			return _fail("Datos de chunk corruptos.")
		new_chunks[pos] = bytes

	var raw_props: Variant = d.get("props", [])
	if typeof(raw_props) != TYPE_ARRAY:
		return _fail("Lista de props mal formada.")
	var new_props: Dictionary[Vector3i, Dictionary] = {}
	var library: PropLibrary = props.library
	var unknown_keys: Dictionary[String, bool] = {}
	var skipped: int = 0
	var clamped: int = 0
	var prop_array: Array = raw_props
	for entry: Variant in prop_array:
		if typeof(entry) != TYPE_DICTIONARY:
			return _fail("Prop mal formado.")
		var p: Dictionary = entry
		var cell: Vector3i = _to_vec3i(p.get("cell"), Vector3i(-1, -1, -1))
		if cell.x < 0 or cell.y < 0 or cell.z < 0 \
				or cell.x >= size_v.x or cell.y >= size_v.y or cell.z >= size_v.z:
			return _fail("Prop fuera del mapa.")
		# Un objeto que no está en la biblioteca no rompe la carga: el prop se omite.
		var prop_key: String = str(p.get("id", ""))
		var id: int = library.key_to_id(prop_key)
		if id < 0:
			unknown_keys[prop_key] = true
			skipped += 1
			continue
		var variant: int = _to_int(p.get("variant"))
		if variant < 0 or variant >= library.variant_count(id):
			variant = clampi(variant, 0, library.variant_count(id) - 1)
			clamped += 1
		new_props[cell] = PropLayer.make_prop(id, variant, _to_int(p.get("rot")))

	# Criaturas (desde la versión 2; un mapa de la versión 1 no trae ninguna).
	var raw_entities: Variant = d.get("entities", [])
	if typeof(raw_entities) != TYPE_ARRAY:
		return _fail("Lista de criaturas mal formada.")
	var new_entities: Dictionary[Vector3i, Dictionary] = {}
	var entity_array: Array = raw_entities
	for entry: Variant in entity_array:
		if typeof(entry) != TYPE_DICTIONARY:
			return _fail("Criatura mal formada.")
		var e: Dictionary = entry
		var type: int = CharacterLibrary.entity_key_to_type(str(e.get("type", "")))
		var cell: Vector3i = _to_vec3i(e.get("cell"), Vector3i(-1, -1, -1))
		if type < 0 or cell.x < 0 or cell.y < 0 or cell.z < 0 \
				or cell.x >= size_v.x or cell.y >= size_v.y or cell.z >= size_v.z:
			return _fail("Criatura desconocida o fuera del mapa.")
		var raw_lines: Variant = e.get("lines", [])
		var lines: Array = []
		if typeof(raw_lines) == TYPE_ARRAY:
			lines = raw_lines
		new_entities[cell] = EntityLayer.make_entity(type, _to_int(e.get("variant")),
				_to_int(e.get("rot")), str(e.get("name", "")), lines)

	# Recién ahora se toca el mundo: un archivo inválido no destruye el mapa actual.
	world.replace_all(size_v, new_chunks)
	props.clear()
	for cell: Vector3i in new_props:
		props.set_prop(cell, new_props[cell])
	if entities != null:
		entities.clear()
		for cell: Vector3i in new_entities:
			entities.set_entity(cell, new_entities[cell])
	var notes: PackedStringArray = []
	if skipped > 0:
		notes.append("Se omitieron %d props de objetos desconocidos (%s)." % [
				skipped, ", ".join(unknown_keys.keys())])
	if clamped > 0:
		notes.append("Se ajustó la variante de %d props." % clamped)
	return {"ok": true, "error": "", "seed": _to_int(d.get("seed")), "warning": " ".join(notes)}


## Guarda el mapa. Devuelve "" si salió bien o un mensaje de error.
static func save_file(path: String, world: VoxelWorld, props: PropLayer, map_seed: int,
		entities: EntityLayer = null) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "No se pudo escribir el archivo (error %d)." % FileAccess.get_open_error()
	file.store_string(JSON.stringify(serialize(world, props, map_seed, entities)))
	file.close()
	return ""


## Carga un mapa. Devuelve lo mismo que deserialize.
static func load_file(path: String, world: VoxelWorld, props: PropLayer,
		entities: EntityLayer = null) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("El archivo no existe.")
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("El archivo no es JSON válido (línea %d)." % json.get_error_line())
	return deserialize(json.data, world, props, entities)


# ---------------------------------------------------------------- auxiliares

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "seed": 0, "warning": ""}


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _to_int(value: Variant, fallback: int = 0) -> int:
	if _is_number(value):
		return int(value)
	return fallback


static func _to_vec3i(value: Variant, fallback: Vector3i = Vector3i.ZERO) -> Vector3i:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var list: Array = value
	if list.size() != 3 or not (_is_number(list[0]) and _is_number(list[1]) and _is_number(list[2])):
		return fallback
	return Vector3i(int(list[0]), int(list[1]), int(list[2]))


static func _rle_encode(data: PackedByteArray) -> Array:
	var out: Array = []
	var current: int = data[0]
	var run: int = 0
	for value: int in data:
		if value == current:
			run += 1
		else:
			out.append(current)
			out.append(run)
			current = value
			run = 1
	out.append(current)
	out.append(run)
	return out


## Devuelve un arreglo vacío si los datos son inválidos.
static func _rle_decode(value: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	if typeof(value) != TYPE_ARRAY:
		return out
	var list: Array = value
	if list.size() % 2 != 0:
		return out
	out.resize(VoxelWorld.CHUNK_VOLUME)
	var at: int = 0
	for i: int in range(0, list.size(), 2):
		if not (_is_number(list[i]) and _is_number(list[i + 1])):
			return PackedByteArray()
		var id: int = int(list[i])
		var run: int = int(list[i + 1])
		if not Blocks.is_valid(id) or run < 1 or at + run > VoxelWorld.CHUNK_VOLUME:
			return PackedByteArray()
		for j: int in run:
			out[at + j] = id
		at += run
	if at != VoxelWorld.CHUNK_VOLUME:
		return PackedByteArray()
	return out
