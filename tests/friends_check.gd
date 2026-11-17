extends SceneTree
## Comprobación con ventana, solo de lo nuevo de amistad: juntar con E, dar de comer con F,
## corazones, nombre, seguir con G, marca de "sin guardar" y pregunta al cerrar.
##   godot --path <proyecto> --script res://tests/friends_check.gd
## Usa eventos de entrada sintéticos; la ventana queda fuera de la pantalla y no captura el mouse.

const SAVE_PATH: String = "user://maps/_prueba_amistad.json"

var _failures: int = 0
var _checks: int = 0
var _main: Node


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		_failures += 1
		print("  FALLA %s" % label)


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _hold(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(2)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.set("capture_mouse_in_play", false)
	get_root().add_child(_main)
	get_root().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	get_root().set_flag(Window.FLAG_NO_FOCUS, true)
	get_root().position = Vector2i(-6000, -6000)
	await _frames(5)
	var world: VoxelWorld = _main.get("world")
	var props: PropLayer = _main.get("props")
	var entities: EntityLayer = _main.get("entities")
	var controller: EditorController = _main.get("controller")
	var ui: EditorUI = _main.get("ui")
	var play: PlayMode = _main.get("play")
	var friends: PlayFriends = play.friends
	_main.call("_new_map", 2024)
	await _frames(5)

	# Un lugar llano y libre para la flor, la oveja y la niña.
	var spot := Vector3i(-1, -1, -1)
	for z: int in range(8, world.size_z - 8):
		for x: int in range(8, world.size_x - 8):
			var cell := Vector3i(x, world.column_height(x, z), z)
			var free: bool = spot.x < 0
			for dz: int in range(-1, 3):
				for dx: int in range(-1, 5):
					if free and not controller.is_free_cell(cell + Vector3i(dx, 0, dz)):
						free = false
			if free:
				spot = cell
	_check(spot.x >= 0, "hay un lugar llano para la prueba")
	if spot.x < 0:
		quit(1)
		return
	var flower: Vector3i = spot
	var sheep_cell: Vector3i = spot + Vector3i(3, 0, 0)

	print("[sin guardar]")
	_check(not _main.get("unsaved") and not ui.is_unsaved_shown(), "un mapa recién generado no tiene nada sin guardar")
	controller.apply_prop(flower, PropLayer.make_prop(PropLibrary.FLOWER_YELLOW, 0, 0))
	controller.apply_entity(sheep_cell, EntityLayer.make_entity(CharacterLibrary.SHEEP, 0, 0))
	await _frames(2)
	_check(_main.get("unsaved") and ui.is_unsaved_shown(), "después de editar aparece la marca «Sin guardar»")
	MapIO.ensure_maps_dir()
	_main.call("_on_save_path", SAVE_PATH)
	await _frames(2)
	_check(not _main.get("unsaved") and not ui.is_unsaved_shown() and FileAccess.file_exists(SAVE_PATH), "al guardar, la marca desaparece")
	var saved_map: Dictionary = MapIO.serialize(world, props, 0, entities)
	controller.clear_history()

	print("[juntar con E]")
	await _key(KEY_F5)
	await _key(KEY_ENTER)
	await _frames(30)
	_check(_main.get("mode") == 2 and play.active, "entra al modo juego")
	var sheep: EntityActor = entities.get_actor(sheep_cell)
	play.player.body.teleport(Vector3(flower) + Vector3(0.5, 0.0, 1.4))
	await _frames(6)
	_check(play.prompt_text() == "E: juntar flor amarilla", "junto a la flor: «%s»" % play.prompt_text())
	await _key(KEY_E)
	await _frames(4)
	var hud: BackpackHud = play.get("_backpack_hud")
	_check(friends.count(Items.FLOWER_YELLOW) == 1 and hud.visible and hud.shown_count(Items.FLOWER_YELLOW) == 1,
			"E la junta y la mochila en pantalla muestra 1")
	_check(props.has_prop(flower) and props.is_play_hidden(flower), "la flor deja de verse sin salir del mapa")
	_check(_main.get("unsaved") and not ui.visible, "juntar es progreso sin guardar")
	await _key(KEY_3)
	_check(friends.selected == 2 and hud.selected() == 2, "la tecla 3 elige el tercer casillero")
	await _key(KEY_5)
	_check(friends.selected == 4 and hud.selected() == 4, "la tecla 5, el quinto")

	print("[dar de comer con F]")
	friends.backpack["pasto"] = 2
	sheep.body.teleport(sheep.home)
	play.player.body.teleport(sheep.home + Vector3(1.5, 0.0, 0.0))
	await _frames(6)
	_check(play.prompt_text() == "F: dar pasto", "junto a la oveja: «%s»" % play.prompt_text())
	var overhead: EntityOverhead = friends.overhead_of(sheep)
	_check(overhead != null and overhead.visible and overhead.shows_bubble() and overhead.shown_hearts() == 0,
			"sobre la oveja se ve el globo con su comida y los corazones vacíos")
	await _key(KEY_F)
	await _frames(4)
	_check(sheep.hearts() == 1 and friends.count(Items.GRASS) == 1 and overhead.shown_hearts() == 1, "F le da pasto: sube a un corazón")
	sheep.body.teleport(sheep.home)
	play.player.body.teleport(sheep.home + Vector3(1.5, 0.0, 0.0))
	await _frames(4)
	await _key(KEY_F)
	await _frames(6)
	_check(sheep.hearts() == 2 and friends.count(Items.GRASS) == 0, "otra vez: dos corazones")
	var dialog: ConfirmationDialog = friends.get("_name_dialog")
	_check(friends.naming_actor == sheep and dialog != null and dialog.visible and play.is_dialog_open(),
			"aparece la ventana para ponerle nombre")
	var edit: LineEdit = friends.get("_name_edit")
	var suggested: String = edit.text
	_check(not suggested.is_empty() and dialog.ok_button_text == "Aceptar" and dialog.cancel_button_text == "Más tarde",
			"con un nombre sugerido («%s») y los botones Aceptar / Más tarde" % suggested)
	var still: Vector3 = play.player.body.pos
	await _hold(KEY_W, true)
	await _frames(20)
	await _hold(KEY_W, false)
	_check(play.player.body.pos.is_equal_approx(still), "mientras tanto el jugador no se mueve")
	dialog.get_ok_button().pressed.emit()
	await _frames(4)
	_check(not dialog.visible and friends.naming_actor == null and sheep.data["name"] == suggested, "Aceptar le pone ese nombre")
	_check(overhead.shown_hearts() == 2, "arriba se ven dos corazones")

	print("[seguir con G]")
	sheep.body.teleport(sheep.home)
	play.player.body.teleport(sheep.home + Vector3(1.5, 0.0, 0.0))
	await _frames(6)
	_check(play.prompt_text().contains("G: que te siga"), "el cartel ofrece «G: que te siga» («%s»)" % play.prompt_text())
	await _key(KEY_G)
	_check(sheep.is_following(), "G hace que la siga")
	var from: Vector3 = sheep.body.pos
	await _hold(KEY_W, true)
	await _frames(90)
	await _hold(KEY_W, false)
	await _frames(40)
	_check(sheep.body.pos.distance_to(from) > 1.5 and sheep.body.pos.distance_to(play.player.body.pos) < 4.5,
			"al caminar, la oveja va detrás (recorrió %.1f, quedó a %.1f)" % [sheep.body.pos.distance_to(from), sheep.body.pos.distance_to(play.player.body.pos)])

	print("[de vuelta en el editor]")
	await _key(KEY_ESCAPE)
	await _frames(4)
	_check(_main.get("mode") == 0 and ui.visible and ui.is_unsaved_shown(), "al volver, el editor marca que hay progreso sin guardar")
	_check(sheep.position.is_equal_approx(sheep.home) and sheep.cell == sheep_cell and not props.is_play_hidden(flower),
			"la oveja está en su celda y la flor se ve otra vez")
	var after: Dictionary = entities.get_entity(sheep_cell)
	_check(after["friendship"] == 8 and after["name"] == suggested and after["follow"] == true, "la criatura conserva corazones, nombre y seguir")
	_check(MapIO.serialize(world, props, 0, entities)["chunks"] == saved_map["chunks"]
			and MapIO.serialize(world, props, 0, entities)["props"] == saved_map["props"], "los bloques y los props no cambiaron")
	_check(not controller.can_undo(), "el progreso no entró al historial de deshacer")
	# En el editor, el nombre se ve al pasar por encima.
	controller.set_tool(EditorController.Tool.ENTITY_ERASE)
	var camera: EditorCamera = _main.get("camera")
	var point: Vector2 = camera.unproject_position(Vector3(sheep_cell) + Vector3(0.5, 0.5, 0.5))
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await _frames(4)
	var status: Label = ui.get("_status_label")
	_check(status.text.contains(suggested), "al pasar el mouse por la oveja, la línea de estado dice su nombre («%s»)" % status.text.get_slice("|", 1).strip_edges())

	print("[cerrar con cambios sin guardar]")
	_main.call("request_quit")
	await _frames(4)
	_check(_main.call("is_close_dialog_open"), "cerrar la ventana con cambios sin guardar pregunta antes de salir")
	var close_dialog: ConfirmationDialog = _main.get("_close_dialog")
	var labels: Array[String] = [close_dialog.ok_button_text, close_dialog.cancel_button_text]
	for child: Node in close_dialog.get_ok_button().get_parent().get_children():
		if child is Button and (child as Button).text == "Salir sin guardar":
			labels.append("Salir sin guardar")
	_check(labels == ["Guardar", "Cancelar", "Salir sin guardar"], "con los botones %s" % str(labels))
	close_dialog.get_cancel_button().pressed.emit()
	await _frames(3)
	_check(not _main.call("is_close_dialog_open") and _main.get("unsaved"), "Cancelar vuelve al editor sin perder nada")

	# Guardar escribe el progreso; cargar lo trae de vuelta.
	_main.call("_on_save_path", SAVE_PATH)
	await _frames(2)
	_check(not _main.get("unsaved") and not ui.is_unsaved_shown(), "guardar otra vez limpia la marca")
	_main.call("_new_map", 77)
	await _frames(4)
	var bag: Dictionary = _main.get("backpack")
	_check(bag["flor_amarilla"] == 0 and not _main.get("unsaved"), "«Nuevo» empieza sin progreso: mochila vacía")
	_main.call("_on_load_path", SAVE_PATH)
	await _frames(40)
	var loaded: Dictionary = entities.get_entity(sheep_cell)
	_check(not loaded.is_empty() and loaded["friendship"] == 8 and loaded["name"] == suggested and bag["flor_amarilla"] == 1,
			"al cargar el mapa guardado vuelven la amiga, su nombre y la mochila")
	_check(play.friends.backpack == bag, "el juego usa esa misma mochila")
	DirAccess.remove_absolute(SAVE_PATH)

	print("")
	if _failures == 0:
		print("AMISTAD (VENTANA) OK: %d comprobaciones." % _checks)
	else:
		print("AMISTAD (VENTANA) FALLIDA: %d de %d comprobaciones fallaron." % [_failures, _checks])
	quit(0 if _failures == 0 else 1)
