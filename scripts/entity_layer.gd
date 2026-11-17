class_name EntityLayer
extends Node3D
## Criaturas colocadas en el mapa (animales y aldeanos). Una por celda: la celda de aire
## sobre un bloque sólido, igual que los props.

var library: CharacterLibrary
## Clave: celda. Valor: {"type", "variant", "rot", "name", "lines"}.
## "name" y "lines" solo se usan en los aldeanos.
var entities: Dictionary[Vector3i, Dictionary] = {}

var _actors: Dictionary[Vector3i, EntityActor] = {}


## Arma los datos de una criatura con todas sus claves, en un formato comparable.
static func make_entity(type: int, variant: int, rot: int, npc_name: String = "",
		lines: Array = []) -> Dictionary:
	var clean: Array = []
	for line: Variant in lines:
		clean.append(str(line))
	return {
		"type": type,
		"variant": clampi(variant, 0, CharacterLibrary.variant_count(type) - 1),
		"rot": posmod(rot, 4),
		"name": npc_name,
		"lines": clean,
	}


## Aldeano nuevo con nombre y líneas por defecto.
static func make_default_npc(variant: int, rot: int) -> Dictionary:
	return make_entity(CharacterLibrary.VILLAGER, variant, rot,
			CharacterLibrary.default_npc_name(variant, randi()), CharacterLibrary.DEFAULT_NPC_LINES)


func has_entity(cell: Vector3i) -> bool:
	return entities.has(cell)


## Devuelve una copia de los datos, o un diccionario vacío si no hay criatura.
func get_entity(cell: Vector3i) -> Dictionary:
	if entities.has(cell):
		return entities[cell].duplicate(true)
	return {}


## Coloca o reemplaza la criatura de una celda. Un diccionario vacío la quita.
func set_entity(cell: Vector3i, data: Dictionary) -> void:
	if _actors.has(cell):
		var old: EntityActor = _actors[cell]
		remove_child(old)
		old.queue_free()
		_actors.erase(cell)
	entities.erase(cell)
	if data.is_empty():
		return
	var stored: Dictionary = data.duplicate(true)
	entities[cell] = stored
	var actor := EntityActor.new()
	actor.setup(library, cell, stored)
	add_child(actor)
	_actors[cell] = actor


func clear() -> void:
	for cell: Vector3i in _actors:
		var actor: EntityActor = _actors[cell]
		remove_child(actor)
		actor.queue_free()
	_actors.clear()
	entities.clear()


func get_actor(cell: Vector3i) -> EntityActor:
	return _actors.get(cell)


func actors() -> Array[EntityActor]:
	var list: Array[EntityActor] = []
	for cell: Vector3i in _actors:
		list.append(_actors[cell])
	return list


## Devuelve todas las criaturas a su celda (al salir del modo juego).
func reset_actors() -> void:
	for cell: Vector3i in _actors:
		_actors[cell].reset()


## Busca la criatura más cercana que cruza el rayo. Devuelve {"cell", "distance"} o vacío.
func pick(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = max_distance
	for cell: Vector3i in entities:
		var type: int = entities[cell]["type"]
		var r: float = maxf(CharacterLibrary.BODY_HALF[type], 0.3)
		var box := AABB(Vector3(cell.x + 0.5 - r, cell.y, cell.z + 0.5 - r),
				Vector3(r * 2.0, CharacterLibrary.BODY_HEIGHT[type], r * 2.0))
		var point: Variant = box.intersects_ray(origin, direction)
		if point == null:
			continue
		var hit_point: Vector3 = point
		var dist: float = origin.distance_to(hit_point)
		if dist < best_dist:
			best_dist = dist
			best = {"cell": cell, "distance": dist}
	return best
