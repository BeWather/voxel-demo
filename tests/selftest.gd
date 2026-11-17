extends SceneTree
## Autoprueba sin ventana. Ejecutar con:
##   godot --headless --path <proyecto> --script res://tests/selftest.gd

const PlayTests := preload("res://tests/selftest_play.gd")
const ObjectTests := preload("res://tests/selftest_objects.gd")
const SizeTests := preload("res://tests/selftest_sizes.gd")
const RideTests := preload("res://tests/selftest_ride.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_test_blocks_and_chunks()
	_test_raycast()
	_test_generation_and_meshing()
	_test_save_load()
	_test_undo_redo()
	# Criaturas, mapa v2, jugador, animales y diálogos (tests/selftest_play.gd).
	var play_tests := PlayTests.new()
	play_tests.run(self)
	_checks += play_tests.checks
	_failures += play_tests.failures
	# Objetos editables: archivos, biblioteca dinámica y editor (tests/selftest_objects.gd).
	var object_tests := ObjectTests.new()
	object_tests.run(self)
	_checks += object_tests.checks
	_failures += object_tests.failures
	# Tamaños de mapa, mallado por partes y mapas grandes (tests/selftest_sizes.gd).
	var size_tests := SizeTests.new()
	size_tests.run(self)
	_checks += size_tests.checks
	_failures += size_tests.failures
	# Salir del agua, monturas, vuelo y herramienta mover (tests/selftest_ride.gd).
	var ride_tests := RideTests.new()
	ride_tests.run(self)
	_checks += ride_tests.checks
	_failures += ride_tests.failures
	print("")
	if _failures == 0:
		print("AUTOPRUEBA OK: %d comprobaciones." % _checks)
	else:
		print("AUTOPRUEBA FALLIDA: %d de %d comprobaciones fallaron." % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		_failures += 1
		print("  FALLA %s" % label)


func _new_world() -> VoxelWorld:
	var world := VoxelWorld.new()
	get_root().add_child(world)
	return world


func _new_props() -> PropLayer:
	var props := PropLayer.new()
	# Solo los props incorporados: lo que haya en `user://props/` no influye en la prueba.
	props.library = PropLibrary.new("")
	get_root().add_child(props)
	return props


func _test_blocks_and_chunks() -> void:
	print("[bloques y chunks]")
	var world: VoxelWorld = _new_world()
	_check(world.set_block(Vector3i(15, 5, 15), Blocks.STONE), "set_block en el borde del chunk")
	_check(world.set_block(Vector3i(16, 5, 16), Blocks.GRASS), "set_block en el chunk vecino")
	_check(world.set_block(Vector3i(0, 0, 0), Blocks.SAND), "set_block en el origen")
	_check(world.set_block(Vector3i(63, 31, 63), Blocks.WOOD), "set_block en la esquina opuesta")
	_check(world.get_block(Vector3i(15, 5, 15)) == Blocks.STONE, "get_block (15,5,15)")
	_check(world.get_block(Vector3i(16, 5, 16)) == Blocks.GRASS, "get_block (16,5,16)")
	_check(world.get_block(Vector3i(0, 0, 0)) == Blocks.SAND, "get_block (0,0,0)")
	_check(world.get_block(Vector3i(63, 31, 63)) == Blocks.WOOD, "get_block (63,31,63)")
	_check(world.get_block(Vector3i(14, 5, 15)) == Blocks.AIR, "la celda vecina sigue vacía")
	_check(not world.set_block(Vector3i(64, 0, 0), Blocks.STONE), "set_block fuera del mundo se rechaza")
	_check(not world.set_block(Vector3i(0, 32, 0), Blocks.STONE), "set_block sobre el límite de altura se rechaza")
	_check(world.get_block(Vector3i(-1, 0, 0)) == Blocks.AIR, "get_block fuera del mundo devuelve aire")
	_check(not world.set_block(Vector3i(15, 5, 15), Blocks.STONE), "set_block sin cambio devuelve false")
	# (15,5,15) y (0,0,0) comparten chunk; los otros dos caen en chunks distintos.
	_check(world.chunks.size() == 3, "se crearon 3 chunks (hay %d)" % world.chunks.size())

	world.remesh_dirty()
	world.set_block(Vector3i(15, 5, 15), Blocks.DIRT)
	_check(world.is_chunk_dirty(Vector3i(0, 0, 0)) and world.is_chunk_dirty(Vector3i(1, 0, 0))
			and world.is_chunk_dirty(Vector3i(0, 0, 1)) and world.is_chunk_dirty(Vector3i(1, 0, 1)),
			"editar en una esquina marca los chunks vecinos")
	_check(world.dirty_count() == 4, "exactamente 4 chunks sucios (hay %d)" % world.dirty_count())
	world.remesh_dirty()
	world.set_block(Vector3i(8, 8, 8), Blocks.STONE)
	world.set_block(Vector3i(9, 8, 8), Blocks.STONE)
	_check(world.dirty_count() == 1, "dos ediciones interiores ensucian un solo chunk")
	_check(world.remesh_dirty() == 1, "y se regenera una sola malla")
	_check(world.get_chunk_mesh(Vector3i(0, 0, 0)) != null, "el chunk tiene malla")
	world.queue_free()


func _test_raycast() -> void:
	print("[raycast]")
	var world: VoxelWorld = _new_world()
	world.set_block(Vector3i(10, 5, 10), Blocks.STONE)

	var hit: Dictionary = world.raycast(Vector3(10.5, 20.0, 10.5), Vector3.DOWN)
	_check(hit["hit"] and hit["cell"] == Vector3i(10, 5, 10), "rayo hacia abajo encuentra el bloque")
	_check(hit["normal"] == Vector3i(0, 1, 0), "normal +Y")
	_check(is_equal_approx(hit["distance"], 14.0), "distancia 14 (da %s)" % str(hit["distance"]))

	hit = world.raycast(Vector3(-5.0, 5.5, 10.5), Vector3.RIGHT)
	_check(hit["hit"] and hit["cell"] == Vector3i(10, 5, 10), "rayo desde afuera del mundo (+X)")
	_check(hit["normal"] == Vector3i(-1, 0, 0), "normal -X")

	hit = world.raycast(Vector3(20.5, 5.5, 10.5), Vector3.LEFT)
	_check(hit["hit"] and hit["normal"] == Vector3i(1, 0, 0), "normal +X")

	hit = world.raycast(Vector3(10.5, 5.5, 30.0), Vector3(0, 0, -1))
	_check(hit["hit"] and hit["normal"] == Vector3i(0, 0, 1), "normal +Z")

	hit = world.raycast(Vector3(10.5, 5.5, -3.0), Vector3(0, 0, 1))
	_check(hit["hit"] and hit["normal"] == Vector3i(0, 0, -1), "normal -Z")

	hit = world.raycast(Vector3(10.5, 2.5, 10.5), Vector3.UP)
	_check(hit["hit"] and hit["normal"] == Vector3i(0, -1, 0), "normal -Y")

	var from := Vector3(30.3, 25.7, 28.9)
	hit = world.raycast(from, Vector3(10.5, 6.0, 10.5) - from)
	_check(hit["hit"] and hit["cell"] == Vector3i(10, 5, 10) and hit["normal"] == Vector3i(0, 1, 0),
			"rayo en diagonal entra por la cara superior")

	hit = world.raycast(Vector3(10.5, 20.0, 12.5), Vector3.DOWN)
	_check(not hit["hit"], "rayo que no toca nada")
	hit = world.raycast(Vector3(-5.0, 50.0, -5.0), Vector3.UP)
	_check(not hit["hit"], "rayo que no entra al mundo")

	# Borde del mundo: un bloque en x = 0 visto desde afuera.
	world.set_block(Vector3i(0, 3, 7), Blocks.DIRT)
	hit = world.raycast(Vector3(-10.0, 3.5, 7.5), Vector3.RIGHT)
	_check(hit["hit"] and hit["cell"] == Vector3i(0, 3, 7) and hit["normal"] == Vector3i(-1, 0, 0),
			"bloque en el borde del mundo")
	world.queue_free()


func _test_generation_and_meshing() -> void:
	print("[generación y mallado]")
	var world: VoxelWorld = _new_world()
	var props: PropLayer = _new_props()
	var t0: int = Time.get_ticks_msec()
	MeadowGenerator.generate(world, props, 12345)
	var t_gen: int = Time.get_ticks_msec() - t0
	var remeshed: int = world.remesh_dirty()
	props.rebuild_dirty()
	var t_total: int = Time.get_ticks_msec() - t0
	print("  generación %d ms, total con mallas %d ms, %d chunks, %d props" % [
			t_gen, t_total, remeshed, props.props.size()])
	_check(t_total < 2000, "generar y mallar tarda menos de 2 s")

	var min_h: int = 999
	var max_h: int = 0
	var water: int = 0
	var sand: int = 0
	for z: int in world.size_z:
		for x: int in world.size_x:
			var h: int = world.column_height(x, z)
			min_h = mini(min_h, h)
			max_h = maxi(max_h, h)
			var top: int = world.get_block_xyz(x, h - 1, z)
			if top == Blocks.WATER:
				water += 1
			elif top == Blocks.SAND:
				sand += 1
	print("  alturas %d..%d, columnas de agua %d, de arena %d" % [min_h, max_h, water, sand])
	_check(min_h >= 3 and max_h <= 12, "alturas dentro del rango esperado")
	_check(water > 40, "hay un estanque")
	_check(sand > 20, "hay arena en la orilla")
	_check(props.props.size() > 100, "hay vegetación")

	var bad: int = 0
	var trees: int = 0
	for cell: Vector3i in props.props:
		var below: int = world.get_block(cell + Vector3i.DOWN)
		if world.get_block(cell) != Blocks.AIR or below != Blocks.GRASS:
			bad += 1
		var id: int = props.props[cell]["id"]
		if id == PropLibrary.OAK or id == PropLibrary.PINE:
			trees += 1
	_check(bad == 0, "todos los props están sobre pasto y en una celda de aire (%d mal)" % bad)
	_check(trees > 5 and trees < props.props.size() / 3.0, "los árboles son minoría (%d)" % trees)

	# Una edición puntual regenera pocos chunks.
	world.set_block(Vector3i(24, 20, 24), Blocks.STONE)
	var count: int = world.remesh_dirty()
	_check(count == 1, "editar un voxel interior regenera 1 chunk (fueron %d)" % count)

	# Tamaño de los modelos de props.
	var library: PropLibrary = props.library
	var oak: AABB = library.get_mesh(PropLibrary.OAK, 0).get_aabb()
	var pine: AABB = library.get_mesh(PropLibrary.PINE, 0).get_aabb()
	var flower: AABB = library.get_mesh(PropLibrary.FLOWER_RED, 0).get_aabb()
	var grass: AABB = library.get_mesh(PropLibrary.TALL_GRASS, 0).get_aabb()
	print("  alto roble %.2f, pino %.2f, flor %.2f, pasto alto %.2f" % [
			oak.size.y, pine.size.y, flower.size.y, grass.size.y])
	_check(oak.size.y >= 2.8 and oak.size.y <= 4.2, "el roble mide entre 3 y 4 bloques aprox.")
	_check(pine.size.y >= 2.8 and pine.size.y <= 4.2, "el pino mide entre 3 y 4 bloques aprox.")
	_check(flower.size.y < 1.0 and grass.size.y < 1.0, "flores y pasto alto miden menos de un bloque")
	_check(is_zero_approx(oak.position.y), "los modelos apoyan en y = 0")
	world.queue_free()
	props.queue_free()


func _test_save_load() -> void:
	print("[guardar y cargar]")
	var world: VoxelWorld = _new_world()
	var props: PropLayer = _new_props()
	MeadowGenerator.generate(world, props, 777)
	world.set_block(Vector3i(3, 20, 3), Blocks.SNOW)
	world.set_block(Vector3i(40, 25, 17), Blocks.PATH)
	var original: Dictionary = MapIO.serialize(world, props, 777)

	MapIO.ensure_maps_dir()
	var path: String = MapIO.MAPS_DIR + "/_autoprueba.json"
	_check(MapIO.save_file(path, world, props, 777).is_empty(), "save_file sin errores")

	var world2: VoxelWorld = _new_world()
	var props2: PropLayer = _new_props()
	var result: Dictionary = MapIO.load_file(path, world2, props2)
	_check(result["ok"], "load_file sin errores (%s)" % str(result["error"]))
	_check(result["seed"] == 777, "la semilla se conserva")

	var same_blocks: bool = Vector3i(world2.size_x, world2.size_y, world2.size_z) \
			== Vector3i(world.size_x, world.size_y, world.size_z)
	var compared: int = 0
	for y: int in world.size_y:
		for z: int in world.size_z:
			for x: int in world.size_x:
				compared += 1
				if world.get_block_xyz(x, y, z) != world2.get_block_xyz(x, y, z):
					same_blocks = false
	_check(same_blocks, "los %d voxeles coinciden" % compared)
	_check(world2.get_block(Vector3i(40, 25, 17)) == Blocks.PATH, "un bloque editado a mano se conserva")
	_check(props2.props.size() == props.props.size() and props2.props == props.props,
			"los %d props coinciden (celda, tipo, variante, rotación)" % props.props.size())
	_check(MapIO.serialize(world2, props2, 777) == original, "volver a serializar da el mismo resultado")

	# Versión desconocida: se rechaza sin tocar el mundo cargado.
	var future: Dictionary = original.duplicate(true)
	future["version"] = 99
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(future))
	file.close()
	result = MapIO.load_file(path, world2, props2)
	_check(not result["ok"], "una versión desconocida se rechaza")
	_check(not str(result["error"]).is_empty(), "con mensaje: %s" % str(result["error"]))
	_check(MapIO.serialize(world2, props2, 777) == original, "el mundo no cambia tras el rechazo")

	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ esto no es json")
	file.close()
	result = MapIO.load_file(path, world2, props2)
	_check(not result["ok"], "un archivo corrupto se rechaza (%s)" % str(result["error"]))
	result = MapIO.deserialize({"format": MapIO.FORMAT, "version": 1, "size": [64, 32, 64],
			"chunks": [{"pos": [0, 0, 0], "rle": [1, 10]}], "props": []}, world2, props2)
	_check(not result["ok"], "un chunk incompleto se rechaza (%s)" % str(result["error"]))
	DirAccess.remove_absolute(path)
	world.queue_free()
	props.queue_free()
	world2.queue_free()
	props2.queue_free()


func _test_undo_redo() -> void:
	print("[deshacer y rehacer]")
	var world: VoxelWorld = _new_world()
	var props: PropLayer = _new_props()
	MeadowGenerator.generate(world, props, 4242)
	var controller := EditorController.new()
	controller.setup(world, props, null)

	# Se busca un prop cualquiera y el bloque que lo sostiene.
	var prop_cell: Vector3i = props.props.keys()[0]
	var support: Vector3i = prop_cell + Vector3i.DOWN
	var other := Vector3i(5, 20, 5)
	var before: Dictionary = MapIO.serialize(world, props, 0)
	var prop_before: Dictionary = props.get_prop(prop_cell)

	# Trazo 1: borra el soporte (cae el prop) y coloca otro bloque.
	controller.begin_stroke()
	controller.apply_block(support, Blocks.AIR)
	controller.apply_block(other, Blocks.STONE)
	controller.end_stroke()
	var after: Dictionary = MapIO.serialize(world, props, 0)
	_check(world.get_block(support) == Blocks.AIR, "el soporte se borró")
	_check(not props.has_prop(prop_cell), "el prop sin soporte se quitó")
	_check(world.get_block(other) == Blocks.STONE, "el otro bloque se colocó")
	_check(controller.can_undo() and not controller.can_redo(), "hay un paso para deshacer")

	controller.undo()
	_check(MapIO.serialize(world, props, 0) == before, "deshacer restaura bloques y props")
	_check(props.get_prop(prop_cell) == prop_before, "el prop vuelve con su variante y rotación")
	_check(not controller.can_undo() and controller.can_redo(), "un solo paso cubría todo el trazo")

	controller.redo()
	_check(MapIO.serialize(world, props, 0) == after, "rehacer vuelve a aplicar el trazo")
	controller.undo()
	_check(MapIO.serialize(world, props, 0) == before, "deshacer otra vez vuelve al inicio")

	# Trazo 2: colocar un bloque en la celda de un prop lo quita en el mismo paso.
	controller.begin_stroke()
	controller.apply_block(prop_cell, Blocks.WOOD)
	controller.end_stroke()
	_check(not props.has_prop(prop_cell) and world.get_block(prop_cell) == Blocks.WOOD,
			"un bloque colocado sobre un prop lo reemplaza")
	_check(not controller.can_redo(), "un trazo nuevo vacía la pila de rehacer")
	controller.undo()
	_check(MapIO.serialize(world, props, 0) == before, "deshacer devuelve el prop tapado")

	# Trazo 3: props y varios cambios sobre la misma celda.
	var free_cell := Vector3i(-1, -1, -1)
	for z: int in world.size_z:
		for x: int in world.size_x:
			var cell := Vector3i(x, world.column_height(x, z), z)
			if free_cell.x < 0 and controller.can_place_prop(cell) and not props.has_prop(cell):
				free_cell = cell
	controller.begin_stroke()
	controller.apply_prop(free_cell, PropLayer.make_prop(PropLibrary.ROCK, 1, 3))
	controller.apply_block(other, Blocks.SNOW)
	controller.apply_block(other, Blocks.PATH)
	controller.end_stroke()
	_check(props.get_prop(free_cell) == PropLayer.make_prop(PropLibrary.ROCK, 1, 3), "prop colocado")
	controller.undo()
	_check(MapIO.serialize(world, props, 0) == before, "deshacer quita el prop y el bloque repintado")
	controller.redo()
	_check(world.get_block(other) == Blocks.PATH and props.has_prop(free_cell), "rehacer aplica el estado final")

	# Un trazo sin cambios no entra al historial.
	controller.clear_history()
	controller.begin_stroke()
	controller.apply_block(other, Blocks.PATH)
	controller.end_stroke()
	_check(not controller.can_undo(), "un trazo sin cambios no genera paso")
	_check(not controller.can_place_prop(Vector3i(0, 0, 0)), "no se puede colocar un prop dentro de un bloque")
	controller.free()
	world.queue_free()
	props.queue_free()
