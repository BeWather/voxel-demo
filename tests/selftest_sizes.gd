extends RefCounted
## Tercera parte de la autoprueba: tamaños de mapa S, M y L, generación y mallado por
## partes, guardado de mapas grandes, props por regiones y simulación por cercanía.
## La ejecuta tests/selftest.gd.

var checks: int = 0
var failures: int = 0
var _tree: SceneTree


func run(tree: SceneTree) -> void:
	_tree = tree
	_test_config()
	_test_sizes()
	_test_large_map()
	_test_other_sizes()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		failures += 1
		print("  FALLA %s" % label)


func _new_world(side: int) -> VoxelWorld:
	var world := VoxelWorld.new()
	_tree.get_root().add_child(world)
	world.clear(Vector3i(side, world.size_y, side))
	return world


func _new_props() -> PropLayer:
	var props := PropLayer.new()
	props.library = PropLibrary.new("")
	_tree.get_root().add_child(props)
	return props


func _new_entities() -> EntityLayer:
	var entities := EntityLayer.new()
	entities.library = CharacterLibrary.new()
	_tree.get_root().add_child(entities)
	return entities


func _count_type(entities: EntityLayer, type: int) -> int:
	var count: int = 0
	for cell: Vector3i in entities.entities:
		if entities.entities[cell]["type"] == type:
			count += 1
	return count


## Agua que se escapa: celdas de agua con aire al costado, o sin piso ni agua debajo.
func _leaks(world: VoxelWorld) -> int:
	var leaks: int = 0
	for z: int in world.size_z:
		for x: int in world.size_x:
			for y: int in range(1, 12):
				if world.get_block_xyz(x, y, z) != Blocks.WATER:
					continue
				if world.get_block_xyz(x, y - 1, z) == Blocks.AIR:
					leaks += 1
				for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if world.get_block_xyz(x + side.x, y, z + side.y) == Blocks.AIR:
						leaks += 1
	return leaks


func _test_config() -> void:
	print("[tamaños y escala de la interfaz]")
	_check(AppConfig.side_for("S") == 64 and AppConfig.side_for("m") == 128 and AppConfig.side_for("L") == 256,
			"S = 64, M = 128, L = 256")
	_check(AppConfig.side_for("XL") == 64 and not AppConfig.is_size_key("XL"), "una clave desconocida cae en S")
	_check(AppConfig.key_for_side(128) == "M" and AppConfig.key_for_side(100).is_empty(), "clave a partir del lado")
	_check(AppConfig.size_label("L") == "L — 256 × 256", "etiqueta con las dimensiones: %s" % AppConfig.size_label("L"))
	_check(is_equal_approx(AppConfig.ui_scale_for_height(720), 1.0) and is_equal_approx(AppConfig.ui_scale_for_height(1080), 1.0)
			and is_equal_approx(AppConfig.ui_scale_for_height(1009), 1.0), "escala 1 hasta 1080 px de alto")
	_check(is_equal_approx(AppConfig.ui_scale_for_height(1440), 1.25), "escala 1,25 a 1440 px (%.2f)" % AppConfig.ui_scale_for_height(1440))
	_check(is_equal_approx(AppConfig.ui_scale_for_height(2160), 2.0), "escala 2 a 2160 px (%.2f)" % AppConfig.ui_scale_for_height(2160))
	var saved: String = UserSettings.load_map_size()
	UserSettings.save_map_size("M")
	_check(UserSettings.load_map_size() == "M", "el último tamaño elegido se guarda en ajustes.cfg")
	UserSettings.save_map_size(saved)


func _test_sizes() -> void:
	print("[generación en S, M y L]")
	var density_s: float = 0.0
	for key: String in AppConfig.SIZE_KEYS:
		var side: int = AppConfig.side_for(key)
		var world: VoxelWorld = _new_world(side)
		var props: PropLayer = _new_props()
		var entities: EntityLayer = _new_entities()
		var t0: int = Time.get_ticks_msec()
		var job := MeadowGenerator.new(world, props, 2024, entities)
		var slices: int = 0
		while not job.step(4):
			slices += 1
		var t_gen: int = Time.get_ticks_msec() - t0
		_check(world.size_x == side and world.size_z == side and world.size_y == 32, "%s: el mundo mide %d x %d" % [key, side, side])
		_check(world.in_bounds(Vector3i(side - 1, 31, side - 1)) and not world.in_bounds(Vector3i(side, 0, 0)),
				"%s: los límites siguen al tamaño" % key)
		@warning_ignore("integer_division")
		var expected_chunks: int = (side / 16) * (side / 16)
		_check(world.chunks.size() == expected_chunks, "%s: %d chunks (hay %d)" % [key, expected_chunks, world.chunks.size()])
		_check(world.pending_count() == expected_chunks and world.dirty_count() == 0,
				"%s: las mallas quedan pendientes para armarse por partes" % key)
		var rounds: int = 0
		var t1: int = Time.get_ticks_msec()
		while world.remesh_pending(8) > 0:
			rounds += 1
		var t_mesh: int = Time.get_ticks_msec() - t1
		props.rebuild_dirty()
		var meshed: int = 0
		for chunk_key: Vector3i in world.chunks:
			if world.get_chunk_mesh(chunk_key) != null:
				meshed += 1
		_check(world.pending_count() == 0 and world.dirty_count() == 0 and meshed == expected_chunks,
				"%s: el mallado por partes termina sin chunks pendientes (%d de %d con malla)" % [key, meshed, expected_chunks])
		_check(is_equal_approx(world.pending_progress(), 1.0), "%s: el avance llega al 100%%" % key)
		if side > 64:
			_check(slices > 3 and rounds > 3, "%s: el trabajo se reparte en varios pasos (%d + %d)" % [key, slices, rounds])

		var min_h: int = 999
		var max_h: int = 0
		for z: int in range(0, side, 3):
			for x: int in range(0, side, 3):
				var h: int = world.column_height(x, z)
				min_h = mini(min_h, h)
				max_h = maxi(max_h, h)
		_check(min_h >= 3 and max_h <= 12, "%s: alturas %d..%d" % [key, min_h, max_h])
		var expected_ponds: int = MeadowGenerator.pond_count(side, side)
		_check(job.ponds.size() == expected_ponds, "%s: %d estanque(s) (hay %d)" % [key, expected_ponds, job.ponds.size()])
		var apart: bool = true
		for a: int in job.ponds.size():
			for b: int in range(a + 1, job.ponds.size()):
				if Vector2(job.ponds[a] - job.ponds[b]).length() < MeadowGenerator.POND_SPACING:
					apart = false
		_check(apart, "%s: los estanques están separados" % key)
		var leaks: int = _leaks(world)
		_check(leaks == 0, "%s: el agua no se escapa de ningún estanque (%d fugas)" % [key, leaks])

		var density: float = float(props.props.size()) / float(side * side)
		if key == "S":
			density_s = density
		_check(density > density_s * 0.7 and density < density_s * 1.4,
				"%s: la vegetación escala con el área (%d props, %.3f por celda)" % [key, props.props.size(), density])
		var villagers: int = _count_type(entities, CharacterLibrary.VILLAGER)
		var animals: int = entities.entities.size() - villagers
		_check(villagers == MeadowGenerator.villager_count(side, side), "%s: %d aldeano(s)" % [key, villagers])
		_check(animals >= 20 and animals <= 160, "%s: cantidad de animales razonable (%d)" % [key, animals])
		var rare: int = _count_type(entities, CharacterLibrary.UNICORN) + _count_type(entities, CharacterLibrary.DRAGON)
		_check(rare <= 4, "%s: unicornios y dragones son pocos (%d)" % [key, rare])
		var misplaced: int = 0
		for cell: Vector3i in entities.entities:
			if world.get_block(cell) != Blocks.AIR or not Blocks.is_solid(world.get_block(cell + Vector3i.DOWN)) \
					or props.has_prop(cell):
				misplaced += 1
		_check(misplaced == 0, "%s: todas las criaturas están bien apoyadas" % key)
		print("  %s: generación %d ms, mallas %d ms, %d props en %d grupos, %d animales, %d aldeanos" % [
				key, t_gen, t_mesh, props.props.size(), props.group_count(), animals, villagers])

		if key == "M":
			# El resultado no depende de cómo se reparta el trabajo.
			var world2: VoxelWorld = _new_world(side)
			var props2: PropLayer = _new_props()
			var entities2: EntityLayer = _new_entities()
			MeadowGenerator.generate(world2, props2, 2024, entities2)
			_check(MapIO.serialize(world, props, 2024, entities) == MapIO.serialize(world2, props2, 2024, entities2),
					"M: generar por partes o de una vez da el mismo mapa")
			MeadowGenerator.generate(world2, props2, 2025, entities2)
			_check(world2.chunks != world.chunks, "M: otra semilla da otro mapa")
			# Ida y vuelta por archivo.
			MapIO.ensure_maps_dir()
			var path: String = MapIO.MAPS_DIR + "/_autoprueba_m.json"
			var original: Dictionary = MapIO.serialize(world, props, 2024, entities)
			_check(MapIO.save_file(path, world, props, 2024, entities).is_empty(), "M: guardar")
			var result: Dictionary = MapIO.load_file(path, world2, props2, entities2)
			_check(result["ok"] and world2.size_x == 128 and world2.size_z == 128, "M: cargar (%s)" % str(result["error"]))
			_check(world2.pending_count() == world2.chunks.size(), "M: al cargar, las mallas quedan pendientes")
			_check(MapIO.serialize(world2, props2, 2024, entities2) == original, "M: el mapa cargado es idéntico al guardado")
			DirAccess.remove_absolute(path)
			for node: Node in [world2, props2, entities2]:
				node.queue_free()
		for node: Node in [world, props, entities]:
			node.queue_free()


func _test_large_map() -> void:
	print("[mapa L: ediciones, props por regiones, guardado y modo juego]")
	var world: VoxelWorld = _new_world(256)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	MeadowGenerator.generate(world, props, 77, entities)
	world.remesh_dirty()
	props.rebuild_dirty()

	# Una edición cuesta lo mismo que en S: solo los chunks que toca.
	world.set_block(Vector3i(200, 20, 200), Blocks.STONE)
	_check(world.dirty_count() == 1 and world.is_chunk_dirty(Vector3i(12, 1, 12)), "editar un voxel interior ensucia 1 chunk de 512")
	var t0: int = Time.get_ticks_usec()
	_check(world.remesh_dirty() == 1, "y regenera una sola malla")
	print("  regenerar ese chunk: %.2f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	world.set_block(Vector3i(128, 5, 128), Blocks.STONE)
	_check(world.dirty_count() == 4 and world.is_chunk_dirty(Vector3i(7, 0, 7)) and world.is_chunk_dirty(Vector3i(8, 0, 8)),
			"en la esquina de cuatro chunks ensucia esos 4 (hay %d)" % world.dirty_count())
	world.remesh_dirty()
	world.set_block(Vector3i(128, 5, 128), Blocks.GRASS)
	world.set_block(Vector3i(200, 20, 200), Blocks.AIR)
	world.remesh_dirty()

	# Props: un MultiMesh por región y malla; una edición toca un solo grupo.
	_check(props.group_count() > 100 and props.dirty_count() == 0,
			"los props se reparten en regiones (%d grupos para %d props)" % [props.group_count(), props.props.size()])
	var prop_cell := Vector3i(230, world.column_height(230, 40), 40)
	props.set_prop(prop_cell, {})
	props.rebuild_dirty()
	props.set_prop(prop_cell, PropLayer.make_prop(PropLibrary.ROCK, 1, 2))
	_check(props.dirty_count() == 1, "colocar un prop ensucia un solo grupo")
	props.rebuild_dirty()
	_check(PropLayer.region_of(prop_cell) != PropLayer.region_of(Vector3i(10, 5, 10)), "celdas lejanas caen en regiones distintas")
	var picked: Dictionary = props.pick(Vector3(230.5, 30.0, 40.5), Vector3.DOWN, 100.0)
	_check(not picked.is_empty() and picked["cell"] == prop_cell, "seleccionar un prop en una región lejana")
	t0 = Time.get_ticks_usec()
	for i: int in 20:
		props.pick(Vector3(-20.0, 60.0, -20.0), Vector3(1.0, -0.25, 1.0), 600.0)
	print("  buscar un prop con un rayo que cruza todo el mapa: %.2f ms" % (float(Time.get_ticks_usec() - t0) / 20000.0))

	# Punto de aparición dentro del mapa, también lejos del origen.
	var spawn: Vector3 = Player.find_spawn(world, props, 250, 250)
	_check(world.in_bounds(Vector3i(floori(spawn.x), floori(spawn.y), floori(spawn.z))) and spawn.x > 240.0,
			"el punto de aparición sigue al tamaño del mapa %s" % str(spawn))

	# Modo juego: solo se simulan las criaturas cercanas.
	var play := PlayMode.new()
	play.setup(world, props, entities, entities.library)
	_tree.get_root().add_child(play)
	play.start(0, Player.find_spawn(world, props, 20, 20), false)
	play.rng.seed = 5
	t0 = Time.get_ticks_usec()
	for i: int in 600:
		play.simulate(1.0 / 30.0, Vector3.ZERO, false, false)
	var per_step: float = float(Time.get_ticks_usec() - t0) / 600000.0
	var moved_far: int = 0
	var far_total: int = 0
	var player_pos: Vector3 = play.player.body.pos
	for actor: EntityActor in entities.actors():
		var dist: float = Vector2(actor.home.x - player_pos.x, actor.home.z - player_pos.z).length()
		if dist > PlayMode.SIMULATION_RADIUS + EntityActor.LEASH + 1.0:
			far_total += 1
			if not actor.body.pos.is_equal_approx(actor.home) or actor.state != EntityActor.State.IDLE:
				moved_far += 1
	print("  modo juego en L: %d criaturas, %d simuladas, %.3f ms por paso" % [
			entities.entities.size(), play.simulated_count, per_step])
	_check(far_total > 50 and moved_far == 0, "las %d criaturas lejanas no se simulan" % far_total)
	_check(play.simulated_count < entities.entities.size() / 2.0, "se simula solo una parte (%d de %d)" % [
			play.simulated_count, entities.entities.size()])
	play.stop()
	entities.reset_actors()

	# Guardar y cargar L.
	MapIO.ensure_maps_dir()
	var path: String = MapIO.MAPS_DIR + "/_autoprueba_l.json"
	var original: Dictionary = MapIO.serialize(world, props, 77, entities)
	t0 = Time.get_ticks_msec()
	_check(MapIO.save_file(path, world, props, 77, entities).is_empty(), "L: guardar")
	var t_save: int = Time.get_ticks_msec() - t0
	var size_kb: int = 0
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file != null:
		@warning_ignore("integer_division")
		size_kb = file.get_length() / 1024
		file.close()
	var world2: VoxelWorld = _new_world(64)
	var props2: PropLayer = _new_props()
	var entities2: EntityLayer = _new_entities()
	t0 = Time.get_ticks_msec()
	var result: Dictionary = MapIO.load_file(path, world2, props2, entities2)
	var t_load: int = Time.get_ticks_msec() - t0
	_check(result["ok"] and world2.size_x == 256 and world2.size_z == 256, "L: cargar (%s)" % str(result["error"]))
	_check(MapIO.serialize(world2, props2, 77, entities2) == original, "L: el mapa cargado es idéntico al guardado")
	t0 = Time.get_ticks_msec()
	var rounds: int = 0
	while world2.remesh_pending(8) > 0:
		rounds += 1
	print("  L: archivo de %d KB, guardar %d ms, leer %d ms, mallas %d ms en %d pasos" % [
			size_kb, t_save, t_load, Time.get_ticks_msec() - t0, rounds])
	_check(world2.pending_count() == 0 and rounds > 10, "L: las mallas del mapa cargado se arman por partes")
	DirAccess.remove_absolute(path)

	# Reemplazar el mapa libera el anterior y vacía el historial.
	var controller := EditorController.new()
	controller.setup(world2, props2, null, entities2)
	controller.apply_block(Vector3i(100, 20, 100), Blocks.STONE)
	_check(controller.can_undo(), "hay historial antes de reemplazar el mapa")
	controller.clear_history()
	world2.clear(Vector3i(64, 32, 64))
	props2.clear()
	props2.rebuild_dirty()
	entities2.clear()
	_check(not controller.can_undo() and not controller.can_redo(), "el historial queda vacío")
	_check(world2.chunks.is_empty() and world2.get_chunk_mesh(Vector3i(6, 0, 6)) == null and world2.pending_count() == 0,
			"el mundo anterior se libera (sin chunks ni mallas)")
	_check(props2.props.is_empty() and props2.group_count() == 0 and entities2.actors().is_empty(),
			"también sus props y criaturas")
	controller.free()
	for node: Node in [world, props, entities, world2, props2, entities2, play]:
		node.queue_free()


func _test_other_sizes() -> void:
	print("[mapas de otros tamaños]")
	# Un mapa que no es S, M ni L (48 x 80) también se guarda, se carga y se puede usar.
	var world: VoxelWorld = _new_world(64)
	world.clear(Vector3i(48, 32, 80))
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	MeadowGenerator.generate(world, props, 31, entities)
	_check(world.chunks.size() == 15, "un mundo de 48 x 80 usa 3 x 5 chunks (hay %d)" % world.chunks.size())
	var data: Dictionary = MapIO.serialize(world, props, 31, entities)
	var world2: VoxelWorld = _new_world(256)
	var props2: PropLayer = _new_props()
	var entities2: EntityLayer = _new_entities()
	var json := JSON.new()
	json.parse(JSON.stringify(data))
	var result: Dictionary = MapIO.deserialize(json.data, world2, props2, entities2)
	_check(result["ok"], "se carga sin rechazarlo (%s)" % str(result["error"]))
	_check(world2.size_x == 48 and world2.size_z == 80 and not world2.in_bounds(Vector3i(48, 0, 0))
			and world2.in_bounds(Vector3i(47, 0, 79)), "el mundo toma el tamaño del archivo")
	_check(MapIO.serialize(world2, props2, 31, entities2) == data, "y su contenido")
	_check(AppConfig.world_label(48, 80) == "48 × 80", "se muestra con sus dimensiones")
	var spawn: Vector3 = Player.find_spawn(world2, props2, 200, 200)
	_check(spawn.x < 48.0 and spawn.z < 80.0, "el punto de aparición queda dentro del mapa %s" % str(spawn))
	var camera := EditorCamera.new()
	for side: int in [64, 256]:
		camera.frame_world(Vector3(side, 32, side), 6.0)
		_check(camera.max_distance >= camera.distance and camera.far > camera.distance + side * 1.5
				and camera.focus.is_equal_approx(Vector3(side * 0.5, 6.0, side * 0.5)),
				"la cámara encuadra un mapa de %d: distancia %.0f, máximo %.0f, plano lejano %.0f" % [
				side, camera.distance, camera.max_distance, camera.far])
	camera.distance = 1.0
	camera.update_view()
	_check(is_equal_approx(camera.distance, EditorCamera.MIN_DISTANCE), "y se puede acercar hasta el nivel de los bloques")
	camera.free()
	for node: Node in [world, props, entities, world2, props2, entities2]:
		node.queue_free()
