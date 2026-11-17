extends RefCounted
## Segunda parte de la autoprueba: criaturas, formato de mapa v2, colisión del jugador,
## comportamiento de los animales y diálogos. La ejecuta tests/selftest.gd.

const STEP: float = 1.0 / 60.0

var checks: int = 0
var failures: int = 0
var _tree: SceneTree


func run(tree: SceneTree) -> void:
	_tree = tree
	_test_entities_save_load()
	_test_entity_undo()
	_test_player_collision()
	_test_animals()
	_test_play_mode()
	_test_new_characters()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		failures += 1
		print("  FALLA %s" % label)


# ---------------------------------------------------------------- auxiliares

func _new_world() -> VoxelWorld:
	var world := VoxelWorld.new()
	_tree.get_root().add_child(world)
	return world


func _new_props() -> PropLayer:
	var props := PropLayer.new()
	props.library = PropLibrary.new()
	_tree.get_root().add_child(props)
	return props


func _new_entities() -> EntityLayer:
	var entities := EntityLayer.new()
	entities.library = CharacterLibrary.new()
	_tree.get_root().add_child(entities)
	return entities


## Mundo plano: piedra hasta `top` y pasto arriba (se camina en y = top + 1).
func _flat_world(size: Vector3i, top: int) -> VoxelWorld:
	var world: VoxelWorld = _new_world()
	world.clear(size)
	for z: int in size.z:
		for x: int in size.x:
			for y: int in top + 1:
				world.set_block_raw(x, y, z, Blocks.GRASS if y == top else Blocks.STONE)
	return world


func _fill(world: VoxelWorld, from: Vector3i, to: Vector3i, id: int) -> void:
	for y: int in range(from.y, to.y + 1):
		for z: int in range(from.z, to.z + 1):
			for x: int in range(from.x, to.x + 1):
				world.set_block_raw(x, y, z, id)


func _find_npc(entities: EntityLayer) -> Vector3i:
	for cell: Vector3i in entities.entities:
		if entities.entities[cell]["type"] == CharacterLibrary.VILLAGER:
			return cell
	return Vector3i(-1, -1, -1)


# ---------------------------------------------------------------- pruebas

func _test_entities_save_load() -> void:
	print("[criaturas: generar, guardar y cargar]")
	var world: VoxelWorld = _new_world()
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	MeadowGenerator.generate(world, props, 777, entities)

	var counts: Dictionary[int, int] = {}
	var misplaced: int = 0
	var ducks_off_shore: int = 0
	for cell: Vector3i in entities.entities:
		var type: int = entities.entities[cell]["type"]
		counts[type] = counts.get(type, 0) + 1
		var below: int = world.get_block(cell + Vector3i.DOWN)
		if world.get_block(cell) != Blocks.AIR or not Blocks.is_solid(below) or props.has_prop(cell):
			misplaced += 1
		if type == CharacterLibrary.DUCK and below != Blocks.SAND:
			ducks_off_shore += 1
	print("  %d criaturas, por tipo: %s" % [entities.entities.size(), str(counts)])
	_check(entities.entities.size() >= 15 and entities.entities.size() <= 50, "cantidad moderada de criaturas")
	_check(counts.get(CharacterLibrary.UNICORN, 0) <= 1 and counts.get(CharacterLibrary.DRAGON, 0) <= 1,
			"unicornio y dragón son raros: como mucho uno de cada uno en un mapa S")
	var common: int = 0
	for type: int in range(CharacterLibrary.SHEEP, CharacterLibrary.VILLAGER + 1):
		if counts.has(type):
			common += 1
	_check(common == 8, "hay al menos una de cada tipo común (%d de 8)" % common)
	_check(counts.get(CharacterLibrary.VILLAGER, 0) == 1, "hay exactamente un aldeano")
	_check(misplaced == 0, "todas están sobre suelo firme, en aire y sin prop en la celda")
	_check(ducks_off_shore == 0, "los patos están en la orilla del estanque")
	var npc_cell: Vector3i = _find_npc(entities)
	var centre := Vector2(world.size_x * 0.5, world.size_z * 0.5)
	_check(Vector2(npc_cell.x, npc_cell.z).distance_to(centre) < 8.0, "el aldeano está cerca del centro")
	var npc: Dictionary = entities.get_entity(npc_cell)
	_check(not str(npc["name"]).is_empty() and npc["lines"].size() >= 2, "el aldeano tiene nombre y líneas por defecto")

	# Texto con acentos, comillas y signos: debe sobrevivir al JSON.
	var lines: Array = ["¿Viste al ñandú? ¡Pasó corriendo!", "Dijo \"hasta mañana\" y se fue.", "Línea 3"]
	entities.set_entity(npc_cell, EntityLayer.make_entity(CharacterLibrary.VILLAGER, 2, 3, "Doña Ñusta", lines))
	var original: Dictionary = MapIO.serialize(world, props, 777, entities)
	_check(original["version"] == MapIO.VERSION, "el mapa se guarda con la versión actual (%d)" % MapIO.VERSION)
	_check(original["entities"].size() == entities.entities.size(), "el archivo lista todas las criaturas")

	MapIO.ensure_maps_dir()
	var path: String = MapIO.MAPS_DIR + "/_autoprueba_v2.json"
	_check(MapIO.save_file(path, world, props, 777, entities).is_empty(), "save_file sin errores")
	var world2: VoxelWorld = _new_world()
	var props2: PropLayer = _new_props()
	var entities2: EntityLayer = _new_entities()
	var result: Dictionary = MapIO.load_file(path, world2, props2, entities2)
	_check(result["ok"], "load_file sin errores (%s)" % str(result["error"]))
	_check(entities2.entities == entities.entities, "las %d criaturas coinciden" % entities.entities.size())
	var npc2: Dictionary = entities2.get_entity(npc_cell)
	_check(npc2["name"] == "Doña Ñusta" and npc2["lines"] == lines and npc2["variant"] == 2 and npc2["rot"] == 3,
			"el aldeano conserva nombre, líneas, variante y rotación")
	_check(MapIO.serialize(world2, props2, 777, entities2) == original, "volver a serializar da lo mismo")
	_check(entities2.actors().size() == entities2.entities.size(), "cada criatura cargada tiene su modelo")
	DirAccess.remove_absolute(path)

	# Un mapa de la versión 1 se carga sin criaturas (y borra las que hubiera).
	result = MapIO.load_file("res://tests/fixtures/mapa_v1.json", world2, props2, entities2)
	_check(result["ok"], "el mapa de ejemplo v1 se carga (%s)" % str(result["error"]))
	_check(world2.size_x == 16 and world2.get_block(Vector3i(3, 1, 3)) == Blocks.GRASS
			and world2.get_block(Vector3i(3, 0, 3)) == Blocks.STONE, "bloques del mapa v1")
	_check(props2.props.size() == 2 and props2.has_prop(Vector3i(4, 2, 4)), "props del mapa v1")
	_check(entities2.entities.is_empty() and entities2.actors().is_empty(), "un mapa v1 no tiene criaturas")
	_check(result["seed"] == 99, "semilla del mapa v1")

	# Versiones desconocidas y criaturas inválidas se rechazan sin tocar el mundo.
	var before: Dictionary = MapIO.serialize(world2, props2, 0, entities2)
	var future: Dictionary = original.duplicate(true)
	future["version"] = MapIO.VERSION + 1
	result = MapIO.deserialize(future, world2, props2, entities2)
	_check(not result["ok"], "una versión más nueva se rechaza (%s)" % str(result["error"]))
	var broken: Dictionary = original.duplicate(true)
	broken["entities"] = [{"cell": [1, 2, 3], "type": "kraken"}]
	result = MapIO.deserialize(broken, world2, props2, entities2)
	_check(not result["ok"], "una criatura desconocida se rechaza (%s)" % str(result["error"]))
	_check(MapIO.serialize(world2, props2, 0, entities2) == before, "el mundo no cambia tras los rechazos")
	for node: Node in [world, props, entities, world2, props2, entities2]:
		node.queue_free()


func _test_entity_undo() -> void:
	print("[criaturas: deshacer y rehacer]")
	var world: VoxelWorld = _new_world()
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	MeadowGenerator.generate(world, props, 4242, entities)
	var controller := EditorController.new()
	controller.setup(world, props, null, entities)
	var before: Dictionary = MapIO.serialize(world, props, 0, entities)

	var free_cell := Vector3i(-1, -1, -1)
	var prop_cell: Vector3i = props.props.keys()[0]
	for z: int in world.size_z:
		for x: int in world.size_x:
			var cell := Vector3i(x, world.column_height(x, z), z)
			if free_cell.x < 0 and controller.can_place_entity(cell):
				free_cell = cell
	_check(free_cell.x >= 0, "hay una celda libre para una criatura")
	_check(not controller.can_place_entity(prop_cell), "no se coloca una criatura sobre un prop")

	# Colocar.
	var sheep: Dictionary = EntityLayer.make_entity(CharacterLibrary.SHEEP, 0, 1)
	controller.begin_stroke()
	controller.apply_entity(free_cell, sheep)
	controller.end_stroke()
	_check(entities.get_entity(free_cell) == sheep and entities.get_actor(free_cell) != null, "criatura colocada")
	_check(not controller.can_place_entity(free_cell) and not controller.can_place_prop(free_cell),
			"la celda ocupada no admite otra criatura ni un prop")
	controller.undo()
	_check(MapIO.serialize(world, props, 0, entities) == before and entities.get_actor(free_cell) == null,
			"deshacer quita la criatura")
	controller.redo()
	_check(entities.get_entity(free_cell) == sheep, "rehacer la vuelve a colocar")
	controller.undo()

	# Borrar el bloque de apoyo del aldeano: se va en el mismo paso y vuelve con su texto.
	var npc_cell: Vector3i = _find_npc(entities)
	var npc: Dictionary = entities.get_entity(npc_cell)
	controller.begin_stroke()
	controller.apply_block(npc_cell + Vector3i.DOWN, Blocks.AIR)
	controller.apply_block(Vector3i(5, 20, 5), Blocks.STONE)
	controller.end_stroke()
	_check(not entities.has_entity(npc_cell), "el aldeano sin apoyo se quita")
	var after: Dictionary = MapIO.serialize(world, props, 0, entities)
	controller.undo()
	_check(MapIO.serialize(world, props, 0, entities) == before, "un solo deshacer restaura bloque y aldeano")
	_check(entities.get_entity(npc_cell) == npc, "el aldeano vuelve con su nombre y sus líneas")
	_check(not controller.can_undo(), "todo el trazo era un solo paso")
	controller.redo()
	_check(MapIO.serialize(world, props, 0, entities) == after, "rehacer repite el trazo")
	controller.undo()

	# Un bloque colocado en la celda de la criatura la reemplaza; cambiar a agua el apoyo también la quita.
	controller.apply_block(npc_cell, Blocks.WOOD)
	_check(not entities.has_entity(npc_cell), "un bloque colocado sobre la criatura la quita")
	controller.undo()
	controller.apply_block(npc_cell + Vector3i.DOWN, Blocks.WATER)
	_check(not entities.has_entity(npc_cell), "pintar de agua el apoyo quita la criatura")
	controller.undo()
	_check(MapIO.serialize(world, props, 0, entities) == before, "deshacer devuelve todo")

	# Editar el diálogo es un paso de deshacer como cualquier otro.
	controller.apply_entity(npc_cell, EntityLayer.make_entity(CharacterLibrary.VILLAGER, npc["variant"],
			npc["rot"], "Otro nombre", ["Una sola línea"]))
	_check(entities.get_entity(npc_cell)["name"] == "Otro nombre", "diálogo editado")
	controller.undo()
	_check(entities.get_entity(npc_cell) == npc, "deshacer restaura el diálogo anterior")
	controller.free()
	for node: Node in [world, props, entities]:
		node.queue_free()


func _test_player_collision() -> void:
	print("[jugador: colisión con la grilla]")
	var world: VoxelWorld = _flat_world(Vector3i(24, 16, 24), 3)
	var props: PropLayer = _new_props()
	# Pared de 3 de alto en x = 12, un escalón suelto y una pileta con agua.
	_fill(world, Vector3i(12, 4, 0), Vector3i(12, 6, 9), Blocks.STONE)
	world.set_block_raw(16, 4, 15, Blocks.STONE)
	_fill(world, Vector3i(18, 2, 18), Vector3i(21, 3, 21), Blocks.WATER)
	props.set_prop(Vector3i(4, 4, 15), PropLayer.make_prop(PropLibrary.OAK, 0, 0))
	props.set_prop(Vector3i(8, 4, 15), PropLayer.make_prop(PropLibrary.FLOWER_RED, 0, 0))

	var player := Player.new()
	_tree.get_root().add_child(player)
	player.set_avatar(CharacterLibrary.new().get_avatar_parts(0))
	_check(player.rig.part_count() >= 6, "el avatar tiene sus partes (%d)" % player.rig.part_count())

	# Caída libre hasta el piso.
	player.place_at(Vector3(5.5, 12.0, 5.5))
	var inside: int = 0
	for i: int in 180:
		player.tick(STEP, world, props, Vector3.ZERO, false, false)
		if not player.body.overlapping(world, props).is_empty():
			inside += 1
	_check(player.body.on_ground and is_equal_approx(player.body.pos.y, 4.0),
			"cae y queda apoyado en el piso (y = %.3f)" % player.body.pos.y)
	_check(inside == 0, "nunca queda dentro de un voxel sólido")

	# Caminar contra una pared.
	player.place_at(Vector3(8.5, 4.0, 5.5))
	for i: int in 240:
		player.tick(STEP, world, props, Vector3.RIGHT, false, true)
		if not player.body.overlapping(world, props).is_empty():
			inside += 1
	_check(player.body.pos.x > 11.5 and player.body.pos.x <= 12.0 - Player.BODY_HALF,
			"la pared lo detiene (x = %.3f)" % player.body.pos.x)
	_check(inside == 0, "no entra en la pared")
	# Saltando tampoco pasa una pared de 3 bloques.
	for i: int in 240:
		player.tick(STEP, world, props, Vector3.RIGHT, true, true)
	_check(player.body.pos.x <= 12.0 - Player.BODY_HALF, "no salta una pared de 3 bloques")

	# Un salto supera un bloque.
	player.place_at(Vector3(16.5, 4.0, 12.5))
	for i: int in 60:
		player.tick(STEP, world, props, Vector3.BACK, false, false)
	_check(player.body.pos.z < 15.0, "sin saltar, un bloque lo frena (z = %.3f)" % player.body.pos.z)
	var top_y: float = 0.0
	for i: int in 70:
		player.tick(STEP, world, props, Vector3.BACK, true, false)
		top_y = maxf(top_y, player.body.pos.y)
	_check(player.body.pos.z > 16.5 and top_y >= 5.0, "saltando pasa por encima (z = %.2f, altura máx. %.2f)" % [
			player.body.pos.z, top_y])

	# El tronco de un árbol bloquea; una flor no.
	player.place_at(Vector3(4.5, 4.0, 12.5))
	for i: int in 240:
		player.tick(STEP, world, props, Vector3.BACK, false, false)
	_check(player.body.pos.z < 15.0, "el tronco del roble lo detiene (z = %.3f)" % player.body.pos.z)
	player.place_at(Vector3(8.5, 4.0, 12.5))
	for i: int in 100:
		player.tick(STEP, world, props, Vector3.BACK, false, false)
	_check(player.body.pos.z > 17.0, "una flor no estorba (z = %.3f)" % player.body.pos.z)

	# Agua: no es sólida, se hunde hasta el lecho y nada hacia arriba con el salto.
	player.place_at(Vector3(20.0, 4.5, 20.0))
	for i: int in 240:
		player.tick(STEP, world, props, Vector3.ZERO, false, false)
	_check(player.body.in_water and player.body.on_ground and is_equal_approx(player.body.pos.y, 2.0),
			"en el agua se hunde hasta el lecho (y = %.3f)" % player.body.pos.y)
	for i: int in 90:
		player.tick(STEP, world, props, Vector3.ZERO, true, false)
	_check(player.body.pos.y > 2.6, "manteniendo el salto, nada hacia arriba (y = %.3f)" % player.body.pos.y)
	var slow_start: float = player.body.pos.x
	for i: int in 30:
		player.tick(STEP, world, props, Vector3.RIGHT, true, false)
	var swim_speed: float = (player.body.pos.x - slow_start) / (30.0 * STEP)
	_check(swim_speed > 0.5 and swim_speed < Player.WALK_SPEED * 0.75, "en el agua avanza más lento (%.2f)" % swim_speed)

	# Reaparición: por debajo de y = 0 y al salir caminando del mapa.
	player.place_at(Vector3(5.5, 4.0, 5.5))
	player.respawn_count = 0
	player.body.teleport(Vector3(-4.0, 1.0, 5.5))
	for i: int in 120:
		player.tick(STEP, world, props, Vector3.ZERO, false, false)
	_check(player.respawn_count == 1 and player.body.pos.distance_to(player.spawn) < 0.5,
			"al caer por debajo de y = 0 reaparece en el punto de inicio")
	for i: int in 400:
		player.tick(STEP, world, props, Vector3.LEFT, false, true)
	_check(player.respawn_count >= 2, "al caminar fuera del borde del mapa también reaparece")

	# Punto de aparición: nunca en el agua si hay una celda seca cerca, ni sobre un tronco.
	var spawn: Vector3 = Player.find_spawn(world, props, 20, 20)
	_check(Blocks.is_solid(world.get_block_xyz(floori(spawn.x), floori(spawn.y) - 1, floori(spawn.z)))
			and world.get_block_xyz(floori(spawn.x), floori(spawn.y), floori(spawn.z)) == Blocks.AIR,
			"pedir aparecer en el agua da una celda seca cercana %s" % str(spawn))
	spawn = Player.find_spawn(world, props, 4, 15)
	_check(Vector3i(floori(spawn.x), floori(spawn.y), floori(spawn.z)) != Vector3i(4, 4, 15),
			"no aparece dentro de un tronco")
	spawn = Player.find_spawn(world, props, 16, 15)
	_check(is_equal_approx(spawn.y, 5.0), "aparece sobre el bloque más alto de la columna")
	for node: Node in [world, props, player]:
		node.queue_free()


func _test_animals() -> void:
	print("[animales: deambular]")
	# Meseta de 9x9 a 4 bloques de altura: bajar de ahí sería una caída alta.
	var world: VoxelWorld = _flat_world(Vector3i(32, 16, 32), 3)
	_fill(world, Vector3i(10, 4, 10), Vector3i(18, 7, 18), Blocks.STONE)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	var far := Vector3(0.0, 200.0, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240

	for type: int in [CharacterLibrary.SHEEP, CharacterLibrary.RABBIT, CharacterLibrary.FOX]:
		var cell := Vector3i(14, 8, 14)
		entities.set_entity(cell, EntityLayer.make_entity(type, 0, 0))
		var actor: EntityActor = entities.get_actor(cell)
		var lowest: float = INF
		var farthest: float = 0.0
		var travelled: float = 0.0
		var inside: int = 0
		for i: int in 1800:
			var previous: Vector3 = actor.body.pos
			actor.tick(1.0 / 30.0, world, props, far, rng)
			lowest = minf(lowest, actor.body.pos.y)
			farthest = maxf(farthest, Vector2(actor.body.pos.x - actor.home.x, actor.body.pos.z - actor.home.z).length())
			travelled += Vector2(actor.body.pos.x - previous.x, actor.body.pos.z - previous.z).length()
			if not actor.body.overlapping(world, props).is_empty():
				inside += 1
		var label: String = CharacterLibrary.ENTITY_NAMES[type]
		print("  %s: recorrió %.1f, se alejó %.2f, altura mínima %.2f" % [label, travelled, farthest, lowest])
		_check(travelled > 3.0, "%s: deambula" % label)
		_check(lowest >= 7.99, "%s: no baja de la meseta (caída de 4 bloques)" % label)
		_check(farthest <= EntityActor.LEASH + 0.3, "%s: no se aleja más que su radio" % label)
		_check(inside == 0, "%s: nunca queda dentro de un bloque" % label)
		entities.set_entity(cell, {})

	# Terreno escalonado: sube y baja escalones de un bloque, y respeta el radio.
	var stairs: VoxelWorld = _flat_world(Vector3i(32, 16, 32), 3)
	for z: int in 32:
		for x: int in 32:
			@warning_ignore("integer_division")
			var extra: int = ((x / 3) + (z / 4)) % 3
			for y: int in range(4, 4 + extra):
				stairs.set_block_raw(x, y, z, Blocks.GRASS)
	var cow_cell := Vector3i(16, stairs.column_height(16, 16), 16)
	entities.set_entity(cow_cell, EntityLayer.make_entity(CharacterLibrary.COW, 0, 0))
	var cow: EntityActor = entities.get_actor(cow_cell)
	var cow_far: float = 0.0
	var levels: Dictionary[int, bool] = {}
	var worst_fall: float = 0.0
	var last_ground: float = cow.body.pos.y
	for i: int in 3000:
		cow.tick(1.0 / 30.0, stairs, props, far, rng)
		cow_far = maxf(cow_far, Vector2(cow.body.pos.x - cow.home.x, cow.body.pos.z - cow.home.z).length())
		if cow.body.on_ground:
			worst_fall = maxf(worst_fall, last_ground - cow.body.pos.y)
			last_ground = cow.body.pos.y
			levels[roundi(cow.body.pos.y)] = true
	print("  Vaca en escalones: niveles pisados %s, mayor bajada %.2f, se alejó %.2f" % [
			str(levels.keys()), worst_fall, cow_far])
	_check(levels.size() >= 2, "la vaca cambia de nivel por escalones de un bloque")
	_check(worst_fall <= 1.01, "nunca baja más de un bloque de una vez")
	_check(cow_far <= EntityActor.LEASH + 0.3, "la vaca respeta su radio")
	entities.set_entity(cow_cell, {})

	# Isla de arena rodeada de agua: la oveja no entra al agua, el pato sí y flota.
	var pond: VoxelWorld = _flat_world(Vector3i(32, 16, 32), 3)
	_fill(pond, Vector3i(6, 2, 6), Vector3i(25, 3, 25), Blocks.WATER)
	_fill(pond, Vector3i(14, 2, 14), Vector3i(17, 3, 17), Blocks.SAND)
	var island := Vector3i(15, 4, 15)
	entities.set_entity(island, EntityLayer.make_entity(CharacterLibrary.SHEEP, 0, 0))
	var sheep: EntityActor = entities.get_actor(island)
	var wet: int = 0
	for i: int in 1800:
		sheep.tick(1.0 / 30.0, pond, props, far, rng)
		if sheep.body.in_water or sheep.body.pos.y < 3.99:
			wet += 1
	_check(wet == 0, "la oveja nunca entra al agua")
	entities.set_entity(island, EntityLayer.make_entity(CharacterLibrary.DUCK, 0, 0))
	var duck: EntityActor = entities.get_actor(island)
	var swam: int = 0
	var sunk: int = 0
	var duck_far: float = 0.0
	for i: int in 2400:
		duck.tick(1.0 / 30.0, pond, props, far, rng)
		var column_top: int = pond.column_height(floori(duck.body.pos.x), floori(duck.body.pos.z))
		if pond.get_block_xyz(floori(duck.body.pos.x), column_top - 1, floori(duck.body.pos.z)) == Blocks.WATER:
			swam += 1
			if duck.body.pos.y < 3.3:
				sunk += 1
		duck_far = maxf(duck_far, Vector2(duck.body.pos.x - duck.home.x, duck.body.pos.z - duck.home.z).length())
	print("  Pato: %d pasos sobre el agua, %d hundido, se alejó %.2f" % [swam, sunk, duck_far])
	_check(swam > 200, "el pato se mete al agua")
	_check(sunk == 0, "el pato flota en la superficie")
	_check(duck_far <= EntityActor.LEASH + 0.3, "el pato respeta su radio")
	entities.set_entity(island, {})

	# Huida: la gallina se aleja del jugador; la oveja lo ignora.
	var field: VoxelWorld = _flat_world(Vector3i(32, 16, 32), 3)
	var hen_cell := Vector3i(16, 4, 16)
	for type: int in [CharacterLibrary.CHICKEN, CharacterLibrary.SHEEP]:
		entities.set_entity(hen_cell, EntityLayer.make_entity(type, 0, 0))
		var actor: EntityActor = entities.get_actor(hen_cell)
		var threat := Vector3(18.5, 4.0, 16.5)
		var fled: bool = false
		var max_dist: float = 0.0
		for i: int in 900:
			actor.tick(1.0 / 30.0, field, props, threat, rng)
			if actor.state == EntityActor.State.FLEE:
				fled = true
			max_dist = maxf(max_dist, Vector2(actor.body.pos.x - actor.home.x, actor.body.pos.z - actor.home.z).length())
		if type == CharacterLibrary.CHICKEN:
			_check(fled and actor.body.pos.distance_to(threat) > 3.0,
					"la gallina huye del jugador (quedó a %.2f)" % actor.body.pos.distance_to(threat))
			_check(max_dist <= EntityActor.LEASH + 0.3, "aun huyendo respeta su radio (%.2f)" % max_dist)
		else:
			_check(not fled, "la oveja ignora al jugador")
		# Al salir del modo juego, cada criatura vuelve a su celda.
		entities.reset_actors()
		_check(actor.body.pos.is_equal_approx(actor.home) and actor.position.is_equal_approx(actor.home),
				"%s: vuelve a su celda al reiniciar" % CharacterLibrary.ENTITY_NAMES[type])
		entities.set_entity(hen_cell, {})
	for node: Node in [world, stairs, pond, field, props, entities]:
		node.queue_free()


func _test_play_mode() -> void:
	print("[modo juego: aldeano y diálogo]")
	var world: VoxelWorld = _flat_world(Vector3i(24, 16, 24), 3)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	var npc_cell := Vector3i(12, 4, 12)
	entities.set_entity(npc_cell, EntityLayer.make_entity(CharacterLibrary.VILLAGER, 1, 0, "Anselmo",
			["Primera.", "Segunda.", "Tercera."]))
	entities.set_entity(Vector3i(5, 4, 5), EntityLayer.make_entity(CharacterLibrary.PIG, 0, 2))
	var before: Dictionary = MapIO.serialize(world, props, 0, entities)

	var play := PlayMode.new()
	play.setup(world, props, entities, entities.library)
	_tree.get_root().add_child(play)
	play.start(2, Vector3(12.5, 4.0, 18.5), false)
	play.rng.seed = 7
	_check(play.active and play.player.visible, "el modo juego arranca")
	for i: int in 30:
		play.simulate(STEP, Vector3.ZERO, false, false)
	play.interact()
	_check(not play.is_dialog_open(), "lejos del aldeano, E no abre nada")

	# Caminar hasta el aldeano (está hacia -Z).
	for i: int in 120:
		play.simulate(STEP, Vector3.FORWARD, false, false)
		if play.player.body.pos.z < 14.2:
			break
	for i: int in 60:
		play.simulate(STEP, Vector3.ZERO, false, false)
	var npc: EntityActor = entities.get_actor(npc_cell)
	var to_player: Vector3 = play.player.body.pos - npc.body.pos
	_check(absf(angle_difference(npc.yaw, atan2(to_player.x, to_player.z))) < 0.2,
			"el aldeano gira para mirar al jugador")
	_check(npc.body.pos.is_equal_approx(npc.home), "el aldeano no se mueve de su lugar")
	play.interact()
	_check(play.is_dialog_open(), "E abre el diálogo cerca del aldeano")
	var frozen: Vector3 = play.player.body.pos
	for i: int in 60:
		play.simulate(STEP, Vector3.RIGHT, true, true)
	_check(play.player.body.pos.is_equal_approx(frozen), "con el diálogo abierto el jugador no se mueve")
	play.interact()
	play.interact()
	_check(play.is_dialog_open(), "sigue abierto en la última línea")
	play.interact()
	_check(not play.is_dialog_open(), "se cierra después de la última línea")
	for i: int in 60:
		play.simulate(STEP, Vector3.RIGHT, false, false)
	_check(play.player.body.pos.x > frozen.x + 1.0, "al cerrar, el jugador vuelve a moverse")

	# El cerdo deambuló; al salir vuelve a su celda y el mapa queda igual.
	for i: int in 600:
		play.simulate(1.0 / 30.0, Vector3.ZERO, false, false)
	play.stop()
	entities.reset_actors()
	var pig: EntityActor = entities.get_actor(Vector3i(5, 4, 5))
	_check(pig.position.is_equal_approx(pig.home), "al salir, el cerdo vuelve a su celda")
	_check(not play.active and not play.player.visible, "el modo juego se detiene")
	_check(MapIO.serialize(world, props, 0, entities) == before, "jugar no modifica bloques, props ni criaturas")
	for node: Node in [world, props, entities, play]:
		node.queue_free()


## Alto del modelo en bloques: el punto más alto de todas sus partes.
func _model_height(parts: Array[Dictionary]) -> float:
	var top: float = 0.0
	for part: Dictionary in parts:
		var mesh: ArrayMesh = part["mesh"]
		var pivot: Vector3 = part["pivot"]
		top = maxf(top, pivot.y + mesh.get_aabb().end.y)
	return top


func _test_new_characters() -> void:
	print("[avatares de niña y criaturas grandes]")
	var library := CharacterLibrary.new()

	# Avatares: identificadores estables y elección guardada.
	var unique: Dictionary[String, bool] = {}
	for id: String in CharacterLibrary.AVATAR_IDS:
		unique[id] = true
	_check(CharacterLibrary.AVATAR_COUNT == 12 and CharacterLibrary.AVATAR_NAMES.size() == 12 and unique.size() == 12,
			"hay 12 avatares con identificadores distintos")
	_check(CharacterLibrary.is_child_avatar(0) and CharacterLibrary.is_child_avatar(5)
			and not CharacterLibrary.is_child_avatar(6), "las seis niñas van primero")
	_check(UserSettings.resolve_avatar("hada", null) == 4, "un identificador guardado se resuelve por nombre")
	_check(UserSettings.resolve_avatar(null, 2) == CharacterLibrary.avatar_index("maga")
			and CharacterLibrary.AVATAR_NAMES[UserSettings.resolve_avatar(null, 2)] == "Maga",
			"un número de la versión anterior sigue apuntando al mismo avatar (2 = Maga)")
	_check(UserSettings.resolve_avatar("no_existe", 3) == 0 and UserSettings.resolve_avatar(null, 99) == 0
			and UserSettings.resolve_avatar(null, null) == 0 and UserSettings.resolve_avatar(7, "x") == 0,
			"un valor desconocido cae en el primer avatar sin errores")
	var settings_path: String = "user://_autoprueba_ajustes.cfg"
	var legacy := ConfigFile.new()
	legacy.set_value(UserSettings.SECTION, UserSettings.KEY_AVATAR, 4)
	legacy.save(settings_path)
	_check(CharacterLibrary.AVATAR_NAMES[UserSettings.load_avatar(settings_path)] == "Pastora",
			"un archivo de ajustes viejo (avatar = 4) se lee como Pastora")
	UserSettings.save_avatar(3, settings_path)
	var saved := ConfigFile.new()
	saved.load(settings_path)
	_check(saved.get_value(UserSettings.SECTION, UserSettings.KEY_AVATAR_ID, "") == "princesa"
			and not saved.has_section_key(UserSettings.SECTION, UserSettings.KEY_AVATAR)
			and UserSettings.load_avatar(settings_path) == 3, "al guardar se escribe el identificador (princesa)")
	DirAccess.remove_absolute(settings_path)

	# Proporciones.
	var child_min: float = INF
	var child_max: float = 0.0
	var adult_min: float = INF
	var heights: Array[String] = []
	for index: int in CharacterLibrary.AVATAR_COUNT:
		var height: float = _model_height(library.get_avatar_parts(index))
		heights.append("%s %.2f" % [CharacterLibrary.AVATAR_NAMES[index], height])
		if CharacterLibrary.is_child_avatar(index):
			child_min = minf(child_min, height)
			child_max = maxf(child_max, height)
		else:
			adult_min = minf(adult_min, height)
	print("  alto de los avatares (bloques): %s" % ", ".join(heights))
	_check(child_min >= 1.3 and child_max <= 1.8 and child_max < adult_min + 0.01,
			"las niñas miden entre %.2f y %.2f bloques; el adulto más bajo, %.2f" % [child_min, child_max, adult_min])
	var creature_heights: Array[String] = []
	for type: int in [CharacterLibrary.SHEEP, CharacterLibrary.PONY, CharacterLibrary.UNICORN, CharacterLibrary.DRAGON]:
		creature_heights.append("%s %.2f" % [CharacterLibrary.ENTITY_NAMES[type], _model_height(library.get_entity_parts(type, 0))])
	print("  alto de las criaturas (bloques): %s" % ", ".join(creature_heights))
	var pony_height: float = _model_height(library.get_entity_parts(CharacterLibrary.PONY, 0))
	var dragon_height: float = _model_height(library.get_entity_parts(CharacterLibrary.DRAGON, 0))
	var sheep_height: float = _model_height(library.get_entity_parts(CharacterLibrary.SHEEP, 0))
	_check(pony_height > 1.6 and pony_height < 2.3 and dragon_height > 1.6 and dragon_height < 2.4
			and pony_height > sheep_height * 1.4, "poni y dragón tienen más o menos el alto de un adulto y superan a la oveja")
	_check(library.get_entity_parts(CharacterLibrary.PONY, 0)[4]["mesh"] != library.get_entity_parts(CharacterLibrary.PONY, 2)[4]["mesh"],
			"los pelajes del poni son modelos distintos")

	# Colisión del jugador según el avatar.
	var world: VoxelWorld = _flat_world(Vector3i(32, 16, 32), 3)
	_fill(world, Vector3i(10, 4, 10), Vector3i(18, 7, 18), Blocks.STONE)
	world.set_block_raw(24, 4, 6, Blocks.STONE)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	var player := Player.new()
	_tree.get_root().add_child(player)
	player.set_avatar(library.get_avatar_parts(0), CharacterLibrary.avatar_body_height(0))
	_check(is_equal_approx(player.body.height, CharacterLibrary.CHILD_BODY_HEIGHT) and player.body.height < Player.BODY_HEIGHT,
			"la caja de una niña mide %.2f de alto (la de un adulto, %.2f)" % [player.body.height, Player.BODY_HEIGHT])
	player.place_at(Vector3(24.5, 4.0, 3.5))
	var top_y: float = 0.0
	for i: int in 110:
		player.tick(STEP, world, props, Vector3.BACK, true, false)
		top_y = maxf(top_y, player.body.pos.y)
	_check(player.body.pos.z > 7.5 and top_y >= 5.0, "la niña también supera un bloque saltando (z = %.2f)" % player.body.pos.z)
	player.set_avatar(library.get_avatar_parts(8), CharacterLibrary.avatar_body_height(8))
	_check(is_equal_approx(player.body.height, CharacterLibrary.ADULT_BODY_HEIGHT), "al cambiar a un adulto la caja vuelve a 1,70")
	var play := PlayMode.new()
	play.setup(world, props, entities, library)
	_tree.get_root().add_child(play)
	play.start(0, Vector3(5.5, 4.0, 5.5), false)
	var child_camera: float = play.play_camera.position.y
	play.stop()
	play.start(8, Vector3(5.5, 4.0, 5.5), false)
	_check(play.play_camera.position.y > child_camera + 0.15,
			"la cámara sigue la altura del avatar (%.2f con la niña, %.2f con el adulto)" % [child_camera, play.play_camera.position.y])
	play.stop()

	# Criaturas nuevas: guardar, cargar y deshacer.
	entities.set_entity(Vector3i(3, 4, 3), EntityLayer.make_entity(CharacterLibrary.PONY, 2, 1))
	entities.set_entity(Vector3i(6, 4, 3), EntityLayer.make_entity(CharacterLibrary.UNICORN, 0, 2))
	entities.set_entity(Vector3i(9, 4, 3), EntityLayer.make_entity(CharacterLibrary.DRAGON, 1, 3))
	var data: Dictionary = MapIO.serialize(world, props, 5, entities)
	var text: String = JSON.stringify(data)
	_check(text.contains("\"poni\"") and text.contains("\"unicornio\"") and text.contains("\"dragon\""),
			"se guardan con sus claves: poni, unicornio, dragon")
	var world2: VoxelWorld = _new_world()
	var props2: PropLayer = _new_props()
	var entities2: EntityLayer = _new_entities()
	var json := JSON.new()
	json.parse(text)
	var result: Dictionary = MapIO.deserialize(json.data, world2, props2, entities2)
	_check(result["ok"] and entities2.entities == entities.entities, "poni, unicornio y dragón sobreviven a guardar y cargar")
	_check(entities2.get_entity(Vector3i(3, 4, 3))["variant"] == 2 and entities2.get_entity(Vector3i(9, 4, 3))["variant"] == 1,
			"con su pelaje y su color")
	var controller := EditorController.new()
	controller.setup(world2, props2, null, entities2)
	var dragon_cell := Vector3i(20, 4, 20)
	controller.apply_entity(dragon_cell, EntityLayer.make_entity(CharacterLibrary.DRAGON, 0, 0))
	controller.apply_block(dragon_cell + Vector3i.DOWN, Blocks.AIR)
	_check(not entities2.has_entity(dragon_cell), "el dragón también se va si se borra su apoyo")
	controller.undo()
	controller.undo()
	_check(MapIO.serialize(world2, props2, 5, entities2) == data, "deshacer dos veces vuelve al mapa cargado")
	controller.redo()
	_check(entities2.get_entity(dragon_cell)["type"] == CharacterLibrary.DRAGON, "rehacer vuelve a poner el dragón")
	controller.free()

	# Deambular: en una meseta de 4 bloques de alto y entre paredes.
	var far := Vector3(0.0, 200.0, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9090
	for type: int in [CharacterLibrary.PONY, CharacterLibrary.UNICORN, CharacterLibrary.DRAGON]:
		var cell := Vector3i(14, 8, 14)
		entities.set_entity(cell, EntityLayer.make_entity(type, 0, 0))
		var actor: EntityActor = entities.get_actor(cell)
		var lowest: float = INF
		var farthest: float = 0.0
		var travelled: float = 0.0
		var inside: int = 0
		var fled: bool = false
		for i: int in 2400:
			var previous: Vector3 = actor.body.pos
			# El jugador se acerca a mitad de camino: estos animales no huyen.
			var threat: Vector3 = far if i < 1200 else actor.body.pos + Vector3(1.5, 0.0, 0.0)
			actor.tick(1.0 / 30.0, world, props, threat, rng)
			lowest = minf(lowest, actor.body.pos.y)
			farthest = maxf(farthest, Vector2(actor.body.pos.x - actor.home.x, actor.body.pos.z - actor.home.z).length())
			travelled += Vector2(actor.body.pos.x - previous.x, actor.body.pos.z - previous.z).length()
			if not actor.body.overlapping(world, props).is_empty():
				inside += 1
			if actor.state == EntityActor.State.FLEE:
				fled = true
		var label: String = CharacterLibrary.ENTITY_NAMES[type]
		print("  %s: recorrió %.1f, se alejó %.2f, altura mínima %.2f" % [label, travelled, farthest, lowest])
		_check(travelled > 2.0, "%s: deambula" % label)
		_check(lowest >= 7.99, "%s: no se cae de la meseta" % label)
		_check(farthest <= EntityActor.LEASH + 0.3, "%s: respeta su radio" % label)
		_check(inside == 0, "%s: nunca queda dentro de un bloque" % label)
		_check(not fled, "%s: no huye del jugador" % label)
		entities.set_entity(cell, {})

	# En un pasillo de una celda de ancho la caja del poni entra sin tocar las paredes.
	_fill(world, Vector3i(20, 4, 20), Vector3i(20, 6, 28), Blocks.STONE)
	_fill(world, Vector3i(22, 4, 20), Vector3i(22, 6, 28), Blocks.STONE)
	var corridor := Vector3i(21, 4, 24)
	entities.set_entity(corridor, EntityLayer.make_entity(CharacterLibrary.PONY, 1, 0))
	var pony: EntityActor = entities.get_actor(corridor)
	_check(pony.body.overlapping(world, props).is_empty(), "un poni colocado entre dos paredes no queda metido en ellas")
	var stuck: int = 0
	for i: int in 900:
		pony.tick(1.0 / 30.0, world, props, far, rng)
		if not pony.body.overlapping(world, props).is_empty() or absf(pony.body.pos.x - 21.5) > 0.06:
			stuck += 1
	_check(stuck == 0, "y camina por el pasillo sin atravesarlas")
	# El agua lo frena como a los demás animales de tierra.
	var pond: VoxelWorld = _flat_world(Vector3i(32, 16, 32), 3)
	_fill(pond, Vector3i(6, 2, 6), Vector3i(25, 3, 25), Blocks.WATER)
	_fill(pond, Vector3i(14, 2, 14), Vector3i(17, 3, 17), Blocks.SAND)
	entities.set_entity(Vector3i(15, 4, 15), EntityLayer.make_entity(CharacterLibrary.DRAGON, 0, 0))
	var dragon: EntityActor = entities.get_actor(Vector3i(15, 4, 15))
	var wet: int = 0
	for i: int in 1800:
		dragon.tick(1.0 / 30.0, pond, props, far, rng)
		if dragon.body.in_water or dragon.body.pos.y < 3.99:
			wet += 1
	_check(wet == 0, "el dragón no entra al agua")
	for node: Node in [world, pond, props, entities, world2, props2, entities2, player, play]:
		node.queue_free()
