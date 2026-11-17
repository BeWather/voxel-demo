class_name PropIO
extends RefCounted
## Guardado y carga de objetos (props) en JSON, un archivo por objeto: `user://props/<clave>.json`.
## Cada variante lleva una paleta de colores en hexadecimal y una lista plana de voxeles
## [x, y, z, índice de paleta, x, y, z, índice, ...].

const FORMAT: String = "editor_voxel_objeto"
const VERSION: int = 1
const PROPS_DIR: String = "user://props"
const MAX_KEY_LENGTH: int = 40
const MAX_NAME_LENGTH: int = 40

const _KEY_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789_"
## Letras con tilde o diéresis y su equivalente ASCII (mismo índice en las dos cadenas).
const _ACCENTED: String = "áàäâãåéèëêíìïîóòöôõúùüûñç"
const _PLAIN: String = "aaaaaaeeeeiiiiooooouuuunc"


static func ensure_dir(dir: String = PROPS_DIR) -> void:
	DirAccess.make_dir_recursive_absolute(dir)


static func path_for(dir: String, key: String) -> String:
	return "%s/%s.json" % [dir, key]


## Rutas de los archivos .json de una carpeta, en orden alfabético (el orden de carga define
## el id de los objetos nuevos, así que tiene que ser estable).
static func list_files(dir: String = PROPS_DIR) -> Array[String]:
	var paths: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return paths
	var names: Array = Array(DirAccess.get_files_at(dir))
	names.sort()
	for file_name: String in names:
		if file_name.get_extension().to_lower() == "json":
			paths.append("%s/%s" % [dir, file_name])
	return paths


## Deriva una clave de un nombre: minúsculas, ASCII, guiones bajos. Puede devolver "".
static func slugify(display_name: String) -> String:
	var out: String = ""
	for ch: String in display_name.strip_edges().to_lower():
		var at: int = _ACCENTED.find(ch)
		if at >= 0:
			ch = _PLAIN[at]
		if _KEY_CHARS.contains(ch) and ch != "_":
			out += ch
		elif not out.is_empty() and not out.ends_with("_"):
			out += "_"
	return out.left(MAX_KEY_LENGTH).rstrip("_")


static func is_valid_key(key: String) -> bool:
	if key.is_empty() or key.length() > MAX_KEY_LENGTH:
		return false
	for ch: String in key:
		if not _KEY_CHARS.contains(ch):
			return false
	return true


## Revisa que un objeto se pueda guardar. Devuelve "" o el motivo del rechazo.
static func validate(key: String, display_name: String, variants: Array[Dictionary]) -> String:
	if not is_valid_key(key):
		return "Clave de objeto inválida: «%s»." % key
	if display_name.strip_edges().is_empty():
		return "El objeto necesita un nombre."
	if variants.is_empty() or variants.size() > PropLibrary.MAX_VARIANTS:
		return "Un objeto tiene entre 1 y %d variantes." % PropLibrary.MAX_VARIANTS
	for i: int in variants.size():
		var vox: Dictionary = variants[i]
		if vox.is_empty():
			return "La variante %d está vacía." % (i + 1)
		for voxel_key: int in vox:
			var cell: Vector3i = PropLibrary.voxel_cell(voxel_key)
			if not PropLibrary.in_volume(cell.x, cell.y, cell.z):
				return "La variante %d tiene voxeles fuera del volumen de edición." % (i + 1)
	return ""


## Copia de las variantes con los colores redondeados a 8 bits por canal y sin transparencia,
## tal como quedan al guardarlas.
static func quantize_variants(variants: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in variants:
		var vox: Dictionary[int, Color] = {}
		for voxel_key: int in entry:
			var color: Color = entry[voxel_key]
			vox[voxel_key] = Color.html(color.to_html(false))
		out.append(vox)
	return out


## Convierte un objeto en un diccionario listo para JSON.
static func serialize(key: String, display_name: String, variants: Array[Dictionary]) -> Dictionary:
	var variant_list: Array = []
	for entry: Dictionary in variants:
		var palette: Array = []
		var index_of: Dictionary[String, int] = {}
		var voxels: Array = []
		var keys: Array = entry.keys()
		keys.sort()
		for voxel_key: int in keys:
			var color: Color = entry[voxel_key]
			var hex: String = color.to_html(false)
			if not index_of.has(hex):
				index_of[hex] = palette.size()
				palette.append(hex)
			var cell: Vector3i = PropLibrary.voxel_cell(voxel_key)
			voxels.append(cell.x)
			voxels.append(cell.y)
			voxels.append(cell.z)
			voxels.append(index_of[hex])
		variant_list.append({"palette": palette, "voxels": voxels})
	return {
		"format": FORMAT,
		"version": VERSION,
		"key": key,
		"name": display_name,
		"variants": variant_list,
	}


## Valida `data` y arma las variantes.
## Devuelve {"ok": bool, "error": String, "key": String, "name": String, "variants": Array[Dictionary]}.
static func deserialize(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return _fail("el archivo no contiene un objeto.")
	var d: Dictionary = data
	if str(d.get("format", "")) != FORMAT:
		return _fail("el archivo no es un objeto del Editor Voxel.")
	var version: Variant = d.get("version")
	if not _is_number(version) or int(version) != VERSION:
		return _fail("versión de objeto no soportada: %s (se esperaba %d)." % [str(version), VERSION])
	if typeof(d.get("key")) != TYPE_STRING or not is_valid_key(str(d.get("key"))):
		return _fail("clave de objeto inválida.")
	var key: String = d["key"]
	var display_name: String = str(d.get("name", "")).strip_edges().left(MAX_NAME_LENGTH)
	if typeof(d.get("name")) != TYPE_STRING or display_name.is_empty():
		return _fail("falta el nombre del objeto.")

	var raw_variants: Variant = d.get("variants")
	if typeof(raw_variants) != TYPE_ARRAY:
		return _fail("falta la lista de variantes.")
	var variant_array: Array = raw_variants
	if variant_array.is_empty() or variant_array.size() > PropLibrary.MAX_VARIANTS:
		return _fail("cantidad de variantes inválida.")
	var variants: Array[Dictionary] = []
	for entry: Variant in variant_array:
		if typeof(entry) != TYPE_DICTIONARY:
			return _fail("variante mal formada.")
		var variant: Dictionary = entry
		var palette: Array[Color] = []
		var raw_palette: Variant = variant.get("palette")
		if typeof(raw_palette) != TYPE_ARRAY:
			return _fail("falta la paleta de una variante.")
		var palette_array: Array = raw_palette
		for hex: Variant in palette_array:
			if typeof(hex) != TYPE_STRING or str(hex).length() != 6 or not str(hex).is_valid_hex_number():
				return _fail("color de paleta inválido.")
			palette.append(Color.html(str(hex)))
		var raw_voxels: Variant = variant.get("voxels")
		if typeof(raw_voxels) != TYPE_ARRAY:
			return _fail("falta la lista de voxeles de una variante.")
		var list: Array = raw_voxels
		if list.is_empty() or list.size() % 4 != 0:
			return _fail("lista de voxeles vacía o incompleta.")
		var vox: Dictionary[int, Color] = {}
		for i: int in range(0, list.size(), 4):
			if not (_is_number(list[i]) and _is_number(list[i + 1]) and _is_number(list[i + 2])
					and _is_number(list[i + 3])):
				return _fail("voxel mal formado.")
			var x: int = int(list[i])
			var y: int = int(list[i + 1])
			var z: int = int(list[i + 2])
			var color_index: int = int(list[i + 3])
			if not PropLibrary.in_volume(x, y, z):
				return _fail("voxel fuera del volumen de edición.")
			if color_index < 0 or color_index >= palette.size():
				return _fail("índice de paleta fuera de rango.")
			vox[PropLibrary.voxel_key(x, y, z)] = palette[color_index]
		variants.append(vox)
	return {"ok": true, "error": "", "key": key, "name": display_name, "variants": variants}


## Guarda un objeto. Devuelve "" si salió bien o un mensaje de error.
static func save_file(path: String, key: String, display_name: String, variants: Array[Dictionary]) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "No se pudo escribir el archivo (error %d)." % FileAccess.get_open_error()
	file.store_string(JSON.stringify(serialize(key, display_name, variants)))
	file.close()
	return ""


## Carga un objeto. Devuelve lo mismo que deserialize.
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("el archivo no existe.")
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("el archivo no es JSON válido (línea %d)." % json.get_error_line())
	return deserialize(json.data)


# ---------------------------------------------------------------- auxiliares

static func _fail(message: String) -> Dictionary:
	var none: Array[Dictionary] = []
	return {"ok": false, "error": message, "key": "", "name": "", "variants": none}


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
