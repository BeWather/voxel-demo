extends RefCounted
## Tercera parte de la autoprueba: archivos de objetos, biblioteca de props dinámica, objetos
## propios dentro de un mapa y el modelo del editor de objetos. La ejecuta tests/selftest.gd.

## Carpeta de objetos solo para la prueba: nunca se toca la `user://props/` real.
const TEST_PROPS_DIR: String = "user://_autoprueba_props"

var checks: int = 0
var failures: int = 0
var _tree: SceneTree


func run(tree: SceneTree) -> void:
	_tree = tree
	_test_prop_files()
	_test_custom_props_in_maps()
	_test_object_model()


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


## Sin `library` usa solo los props incorporados: lo que haya en `user://props/` no influye.
func _new_props(library: PropLibrary = null) -> PropLayer:
	var props := PropLayer.new()
	props.library = library if library != null else PropLibrary.new("")
	_tree.get_root().add_child(props)
	return props



func _clean_test_props() -> void:
	for path: String in PropIO.list_files(TEST_PROPS_DIR):
		DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(TEST_PROPS_DIR):
		DirAccess.remove_absolute(TEST_PROPS_DIR)


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Dos variantes chicas con colores de 8 bits y voxeles en los extremos del volumen.
func _sample_variants() -> Array[Dictionary]:
	var a: Dictionary[int, Color] = {}
	a[PropLibrary.voxel_key(0, 0, 0)] = Color.html("6b4a2b")
	a[PropLibrary.voxel_key(0, 1, 0)] = Color.html("6b4a2b")
	a[PropLibrary.voxel_key(-1, 2, 1)] = Color.html("33aa44")
	a[PropLibrary.voxel_key(PropLibrary.MIN_XZ, 0, PropLibrary.MIN_XZ)] = Color.html("ff0000")
	a[PropLibrary.voxel_key(PropLibrary.MAX_XZ, PropLibrary.MAX_Y, PropLibrary.MAX_XZ)] = Color.html("0000ff")
	var b: Dictionary[int, Color] = {}
	b[PropLibrary.voxel_key(0, 0, 0)] = Color.html("808080")
	b[PropLibrary.voxel_key(1, 0, 0)] = Color.html("33aa44")
	var variants: Array[Dictionary] = [a, b]
	return variants


func _test_prop_files() -> void:
	print("[archivos de objetos]")
	_clean_test_props()
	PropIO.ensure_dir(TEST_PROPS_DIR)
	var variants: Array[Dictionary] = _sample_variants()

	# Ida y vuelta de un archivo.
	var path: String = PropIO.path_for(TEST_PROPS_DIR, "arbol_de_prueba")
	_check(PropIO.save_file(path, "arbol_de_prueba", "Árbol de prueba", variants).is_empty(), "save_file sin errores")
	var loaded: Dictionary = PropIO.load_file(path)
	_check(loaded["ok"], "load_file sin errores (%s)" % str(loaded["error"]))
	_check(loaded["key"] == "arbol_de_prueba" and loaded["name"] == "Árbol de prueba", "clave y nombre se conservan")
	var loaded_variants: Array[Dictionary] = loaded["variants"]
	_check(loaded_variants.size() == 2 and loaded_variants[0] == variants[0] and loaded_variants[1] == variants[1],
			"voxeles y colores coinciden tras guardar y cargar")
	var raw: Dictionary = PropIO.serialize("arbol_de_prueba", "Árbol de prueba", variants)
	var first: Dictionary = raw["variants"][0]
	_check(first["palette"].size() == 4 and first["voxels"].size() == 5 * 4,
			"formato compacto: paleta de 4 colores y 5 voxeles de 4 números")

	# Los colores que no son de 8 bits se redondean igual al guardar que en memoria.
	var soft: Dictionary[int, Color] = {}
	soft[PropLibrary.voxel_key(0, 0, 0)] = Color(0.123456, 0.5, 0.987654)
	var soft_variants: Array[Dictionary] = [soft]
	var quantized: Array[Dictionary] = PropIO.quantize_variants(soft_variants)
	var back: Dictionary = PropIO.deserialize(JSON.parse_string(JSON.stringify(
			PropIO.serialize("suave", "Suave", soft_variants))))
	var back_variants: Array[Dictionary] = back["variants"]
	_check(back["ok"] and back_variants[0] == quantized[0], "un color fraccionario se redondea a 8 bits de forma estable")

	# Archivos inválidos: se rechazan con mensaje.
	var future: Dictionary = raw.duplicate(true)
	future["version"] = 99
	var rejected: Dictionary = PropIO.deserialize(future)
	_check(not rejected["ok"] and not str(rejected["error"]).is_empty(),
			"una versión desconocida se rechaza (%s)" % str(rejected["error"]))
	var outside: Dictionary = raw.duplicate(true)
	outside["variants"][0]["voxels"] = [PropLibrary.MAX_XZ + 1, 0, 0, 0]
	_check(not PropIO.deserialize(outside)["ok"], "un voxel fuera del volumen se rechaza")
	var bad_index: Dictionary = raw.duplicate(true)
	bad_index["variants"][0]["voxels"] = [0, 0, 0, 9]
	_check(not PropIO.deserialize(bad_index)["ok"], "un índice de paleta fuera de rango se rechaza")
	_check(not PropIO.deserialize([1, 2, 3])["ok"] and not PropIO.deserialize({"format": "otro"})["ok"],
			"datos que no son un objeto se rechazan")

	# Claves derivadas del nombre.
	_check(PropIO.slugify("  Árbol seco Ñandú #2!! ") == "arbol_seco_nandu_2", "slugify: minúsculas, ASCII y guiones bajos")
	_check(PropIO.slugify("¿¡!?").is_empty(), "slugify de un nombre sin letras ni números da vacío")
	_check(PropIO.is_valid_key("flor_roja") and not PropIO.is_valid_key("Flor Roja") and not PropIO.is_valid_key(""),
			"is_valid_key")

	# La biblioteca saltea los archivos rotos sin caerse.
	_write_text(PropIO.path_for(TEST_PROPS_DIR, "roto"), "{ esto no es json")
	future["key"] = "del_futuro"
	_write_text(PropIO.path_for(TEST_PROPS_DIR, "del_futuro"), JSON.stringify(future))
	_write_text(PropIO.path_for(TEST_PROPS_DIR, "otro_nombre"), JSON.stringify(raw))
	print("  (las 3 advertencias de \"Objeto omitido\" que siguen son esperadas)")
	var library := PropLibrary.new(TEST_PROPS_DIR)
	_check(library.load_warnings.size() == 3, "3 archivos inválidos omitidos con aviso (hubo %d)" % library.load_warnings.size())
	_check(library.count() == PropLibrary.BUILTIN_COUNT + 1, "el archivo válido se agrega como objeto nuevo")
	for bad: String in ["roto", "del_futuro", "otro_nombre"]:
		DirAccess.remove_absolute(PropIO.path_for(TEST_PROPS_DIR, bad))

	# Objeto propio: id válido después de los incorporados, malla y datos derivados.
	var custom: int = library.key_to_id("arbol_de_prueba")
	_check(custom == PropLibrary.BUILTIN_COUNT and library.is_valid(custom), "el objeto propio recibe el id %d" % custom)
	_check(library.prop_name(custom) == "Árbol de prueba" and not library.is_builtin(custom), "con su nombre, y no es incorporado")
	_check(library.variant_count(custom) == 2, "tiene sus 2 variantes")
	_check(library.get_mesh(custom, 0).get_surface_count() == 1 and library.get_mesh(custom, 1).get_surface_count() == 1,
			"cada variante tiene malla")
	_check(library.get_voxels(custom, 0) == variants[0], "get_voxels devuelve el modelo guardado")
	_check(is_equal_approx(library.pick_height(custom), (PropLibrary.MAX_Y + 1) * PropLibrary.VOXEL)
			and is_equal_approx(library.pick_radius(custom), PropLibrary.MAX_PICK_RADIUS),
			"la caja de selección sale de los voxeles (alto %.2f, radio %.2f)" % [
			library.pick_height(custom), library.pick_radius(custom)])
	var only_one: bool = true
	for i: int in 30:
		if library.random_variant(custom) > 1:
			only_one = false
	_check(only_one, "random_variant respeta la cantidad real de variantes")

	# Los incorporados no cambian por tener objetos propios.
	var pristine := PropLibrary.new("")
	_check(pristine.count() == PropLibrary.BUILTIN_COUNT and pristine.key_to_id("arbol_de_prueba") == -1,
			"sin carpeta solo están los incorporados")
	_check(library.key_to_id("roble") == PropLibrary.OAK and library.key_to_id("tronco") == PropLibrary.LOG
			and library.get_voxels(PropLibrary.OAK, 2) == pristine.get_voxels(PropLibrary.OAK, 2),
			"los incorporados conservan clave, orden y modelo")
	_check(library.swatch(PropLibrary.FLOWER_RED).r > 0.7 and library.swatch(PropLibrary.FLOWER_RED).g < 0.4
			and library.swatch(PropLibrary.OAK).g > library.swatch(PropLibrary.OAK).r,
			"el color de muestra sale del modelo (flor roja: roja; roble: verde)")

	# Guardar sobre un incorporado lo reemplaza; restaurarlo vuelve al original.
	var changed: Array[int] = []
	library.prop_changed.connect(func(id: int) -> void: changed.append(id))
	var rock: Dictionary[int, Color] = {}
	rock[PropLibrary.voxel_key(0, 0, 0)] = Color.html("112233")
	var rock_variants: Array[Dictionary] = [rock]
	var result: Dictionary = library.save_prop("roca", "Roca", rock_variants)
	_check(result["ok"] and result["id"] == PropLibrary.ROCK, "save_prop sobre un incorporado conserva su id")
	_check(library.is_overridden(PropLibrary.ROCK) and library.variant_count(PropLibrary.ROCK) == 1
			and library.count() == PropLibrary.BUILTIN_COUNT + 1, "queda reemplazado, con 1 variante, sin agregar objetos")
	_check(library.get_mesh(PropLibrary.ROCK, 2) == library.get_mesh(PropLibrary.ROCK, 0),
			"una variante que ya no existe usa la última disponible")
	_check(changed == [PropLibrary.ROCK], "se avisa el cambio con prop_changed")
	var reloaded := PropLibrary.new(TEST_PROPS_DIR)
	_check(reloaded.is_overridden(PropLibrary.ROCK) and reloaded.get_voxels(PropLibrary.ROCK, 0) == rock
			and reloaded.key_to_id("arbol_de_prueba") == custom, "al reiniciar, el reemplazo y el objeto propio siguen ahí")
	_check(library.restore_builtin(PropLibrary.ROCK).is_empty(), "restore_builtin sin errores")
	_check(not FileAccess.file_exists(PropIO.path_for(TEST_PROPS_DIR, "roca")), "se borró el archivo del reemplazo")
	_check(not library.is_overridden(PropLibrary.ROCK) and library.variant_count(PropLibrary.ROCK) == 3
			and library.get_voxels(PropLibrary.ROCK, 1) == pristine.get_voxels(PropLibrary.ROCK, 1),
			"vuelve el modelo procedural con sus 3 variantes")
	_check(not library.restore_builtin(custom).is_empty(), "un objeto propio no se puede \"restaurar\"")

	# Guardados inválidos.
	var empty: Dictionary[int, Color] = {}
	var with_empty: Array[Dictionary] = [rock, empty]
	_check(not library.save_prop("vacio", "Vacío", with_empty)["ok"], "una variante vacía no se guarda")
	_check(not library.save_prop("Clave Mala", "x", rock_variants)["ok"], "una clave inválida no se guarda")
	var too_many: Array[Dictionary] = []
	for i: int in PropLibrary.MAX_VARIANTS + 1:
		too_many.append(rock)
	_check(not library.save_prop("muchas", "Muchas", too_many)["ok"], "más de %d variantes no se guardan" % PropLibrary.MAX_VARIANTS)
	_check(library.count() == PropLibrary.BUILTIN_COUNT + 1, "los rechazos no agregan objetos")
	_clean_test_props()


func _test_custom_props_in_maps() -> void:
	print("[objetos propios en el mapa]")
	_clean_test_props()
	var library := PropLibrary.new(TEST_PROPS_DIR)
	var custom: int = library.save_prop("arbol_de_prueba", "Árbol de prueba", _sample_variants())["id"]
	var world: VoxelWorld = _new_world()
	var props: PropLayer = _new_props(library)
	world.set_block(Vector3i(4, 0, 4), Blocks.GRASS)
	world.set_block(Vector3i(6, 0, 4), Blocks.GRASS)
	var custom_cell := Vector3i(4, 1, 4)
	var oak_cell := Vector3i(6, 1, 4)
	props.set_prop(custom_cell, PropLayer.make_prop(custom, 1, 2))
	props.set_prop(oak_cell, PropLayer.make_prop(PropLibrary.OAK, 2, 0))
	props.rebuild_dirty()
	_check(props.dirty_count() == 0 and props.get_child_count() == 2, "el objeto propio se dibuja con su MultiMesh")
	var picked: Dictionary = props.pick(Vector3(4.5, 10.0, 4.5), Vector3.DOWN, 100.0)
	_check(not picked.is_empty() and picked["cell"] == custom_cell, "se puede seleccionar con el mouse")
	props.refresh_prop(custom)
	_check(props.dirty_count() == 1, "refresh_prop marca solo las mallas de ese objeto")
	props.rebuild_dirty()

	var controller := EditorController.new()
	controller.setup(world, props, null)
	controller.set_prop(custom)
	_check(controller.prop_id == custom and controller.prop_variant < 2, "el controlador acepta el id del objeto propio")
	controller.set_prop(999)
	_check(controller.prop_id == custom, "y rechaza un id inexistente")
	controller.free()

	# El mapa guarda la clave de texto y se vuelve a cargar igual.
	var data: Dictionary = MapIO.serialize(world, props, 5)
	var keys: Array = []
	for entry: Dictionary in data["props"]:
		keys.append(entry["id"])
	_check(keys.has("arbol_de_prueba") and keys.has("roble"), "el mapa guarda las claves de texto %s" % str(keys))
	MapIO.ensure_maps_dir()
	var path: String = MapIO.MAPS_DIR + "/_autoprueba_objetos.json"
	_check(MapIO.save_file(path, world, props, 5).is_empty(), "save_file sin errores")
	var world2: VoxelWorld = _new_world()
	var props2: PropLayer = _new_props(library)
	var result: Dictionary = MapIO.load_file(path, world2, props2)
	_check(result["ok"] and str(result["warning"]).is_empty(), "load_file sin errores ni avisos")
	_check(props2.props == props.props, "el prop propio vuelve con su tipo, variante y rotación")

	# Sin ese objeto en la biblioteca: el mapa carga igual y el prop se omite con aviso.
	var world3: VoxelWorld = _new_world()
	var props3: PropLayer = _new_props()
	result = MapIO.load_file(path, world3, props3)
	_check(result["ok"], "un mapa con un objeto desconocido carga igual")
	_check(str(result["warning"]).contains("arbol_de_prueba"), "y lo avisa: %s" % str(result["warning"]))
	_check(props3.props.size() == 1 and props3.has_prop(oak_cell) and not props3.has_prop(custom_cell),
			"solo se omite el prop desconocido")
	_check(world3.get_block(Vector3i(4, 0, 4)) == Blocks.GRASS, "los bloques se cargan completos")

	# Variante fuera de rango: se ajusta y se avisa.
	var tweaked: Dictionary = data.duplicate(true)
	for entry: Dictionary in tweaked["props"]:
		entry["variant"] = 7
	result = MapIO.deserialize(tweaked, world2, props2)
	_check(result["ok"] and not str(result["warning"]).is_empty(), "una variante fuera de rango no impide cargar: %s"
			% str(result["warning"]))
	_check(props2.get_prop(custom_cell)["variant"] == 1 and props2.get_prop(oak_cell)["variant"] == 2,
			"queda en la última variante de cada objeto")
	props2.rebuild_dirty()

	DirAccess.remove_absolute(path)
	for node: Node in [world, props, world2, props2, world3, props3]:
		node.queue_free()
	_clean_test_props()


func _test_object_model() -> void:
	print("[editor de objetos: modelo]")
	var red := Color.html("cc2222")
	var green := Color.html("22aa33")
	var model := ObjectModel.new()
	_check(model.set_voxel(Vector3i(0, 0, 0), red) and model.has_voxel(Vector3i(0, 0, 0)), "set_voxel coloca un voxel")
	_check(not model.set_voxel(Vector3i(0, 0, 0), red), "repetir el mismo color no es un cambio")
	_check(not model.set_voxel(Vector3i(PropLibrary.MAX_XZ + 1, 0, 0), red)
			and not model.set_voxel(Vector3i(0, PropLibrary.MAX_Y + 1, 0), red)
			and not model.set_voxel(Vector3i(0, -1, 0), red)
			and not model.set_voxel(Vector3i(0, 0, PropLibrary.MIN_XZ - 1), red), "fuera del volumen se rechaza")
	_check(model.set_voxel(Vector3i(PropLibrary.MIN_XZ, PropLibrary.MAX_Y, PropLibrary.MAX_XZ), red),
			"las esquinas del volumen son válidas")
	model.undo()
	_check(model.count() == 1 and model.can_undo() and model.can_redo(), "cada cambio suelto es un paso de deshacer")

	# Un trazo completo es un solo paso.
	var before: Dictionary[int, Color] = model.voxels.duplicate()
	var revision: int = model.revision
	model.begin_stroke()
	model.set_voxel(Vector3i(1, 0, 0), red)
	model.set_voxel(Vector3i(2, 0, 0), red)
	model.set_voxel(Vector3i(2, 0, 0), green)
	model.erase_voxel(Vector3i(0, 0, 0))
	_check(model.stroke_touched(Vector3i(2, 0, 0)) and not model.stroke_touched(Vector3i(5, 0, 0)), "el trazo recuerda qué tocó")
	_check(model.end_stroke(), "el trazo con cambios genera un paso")
	var after: Dictionary[int, Color] = model.voxels.duplicate()
	_check(model.count() == 2 and model.get_voxel(Vector3i(2, 0, 0)) == green and not model.has_voxel(Vector3i(0, 0, 0)),
			"colocar, repintar y borrar dentro del trazo")
	_check(model.revision > revision, "la revisión avanza con los cambios")
	_check(not model.can_redo(), "un trazo nuevo vacía la pila de rehacer")
	_check(model.undo() and model.voxels == before, "un deshacer revierte todo el trazo")
	_check(model.redo() and model.voxels == after, "rehacer lo vuelve a aplicar")
	_check(not model.redo(), "no queda nada para rehacer")
	model.undo()
	model.undo()
	_check(model.count() == 0 and not model.can_undo() and not model.undo(), "deshacer hasta el modelo vacío")
	model.redo()
	model.redo()
	_check(model.voxels == after, "y rehacer hasta el final")

	# Un trazo sin cambio neto no entra al historial.
	model.clear_history()
	model.begin_stroke()
	model.set_voxel(Vector3i(9, 9, 9), red)
	model.erase_voxel(Vector3i(9, 9, 9))
	_check(not model.end_stroke() and not model.can_undo() and model.voxels == after, "un trazo sin cambio neto no genera paso")

	# Colores usados, del más al menos frecuente.
	model.set_voxel(Vector3i(3, 0, 0), green)
	var colors: Array[Color] = model.used_colors()
	_check(colors.size() == 2 and colors[0] == green and colors[1] == red, "used_colors ordena por frecuencia")
	var box: AABB = model.bounds()
	_check(box.position == Vector3(1, 0, 0) and box.size == Vector3(3, 1, 1), "bounds abarca el modelo")

	# Raycast contra el diccionario de voxeles (sin física).
	var solo := ObjectModel.new()
	solo.set_voxel(Vector3i(-3, 4, 2), red)
	var hit: Dictionary = solo.raycast(Vector3(-2.5, 30.0, 2.5), Vector3.DOWN)
	_check(hit["hit"] and hit["cell"] == Vector3i(-3, 4, 2) and hit["normal"] == Vector3i.UP, "rayo hacia abajo: cara superior")
	_check(is_equal_approx(hit["distance"], 25.0), "distancia 25 (da %s)" % str(hit["distance"]))
	hit = solo.raycast(Vector3(-60.0, 4.5, 2.5), Vector3.RIGHT)
	_check(hit["hit"] and hit["cell"] == Vector3i(-3, 4, 2) and hit["normal"] == Vector3i(-1, 0, 0), "rayo desde afuera: cara -X")
	hit = solo.raycast(Vector3(-2.5, 4.5, 40.0), Vector3(0, 0, -1))
	_check(hit["hit"] and hit["normal"] == Vector3i(0, 0, 1), "cara +Z")
	hit = solo.raycast(Vector3(10.5, 30.0, -7.5), Vector3.DOWN)
	_check(not hit["hit"] and hit["floor"] and hit["cell"] == Vector3i(10, 0, -8) and hit["normal"] == Vector3i.UP,
			"sin voxeles en el camino, el rayo llega a la cuadrícula del piso")
	hit = solo.raycast(Vector3(100.0, 30.0, 0.5), Vector3.DOWN)
	_check(not hit["hit"] and not hit["floor"], "fuera del volumen no toca nada")
	hit = solo.raycast(Vector3(0.5, 10.0, 0.5), Vector3.UP)
	_check(not hit["hit"] and not hit["floor"], "un rayo hacia arriba no toca el piso")

	# El editor a nivel de datos: abrir, editar, variantes, guardar como y guardar encima.
	_clean_test_props()
	var library := PropLibrary.new(TEST_PROPS_DIR)
	var editor := ObjectEditor.new()
	editor.setup(library)
	_check(editor.is_new() and editor.variant_count() == 1 and editor.model().count() == 0, "arranca con un objeto nuevo y vacío")
	_check(not editor.save().is_empty(), "un objeto nuevo no se guarda sin nombre")
	editor.open_object(PropLibrary.FLOWER_RED, 1)
	_check(editor.object_key == "flor_roja" and editor.variant == 1 and editor.variant_count() == 3 and not editor.modified,
			"abrir un incorporado trae sus 3 variantes")
	var quantized: Array[Dictionary] = PropIO.quantize_variants(library.get_variants(PropLibrary.FLOWER_RED))
	_check(editor.model().voxels == quantized[1], "con el modelo de la variante elegida")
	var top := Vector3i(0, 20, 0)
	editor.model().set_voxel(top, green)
	editor.add_variant()
	_check(editor.variant_count() == 4 and editor.variant == 3 and editor.modified and editor.model().has_voxel(top),
			"agregar variante duplica la actual y pasa a editarla")
	editor.model().erase_voxel(top)
	editor.set_variant(1)
	_check(editor.model().has_voxel(top), "cada variante tiene su propio modelo")
	editor.undo()
	_check(not editor.model().has_voxel(top) and editor.can_redo(), "deshacer actúa sobre la variante activa")
	editor.redo()
	editor.set_variant(3)
	editor.remove_variant()
	_check(editor.variant_count() == 3 and editor.variant == 2, "quitar variante")
	_check(editor.save_as("Flor de prueba", "flor_de_prueba").is_empty(), "guardar como objeto nuevo")
	var copy: int = library.key_to_id("flor_de_prueba")
	_check(copy == PropLibrary.BUILTIN_COUNT and editor.object_key == "flor_de_prueba" and not editor.modified,
			"el objeto nuevo queda en la biblioteca y pasa a ser el abierto")
	_check(library.get_voxels(copy, 1).has(PropLibrary.voxel_key(top.x, top.y, top.z))
			and not library.is_overridden(PropLibrary.FLOWER_RED)
			and library.get_voxels(PropLibrary.FLOWER_RED, 1) == PropLibrary.new("").get_voxels(PropLibrary.FLOWER_RED, 1),
			"con la edición, y sin tocar el original")
	editor.open_object(PropLibrary.MUSHROOM)
	editor.remove_variant()
	editor.remove_variant()
	editor.remove_variant()
	_check(editor.variant_count() == 1 and not editor.can_remove_variant(), "nunca se quita la última variante")
	editor.model().set_voxel(top, red)
	_check(editor.save().is_empty() and library.is_overridden(PropLibrary.MUSHROOM)
			and library.variant_count(PropLibrary.MUSHROOM) == 1 and editor.can_restore(),
			"guardar sobre un incorporado lo reemplaza con todas sus variantes")
	_check(editor.restore_original().is_empty() and editor.variant_count() == 3 and not editor.can_restore()
			and not editor.model().has_voxel(top), "restaurar original recarga el modelo procedural")
	editor.free()
	_clean_test_props()
	_check(not DirAccess.dir_exists_absolute(TEST_PROPS_DIR), "la prueba no deja archivos")
