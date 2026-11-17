class_name UserSettings
extends RefCounted
## Ajustes del usuario guardados en user://ajustes.cfg.

const PATH: String = "user://ajustes.cfg"
const SECTION: String = "jugador"
## Clave antigua: el avatar se guardaba como número. Se sigue leyendo si no hay otra.
const KEY_AVATAR: String = "avatar"
const KEY_AVATAR_ID: String = "avatar_id"
const SECTION_MAP: String = "mapa"
const KEY_MAP_SIZE: String = "tamano"


## Índice del avatar guardado. Se guarda su identificador (texto), así agregar avatares
## no cambia la elección. Un identificador desconocido, o ningún ajuste, da el primero.
static func load_avatar(path: String = PATH) -> int:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return 0
	var saved_id: Variant = null
	var legacy_index: Variant = null
	if config.has_section_key(SECTION, KEY_AVATAR_ID):
		saved_id = config.get_value(SECTION, KEY_AVATAR_ID)
	if config.has_section_key(SECTION, KEY_AVATAR):
		legacy_index = config.get_value(SECTION, KEY_AVATAR)
	return resolve_avatar(saved_id, legacy_index)


## Convierte lo guardado en un índice de avatar: primero el identificador; si no hay,
## el número de la versión anterior (que se refería a los seis avatares de entonces).
static func resolve_avatar(saved_id: Variant, legacy_index: Variant) -> int:
	if typeof(saved_id) == TYPE_STRING:
		var index: int = CharacterLibrary.avatar_index(saved_id)
		return maxi(index, 0)
	if typeof(legacy_index) == TYPE_INT:
		var old: int = legacy_index
		if old >= 0 and old < CharacterLibrary.LEGACY_AVATAR_IDS.size():
			return maxi(CharacterLibrary.avatar_index(CharacterLibrary.LEGACY_AVATAR_IDS[old]), 0)
	return 0


static func save_avatar(index: int, path: String = PATH) -> void:
	var config := ConfigFile.new()
	config.load(path)
	var safe: int = clampi(index, 0, CharacterLibrary.AVATAR_COUNT - 1)
	config.set_value(SECTION, KEY_AVATAR_ID, CharacterLibrary.AVATAR_IDS[safe])
	if config.has_section_key(SECTION, KEY_AVATAR):
		config.erase_section_key(SECTION, KEY_AVATAR)
	config.save(path)


## Último tamaño de mapa elegido en "Nuevo" (S, M o L).
static func load_map_size() -> String:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return AppConfig.DEFAULT_SIZE
	var value: String = str(config.get_value(SECTION_MAP, KEY_MAP_SIZE, AppConfig.DEFAULT_SIZE))
	return value.to_upper() if AppConfig.is_size_key(value) else AppConfig.DEFAULT_SIZE


static func save_map_size(size_key: String) -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value(SECTION_MAP, KEY_MAP_SIZE, size_key.to_upper())
	config.save(PATH)
