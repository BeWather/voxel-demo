extends SceneTree
## Prueba de interacción con eventos de entrada sintéticos (clics, arrastres y teclas).
## Carga la escena principal e inyecta eventos con Input.parse_input_event. Ejecutar con:
##   godot --path <proyecto> --script res://tests/interaction_test.gd
## Opcional: "-- --ishot=<png>" guarda una captura con el cursor y la vista previa de un prop.
## No reemplaza la prueba manual: no cubre los FileDialog ni la sensación del arrastre real.

const VIEW_POINT: Vector2 = Vector2(760.0, 400.0)
## Carpeta de objetos solo para la prueba: nunca se toca la `user://props/` real.
const TEST_PROPS_DIR: String = "user://_prueba_props"

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _world: VoxelWorld
var _props: PropLayer
var _controller: EditorController


## Dónde se ubica la ventana durante la prueba (fuera de cualquier monitor).
const OFFSCREEN_POSITION: Vector2i = Vector2i(-6000, -6000)


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


func _move(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	Input.parse_input_event(event)
	await _frames(3)


func _button(pos: Vector2, pressed: bool, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(3)


func _click(pos: Vector2) -> void:
	await _move(pos)
	await _button(pos, true)
	await _button(pos, false)


func _key(keycode: Key, ctrl: bool = false, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.ctrl_pressed = ctrl
		event.shift_pressed = shift
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


## Celdas cuyo bloque difiere entre dos mundos serializados no sirve aquí: se compara en vivo.
func _snapshot() -> Dictionary[Vector3i, int]:
	var snap: Dictionary[Vector3i, int] = {}
	for y: int in _world.size_y:
		for z: int in _world.size_z:
			for x: int in _world.size_x:
				var id: int = _world.get_block_xyz(x, y, z)
				if id != Blocks.AIR:
					snap[Vector3i(x, y, z)] = id
	return snap


func _diff(a: Dictionary[Vector3i, int], b: Dictionary[Vector3i, int]) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for cell: Vector3i in a:
		if b.get(cell, 0) != a[cell]:
			cells.append(cell)
	for cell: Vector3i in b:
		if not a.has(cell):
			cells.append(cell)
	return cells


func _run() -> void:
	var shot_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ishot="):
			shot_path = arg.trim_prefix("--ishot=")

	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_clean_test_props()
	_main.set("props_dir", TEST_PROPS_DIR)
	# Sin captura del mouse: la prueba no debe mover ni encerrar el cursor real del usuario.
	_main.set("capture_mouse_in_play", false)
	# Semilla fija: el punto de prueba cae sobre pasto, lejos del estanque.
	get_root().add_child(_main)
	# La ventana de prueba deja pasar el mouse real y no toma el foco: así los eventos
	# sintéticos no se mezclan con lo que haga el usuario mientras corre la prueba.
	get_root().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	get_root().set_flag(Window.FLAG_NO_FOCUS, true)
	# Además se la saca de la pantalla: el mouse real nunca pasa por encima.
	get_root().position = OFFSCREEN_POSITION
	await _frames(5)
	_world = _main.get("world")
	_props = _main.get("props")
	_controller = _main.get("controller")
	MeadowGenerator.generate(_world, _props, 2024, _main.get("entities"))
	_controller.clear_history()
	await _frames(3)

	print("[colocar bloque]")
	var base: Dictionary[Vector3i, int] = _snapshot()
	var props_before: int = _props.props.size()
	await _move(VIEW_POINT)
	await _click(VIEW_POINT)
	var snap: Dictionary[Vector3i, int] = _snapshot()
	var changed: Array[Vector3i] = _diff(base, snap)
	_check(changed.size() == 1, "un clic coloca un bloque (cambiaron %d)" % changed.size())
	_check(_controller.can_undo(), "el clic generó un paso de deshacer")

	# Mantener apretado sin mover el mouse no debe apilar una torre.
	await _key(KEY_Z, true)
	_check(_diff(base, _snapshot()).is_empty(), "Ctrl+Z deshace el bloque")
	await _move(VIEW_POINT)
	await _button(VIEW_POINT, true)
	await _frames(30)
	await _button(VIEW_POINT, false)
	changed = _diff(base, _snapshot())
	_check(changed.size() == 1, "mantener apretado 30 frames coloca un solo bloque (fueron %d)" % changed.size())
	await _key(KEY_Z, true)

	# Arrastre: todos los bloques nuevos quedan en la misma capa.
	await _move(VIEW_POINT)
	await _button(VIEW_POINT, true)
	for i: int in range(1, 13):
		await _move(VIEW_POINT + Vector2(i * 9.0, i * 3.0))
	await _button(VIEW_POINT + Vector2(108.0, 36.0), false)
	changed = _diff(base, _snapshot())
	# La capa es perpendicular a la cara del primer clic: puede ser un plano X, Y o Z.
	var layers: Dictionary[int, bool] = {}
	for axis: int in 3:
		var values: Dictionary[int, bool] = {}
		for cell: Vector3i in changed:
			values[cell[axis]] = true
		if layers.is_empty() or values.size() < layers.size():
			layers = values
	print("  el arrastre colocó %d bloques en las capas %s" % [changed.size(), str(layers.keys())])
	_check(changed.size() >= 2, "el arrastre coloca varios bloques")
	_check(layers.size() == 1, "todos en la misma capa (sin torre)")
	await _key(KEY_Z, true)
	_check(_diff(base, _snapshot()).is_empty(), "un solo Ctrl+Z deshace todo el arrastre")
	await _key(KEY_Y, true)
	_check(_diff(base, _snapshot()).size() == changed.size(), "Ctrl+Y lo rehace")
	await _key(KEY_Z, true, true)
	_check(_diff(base, _snapshot()).size() == changed.size(), "Ctrl+Shift+Z sin nada que rehacer no cambia nada")
	await _key(KEY_Z, true)

	print("[interfaz]")
	# Botón "2 Borrar bloque" del panel lateral.
	var panel_ui: EditorUI = _main.get("ui")
	var tool_buttons: Array[Button] = panel_ui.get("_tool_buttons")
	var brush_buttons: Array[Button] = panel_ui.get("_brush_buttons")
	var block_buttons: Dictionary[int, Button] = panel_ui.get("_block_buttons")
	await _click(tool_buttons[1].get_global_rect().get_center())
	_check(_controller.tool == EditorController.Tool.ERASE, "clic en el botón cambia la herramienta")
	_check(_diff(base, _snapshot()).is_empty(), "el clic sobre la interfaz no edita el mundo")
	await _click(Vector2(600.0, 20.0))
	_check(_diff(base, _snapshot()).is_empty(), "el clic sobre la barra superior no edita el mundo")
	await _click(brush_buttons[2].get_global_rect().get_center())
	_check(_controller.brush == 3, "botón de pincel 3 (quedó en %d)" % _controller.brush)
	await _click(block_buttons[Blocks.STONE].get_global_rect().get_center())
	_check(_controller.block_id == Blocks.STONE, "paleta: piedra seleccionada")

	print("[borrar bloque]")
	await _move(VIEW_POINT)
	await _button(VIEW_POINT, true)
	await _frames(30)
	await _button(VIEW_POINT, false)
	changed = _diff(base, _snapshot())
	_check(changed.size() >= 1 and changed.size() <= 9,
			"mantener apretado borra una sola capa con pincel 3 (%d bloques)" % changed.size())
	_check(_props.props.size() <= props_before, "los props sin soporte se quitan (%d -> %d)" % [
			props_before, _props.props.size()])
	await _key(KEY_Z, true)
	_check(_diff(base, _snapshot()).is_empty() and _props.props.size() == props_before,
			"deshacer restaura bloques y props")

	print("[pintar bloque]")
	await _key(KEY_3)
	_check(_controller.tool == EditorController.Tool.PAINT, "tecla 3 = pintar")
	var ui: EditorUI = _main.get("ui")
	var pressed_tools: int = 0
	for button: Button in ui.get("_tool_buttons"):
		if button.button_pressed:
			pressed_tools += 1
	_check(pressed_tools == 1, "la interfaz marca una sola herramienta activa (%d)" % pressed_tools)
	await _click(VIEW_POINT)
	changed = _diff(base, _snapshot())
	var all_stone: bool = not changed.is_empty()
	for cell: Vector3i in changed:
		if _world.get_block(cell) != Blocks.STONE:
			all_stone = false
	_check(all_stone, "pintar cambia el tipo a piedra (%d bloques)" % changed.size())
	await _key(KEY_Z, true)

	print("[props]")
	await _key(KEY_4)
	_check(_controller.tool == EditorController.Tool.PROP_PLACE, "tecla 4 = colocar prop")
	# Se busca un punto de la vista donde se pueda colocar un prop.
	var spot: Vector2 = VIEW_POINT
	var found: bool = false
	for i: int in 40:
		spot = VIEW_POINT + Vector2(i * 11.0, 0.0)
		await _move(spot)
		# Una celda que ya tiene un prop también es válida (se reemplaza), pero no sirve
		# para contar props: se busca una libre.
		if _controller.get("_prop_valid") and not _props.has_prop(_controller.hover_cell()):
			found = true
			break
	_check(found, "hay una celda válida para el prop")
	await _key(KEY_R)
	_check(_controller.prop_rot == 1, "R rota el prop")
	if not shot_path.is_empty():
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(shot_path)
		print("  captura guardada en %s" % shot_path)
	var count: int = _props.props.size()
	await _click(spot)
	_check(_props.props.size() == count + 1, "un clic coloca un prop")
	var placed: Dictionary = {}
	var placed_cell := Vector3i.ZERO
	for cell: Vector3i in _props.props:
		if _props.props[cell]["rot"] == 1 and _props.props[cell]["id"] == _controller.prop_id:
			placed = _props.props[cell]
			placed_cell = cell
	_check(not placed.is_empty(), "con el tipo y la rotación elegidos")
	await _key(KEY_5)
	# Se apunta al tronco del prop recién colocado, proyectado a la pantalla.
	var editor_camera: EditorCamera = _main.get("camera")
	await _click(editor_camera.unproject_position(Vector3(placed_cell) + Vector3(0.5, 0.4, 0.5)))
	_check(_props.props.size() == count, "borrar prop lo quita al hacer clic sobre él")
	await _key(KEY_Z, true)
	await _key(KEY_Z, true)
	_check(_props.props.size() == count, "dos Ctrl+Z vuelven al estado inicial")

	print("[cámara]")
	var camera: EditorCamera = _main.get("camera")
	var d0: float = camera.distance
	await _button(VIEW_POINT, true, MOUSE_BUTTON_WHEEL_UP)
	_check(camera.distance < d0, "la rueda acerca la cámara")
	var yaw0: float = camera.yaw
	await _button(VIEW_POINT, true, MOUSE_BUTTON_MIDDLE)
	var drag := InputEventMouseMotion.new()
	drag.position = VIEW_POINT + Vector2(40.0, 5000.0)
	drag.relative = Vector2(40.0, 5000.0)
	Input.parse_input_event(drag)
	await _frames(2)
	await _button(VIEW_POINT, false, MOUSE_BUTTON_MIDDLE)
	_check(not is_equal_approx(camera.yaw, yaw0), "arrastrar con el botón central orbita")
	_check(camera.pitch >= EditorCamera.MIN_PITCH and camera.pitch <= EditorCamera.MAX_PITCH
			and camera.global_position.y > camera.focus.y, "el cabeceo queda limitado sobre el horizonte")

	await _test_entities_and_play()
	await _test_move_and_ride()
	await _test_object_mode()
	await _test_window_and_sizes()

	print("")
	if _failures == 0:
		print("INTERACCION OK: %d comprobaciones." % _checks)
	else:
		print("INTERACCION FALLIDA: %d de %d comprobaciones fallaron." % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _hold(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(2)


## Criaturas en el editor y recorrido completo del modo juego: F5, selector, caminar, Esc.
func _test_entities_and_play() -> void:
	var entities: EntityLayer = _main.get("entities")
	var ui: EditorUI = _main.get("ui")
	var selector: AvatarSelector = _main.get("selector")
	var play: PlayMode = _main.get("play")
	var camera: EditorCamera = _main.get("camera")
	var saved_avatar: int = UserSettings.load_avatar()

	print("[criaturas]")
	var entity_buttons: Array[Button] = ui.get("_entity_buttons")
	await _click(entity_buttons[CharacterLibrary.PIG].get_global_rect().get_center())
	_check(_controller.tool == EditorController.Tool.ENTITY_PLACE and _controller.entity_type == CharacterLibrary.PIG,
			"elegir una criatura en la paleta activa \"colocar criatura\"")
	var spot: Vector2 = VIEW_POINT
	var found: bool = false
	for i: int in 40:
		spot = VIEW_POINT + Vector2(i * 11.0, 0.0)
		await _move(spot)
		if _controller.get("_prop_valid"):
			found = true
			break
	_check(found, "hay una celda válida para la criatura")
	var count: int = entities.entities.size()
	var target: Vector3i = _controller.hover_cell()
	await _click(spot)
	_check(entities.entities.size() == count + 1 and entities.has_entity(target), "un clic coloca la criatura")
	await _key(KEY_Z, true)
	_check(entities.entities.size() == count, "Ctrl+Z la quita")
	await _key(KEY_Y, true)
	_check(entities.has_entity(target), "Ctrl+Y la vuelve a poner")
	await _key(KEY_7)
	_check(_controller.tool == EditorController.Tool.ENTITY_ERASE, "tecla 7 = borrar criatura")
	# Se apunta al centro del cuerpo de la criatura, proyectado a la pantalla.
	await _click(camera.unproject_position(Vector3(target) + Vector3(0.5, 0.4, 0.5)))
	_check(entities.entities.size() == count, "borrar criatura la quita al hacer clic sobre ella")
	await _key(KEY_6)
	_check(_controller.tool == EditorController.Tool.ENTITY_PLACE, "tecla 6 = colocar criatura")
	var pressed_tools: int = 0
	for button: Button in ui.get("_tool_buttons"):
		if button.button_pressed:
			pressed_tools += 1
	_check(pressed_tools == 1, "una sola herramienta marcada en el panel")

	print("[modo juego]")
	var before: Dictionary = MapIO.serialize(_world, _props, 0, entities)
	var camera_before: Transform3D = camera.global_transform
	await _move(VIEW_POINT)
	await _key(KEY_F5)
	_check(_main.get("mode") == 1 and selector.visible, "F5 abre el selector de avatar")
	_check(selector.selected() == saved_avatar, "el selector arranca con el último avatar usado")
	await _click(VIEW_POINT + Vector2(300.0, 250.0))
	await _key(KEY_ESCAPE)
	_check(_main.get("mode") == 0 and not selector.visible, "Esc cancela y vuelve al editor")
	_check(MapIO.serialize(_world, _props, 0, entities) == before, "con el selector abierto no se edita el mapa")

	await _key(KEY_F5)
	await _key(KEY_RIGHT)
	var chosen: int = posmod(saved_avatar + 1, CharacterLibrary.AVATAR_COUNT)
	_check(selector.selected() == chosen, "las flechas cambian el avatar")
	await _key(KEY_ENTER)
	_check(_main.get("mode") == 2 and play.active and not selector.visible, "Enter empieza a jugar")
	_check(_main.get("avatar") == chosen and UserSettings.load_avatar() == chosen, "el avatar elegido se recuerda")
	_check(not ui.visible and play.play_camera.current and not camera.current,
			"se oculta el editor y se usa la cámara del juego")
	await _frames(45)
	_check(play.player.body.on_ground or play.player.body.in_water, "el jugador aparece apoyado en el terreno")
	var start: Vector3 = play.player.body.pos
	await _hold(KEY_W, true)
	await _frames(40)
	await _hold(KEY_W, false)
	var walked: float = Vector2(play.player.body.pos.x - start.x, play.player.body.pos.z - start.z).length()
	_check(walked > 0.5, "W mueve al jugador (%.2f bloques)" % walked)
	var yaw_before: float = play.cam_yaw
	# La cámara solo gira con el mouse capturado; aquí se simula esa condición.
	play.set("_capture_mouse", true)
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(120.0, 30.0)
	look.position = VIEW_POINT
	Input.parse_input_event(look)
	await _frames(3)
	play.set("_capture_mouse", false)
	_check(not is_equal_approx(play.cam_yaw, yaw_before), "mover el mouse gira la cámara")
	await _hold(KEY_SPACE, true)
	await _frames(8)
	await _hold(KEY_SPACE, false)
	await _key(KEY_2)
	await _click(VIEW_POINT)
	_check(_controller.tool == EditorController.Tool.ENTITY_PLACE, "las teclas del editor no actúan mientras se juega")
	await _frames(30)

	await _key(KEY_ESCAPE)
	_check(_main.get("mode") == 0 and not play.active, "Esc vuelve al editor")
	_check(ui.visible and camera.current and not play.play_camera.current, "vuelve la interfaz y la cámara del editor")
	_check(camera.global_transform.is_equal_approx(camera_before), "la cámara del editor quedó donde estaba")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "el mouse se libera")
	_check(MapIO.serialize(_world, _props, 0, entities) == before, "jugar no cambió bloques, props ni criaturas")
	var displaced: int = 0
	for actor: EntityActor in entities.actors():
		if not actor.position.is_equal_approx(actor.home):
			displaced += 1
	_check(displaced == 0, "todas las criaturas volvieron a su celda")
	UserSettings.save_avatar(saved_avatar)


# ================================================================ editor de objetos

func _clean_test_props() -> void:
	for path: String in PropIO.list_files(TEST_PROPS_DIR):
		DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(TEST_PROPS_DIR):
		DirAccess.remove_absolute(TEST_PROPS_DIR)


## Centro en pantalla del botón con ese texto, buscado dentro de `parent`.
func _button_center(parent: Node, text: String) -> Vector2:
	for node: Node in parent.find_children("*", "Button", true, false):
		var button: Button = node
		if button.text == text and button.is_visible_in_tree():
			return button.get_global_rect().get_center()
	_check(false, "existe el botón «%s»" % text)
	return Vector2.ZERO


## Pasada por el editor de objetos: entrar, colocar, pintar y borrar voxeles con el mouse,
## deshacer, guardar un objeto y volver al mapa, que tiene que quedar intacto.
func _test_object_mode() -> void:
	var entities: EntityLayer = _main.get("entities")
	var ui: EditorUI = _main.get("ui")
	var camera: EditorCamera = _main.get("camera")
	var library: PropLibrary = _main.get("library")
	var editor: ObjectEditor = _main.get("object_editor")
	var object_ui: ObjectUI = _main.get("object_ui")

	print("[editor de objetos]")
	_controller.set_prop(PropLibrary.ROCK)
	await _frames(2)
	var map_before: Dictionary = MapIO.serialize(_world, _props, 0, entities)
	var camera_before: Transform3D = camera.global_transform
	var could_undo: bool = _controller.can_undo()
	var map_tool: int = _controller.tool
	var modal_before: bool = _main.get("_modal_open")
	var mode_before: int = _main.get("mode")
	await _click(_button_center(ui, "Editor de objetos"))
	_check(_main.get("mode") == 3 and object_ui.visible and editor.visible and not ui.visible,
			"el botón «Editor de objetos» cambia de modo (antes: modo %d, diálogo abierto %s)" % [
			mode_before, str(modal_before)])
	_check(editor.camera.current and not camera.current and not _world.visible and not _props.visible,
			"se oculta el mapa y se usa la cámara del editor de objetos")
	_check(editor.object_key == "roca" and editor.variant_count() == 3 and not editor.modified,
			"abre el prop elegido en la paleta, con sus variantes")

	await _click(_button_center(object_ui, "Nuevo"))
	_check(editor.is_new() and editor.model().count() == 0, "«Nuevo» deja un modelo vacío")
	var object_camera: EditorCamera = editor.camera
	var floor_point: Vector2 = object_camera.unproject_position(Vector3(0.5, 0.0, 0.5))
	await _move(floor_point)
	_check(editor.get("_target_valid") and editor.get("_target") == Vector3i.ZERO, "el cursor marca la celda del piso apuntada")
	await _click(floor_point)
	_check(editor.model().count() == 1 and editor.model().has_voxel(Vector3i.ZERO), "un clic sobre la cuadrícula coloca un voxel")
	_check(editor.modified and editor.can_undo(), "queda como cambio sin guardar y con un paso de deshacer")

	# Mantener apretado no apila una torre hacia la cámara.
	await _move(floor_point)
	await _button(floor_point, true)
	await _frames(25)
	await _button(floor_point, false)
	_check(editor.model().count() == 2, "mantener apretado coloca un solo voxel más (hay %d)" % editor.model().count())
	await _key(KEY_Z, true)
	_check(editor.model().count() == 1, "Ctrl+Z lo deshace")
	await _key(KEY_Y, true)
	_check(editor.model().count() == 2, "Ctrl+Y lo rehace")
	await _key(KEY_Z, true, true)
	await _key(KEY_Z, true)
	_check(editor.model().count() == 1, "Ctrl+Shift+Z sin nada que rehacer no cambia nada")

	# Arrastre sobre el piso: una fila en la misma capa y un solo paso de deshacer.
	var drag_start: Vector2 = object_camera.unproject_position(Vector3(4.5, 0.0, 0.5))
	await _move(drag_start)
	await _button(drag_start, true)
	for x: int in range(5, 11):
		await _move(object_camera.unproject_position(Vector3(x + 0.5, 0.0, 0.5)))
	await _button(object_camera.unproject_position(Vector3(10.5, 0.0, 0.5)), false)
	var row: int = 0
	var flat: bool = true
	for key: int in editor.model().voxels:
		var cell: Vector3i = PropLibrary.voxel_cell(key)
		if cell != Vector3i.ZERO:
			row += 1
			if cell.y != 0:
				flat = false
	_check(row >= 5 and flat, "el arrastre coloca una fila en la misma capa (%d voxeles)" % row)
	await _key(KEY_Z, true)
	_check(editor.model().count() == 1, "un solo Ctrl+Z deshace todo el arrastre")

	# Pintar, tomar color y borrar apuntando al voxel del origen.
	var voxel_point: Vector2 = object_camera.unproject_position(Vector3(0.5, 1.0, 0.5))
	var first_color: Color = editor.model().get_voxel(Vector3i.ZERO)
	var paint := Color.html("3366cc")
	editor.set_color(paint)
	await _key(KEY_3)
	_check(editor.tool == ObjectEditor.Tool.PAINT and _controller.tool == map_tool,
			"tecla 3 = pintar voxel, sin cambiar la herramienta del mapa")
	var pressed_tools: int = 0
	for button: Button in object_ui.get("_tool_buttons"):
		if button.button_pressed:
			pressed_tools += 1
	_check(pressed_tools == 1, "el panel marca una sola herramienta activa")
	await _click(voxel_point)
	_check(editor.model().get_voxel(Vector3i.ZERO) == paint, "pintar cambia el color del voxel")
	await _key(KEY_Z, true)
	_check(editor.model().get_voxel(Vector3i.ZERO) == first_color, "y se deshace")
	await _key(KEY_4)
	await _click(voxel_point)
	_check(editor.color == first_color and editor.tool == ObjectEditor.Tool.PAINT,
			"tomar color lo copia del voxel y vuelve a la herramienta anterior")
	var swatches: HFlowContainer = object_ui.get("_swatch_flow")
	_check(swatches.get_child_count() == 1, "la lista de colores del modelo tiene el único color usado")
	await _key(KEY_2)
	await _click(voxel_point)
	_check(editor.model().count() == 0, "tecla 2 y un clic borran el voxel")
	await _key(KEY_Z, true)
	_check(editor.model().count() == 1, "deshacer lo devuelve")
	await _click(Vector2(800.0, 20.0))
	await _click(Vector2(120.0, 600.0))
	_check(editor.model().count() == 1, "los clics sobre la interfaz no editan el modelo")
	await _key(KEY_F5)
	_check(_main.get("mode") == 3, "F5 no entra al modo juego desde el editor de objetos")
	_check(MapIO.serialize(_world, _props, 0, entities) == map_before and _controller.can_undo() == could_undo
			and _controller.tool == map_tool, "nada de esto tocó el mapa ni su historial")

	# Guardar como objeto nuevo: aparece en la biblioteca y en la paleta del mapa.
	var prop_buttons: Array[Button] = ui.get("_prop_buttons")
	var buttons_before: int = prop_buttons.size()
	_check(editor.save_as("Objeto de prueba", "objeto_de_prueba").is_empty(), "guardar como objeto nuevo")
	await _frames(2)
	prop_buttons = ui.get("_prop_buttons")
	_check(library.key_to_id("objeto_de_prueba") == buttons_before and prop_buttons.size() == buttons_before + 1
			and prop_buttons[buttons_before].text == "Objeto de prueba", "el objeto nuevo aparece en la paleta de props")
	_check(FileAccess.file_exists(PropIO.path_for(TEST_PROPS_DIR, "objeto_de_prueba")), "y queda guardado en la carpeta de objetos")

	# Guardar sobre un incorporado: los props ya colocados en el mapa cambian de malla.
	var oak_variant: int = -1
	for cell: Vector3i in _props.props:
		if _props.props[cell]["id"] == PropLibrary.OAK:
			oak_variant = _props.props[cell]["variant"]
			break
	_check(oak_variant >= 0, "hay un roble colocado en el mapa")
	var instances: Dictionary = _props.get("_instances")
	var oak_node: MultiMeshInstance3D = instances[PropLibrary.OAK * PropLibrary.MAX_VARIANTS + oak_variant]
	var old_mesh: Mesh = oak_node.multimesh.mesh
	editor.open_object(PropLibrary.OAK, oak_variant)
	editor.model().set_voxel(Vector3i(0, PropLibrary.MAX_Y, 0), paint)
	_check(editor.save().is_empty() and library.is_overridden(PropLibrary.OAK), "guardar sobre el roble incorporado")
	await _frames(3)
	_check(oak_node.multimesh.mesh != old_mesh and oak_node.multimesh.mesh == library.get_mesh(PropLibrary.OAK, oak_variant),
			"los robles ya colocados usan la malla nueva")
	_check(object_ui.get("_restore_button").visible, "aparece «Restaurar original»")
	_check(editor.restore_original().is_empty() and not library.is_overridden(PropLibrary.OAK), "restaurar original")
	await _frames(3)
	_check(not FileAccess.file_exists(PropIO.path_for(TEST_PROPS_DIR, "roble")), "se borra el archivo del reemplazo")

	# Volver: el mapa, su historial y su cámara quedan como estaban.
	await _click(_button_center(object_ui, "Volver al mapa"))
	_check(_main.get("mode") == 0 and ui.visible and not object_ui.visible and not editor.visible,
			"«Volver al mapa» vuelve al editor de mapas")
	_check(camera.current and camera.global_transform.is_equal_approx(camera_before) and _world.visible and _props.visible,
			"con el mapa visible y la cámara donde estaba")
	_check(MapIO.serialize(_world, _props, 0, entities) == map_before and _controller.can_undo() == could_undo,
			"el mapa y su historial están intactos")
	var voxels_before: int = editor.model().count()
	await _key(KEY_1)
	await _click(VIEW_POINT)
	_check(MapIO.serialize(_world, _props, 0, entities) != map_before and editor.model().count() == voxels_before,
			"de vuelta en el mapa, un clic edita el mapa y no el objeto")
	await _key(KEY_Z, true)
	_check(MapIO.serialize(_world, _props, 0, entities) == map_before, "y Ctrl+Z lo deshace en el mapa")
	_clean_test_props()


## Posición en píxeles de ventana de un punto dado en coordenadas de la interfaz
## (difieren cuando la interfaz está escalada).
func _to_window(pos: Vector2) -> Vector2:
	return pos * get_root().content_scale_factor


func _panel_of(control: Control) -> Control:
	var node: Node = control
	while node != null and not (node is PanelContainer):
		node = node.get_parent()
	return node as Control


## Comprueba que la vista 3D y los paneles ocupan la ventana tal como está ahora.
func _check_layout(label: String) -> void:
	var root: Window = get_root()
	var ui: EditorUI = _main.get("ui")
	var camera: EditorCamera = _main.get("camera")
	var view: Vector2 = root.get_visible_rect().size
	var window_size := Vector2(root.size)
	_check((view * root.content_scale_factor).is_equal_approx(window_size),
			"%s: la vista ocupa toda la ventana (%s a escala %.2f)" % [label, str(view), root.content_scale_factor])
	var aspect: float = camera.get_camera_projection().get_aspect()
	_check(absf(aspect - window_size.x / window_size.y) < 0.01,
			"%s: la proyección 3D usa la proporción de la ventana (%.3f)" % [label, aspect])
	_check(ui.get_global_rect().size.is_equal_approx(view), "%s: la interfaz ocupa toda la vista" % label)
	var top: Rect2 = _panel_of(ui.get("_seed_label")).get_global_rect()
	var status: Rect2 = _panel_of(ui.get("_status_label")).get_global_rect()
	var tool_buttons: Array[Button] = ui.get("_tool_buttons")
	var side: Rect2 = _panel_of(tool_buttons[0]).get_global_rect()
	_check(top.position.is_zero_approx() and is_equal_approx(top.size.x, view.x), "%s: la barra superior va de lado a lado" % label)
	_check(is_equal_approx(status.end.y, view.y) and is_equal_approx(status.size.x, view.x),
			"%s: la línea de estado queda abajo" % label)
	_check(is_zero_approx(side.position.x) and is_equal_approx(side.position.y, top.end.y)
			and is_equal_approx(side.end.y, status.position.y), "%s: el panel lateral ocupa todo el alto" % label)


## Mueve el mouse sobre un punto conocido del mapa y comprueba que el cursor marca esa celda.
func _check_picking(label: String) -> void:
	var camera: EditorCamera = _main.get("camera")
	await _key(KEY_1)
	@warning_ignore("integer_division")
	var column := Vector2i(_world.size_x / 2 + 3, _world.size_z / 2 + 2)
	var aim := Vector3(column.x + 0.5, _world.column_height(column.x, column.y), column.y + 0.5)
	var origin: Vector3 = camera.get_camera_transform().origin
	var hit: Dictionary = _world.raycast(origin, aim - origin)
	var expected: Vector3i = hit["cell"]
	var normal: Vector3i = hit["normal"]
	expected += normal
	var screen: Vector2 = camera.unproject_position(aim)
	await _move(_to_window(screen))
	_check(hit["hit"] and _controller.has_hover() and _controller.hover_cell() == expected,
			"%s: el cursor marca la celda apuntada %s (marca %s)" % [label, str(expected), str(_controller.hover_cell())])
	# Un clic en un botón del panel sigue acertando.
	var ui: EditorUI = _main.get("ui")
	var brush_buttons: Array[Button] = ui.get("_brush_buttons")
	await _click(_to_window(brush_buttons[3].get_global_rect().get_center()))
	_check(_controller.brush == 4, "%s: el clic en el panel acierta al botón (pincel %d)" % [label, _controller.brush])
	await _click(_to_window(brush_buttons[0].get_global_rect().get_center()))


## Ventana redimensionable, escala de la interfaz, F11 y mapas de otros tamaños.
func _test_window_and_sizes() -> void:
	var root: Window = get_root()
	var camera: EditorCamera = _main.get("camera")
	var overlay: BusyOverlay = _main.get("overlay")
	var new_dialog: NewMapDialog = _main.get("new_dialog")
	var ui: EditorUI = _main.get("ui")
	var start_size: Vector2i = root.size
	var saved_size: String = UserSettings.load_map_size()

	print("[ventana]")
	_check_layout("%d x %d" % [start_size.x, start_size.y])
	await _check_picking("%d x %d" % [start_size.x, start_size.y])
	for size: Vector2i in [Vector2i(1600, 900), Vector2i(1000, 640), start_size]:
		root.size = size
		await _frames(10)
		var label: String = "%d x %d" % [size.x, size.y]
		_check(root.size == size, "%s: la ventana cambió de tamaño" % label)
		_check_layout(label)
		await _check_picking(label)

	# Interfaz escalada (como en un monitor de 1440p o 4K): todo sigue alineado.
	root.content_scale_factor = 1.5
	await _frames(10)
	_check_layout("escala 1,5")
	await _check_picking("escala 1,5")
	root.content_scale_factor = 1.0
	await _frames(5)

	await _key(KEY_F11)
	await _frames(20)
	_check(root.mode == Window.MODE_FULLSCREEN, "F11 pasa a pantalla completa")
	# En pantalla completa la ventana queda bajo el mouse real del usuario, así que aquí
	# solo se comprueba la disposición (el apuntado ya se probó en los otros tamaños).
	_check_layout("pantalla completa")
	await _key(KEY_F11)
	await _frames(20)
	_check(root.mode != Window.MODE_FULLSCREEN, "F11 otra vez vuelve a la ventana")
	root.size = start_size
	root.position = OFFSCREEN_POSITION
	await _frames(10)
	_check_layout("de vuelta en %d x %d" % [start_size.x, start_size.y])

	print("[mapa nuevo]")
	await _click(_button_center(ui, "Nuevo"))
	await _frames(5)
	_check(new_dialog.visible, "el botón Nuevo abre el diálogo de tamaño y semilla")
	_check(new_dialog.selected_size() == saved_size, "arranca con el último tamaño usado (%s)" % saved_size)
	_check(not _controller.input_enabled, "con el diálogo abierto no se edita")
	new_dialog.select_size("M")
	new_dialog.set_seed_text("4321")
	new_dialog.get_ok_button().pressed.emit()
	await _frames(2)
	_check(not new_dialog.visible and _main.call("is_busy") and overlay.visible, "Crear cierra el diálogo y muestra el avance")
	_check(overlay.current_text().begins_with("Generando"), "el cartel dice «%s»" % overlay.current_text())
	_check(not _controller.input_enabled, "mientras se genera no se edita")
	var waited: int = 0
	var slow_frames: int = 0
	var last: int = Time.get_ticks_msec()
	while _main.call("is_busy") and waited < 3000:
		await process_frame
		waited += 1
		var now: int = Time.get_ticks_msec()
		if now - last > 120:
			slow_frames += 1
		last = now
	print("  el mapa M quedó listo en %d cuadros (%d ms), %d cuadros de más de 120 ms" % [
			waited, _main.get("last_load_msec"), slow_frames])
	_check(not _main.call("is_busy") and not overlay.visible, "la generación termina y el cartel desaparece")
	_check(waited > 10 and slow_frames == 0, "la ventana no se congela mientras se genera")
	_check(_world.size_x == 128 and _world.size_z == 128 and _main.get("current_seed") == 4321,
			"el mapa nuevo es M (128 x 128) con la semilla pedida")
	_check(_world.pending_count() == 0 and _world.chunks.size() == 64, "todas las mallas quedaron armadas")
	_check(is_equal_approx(camera.bounds_max.x, 128.0) and is_equal_approx(camera.focus.x, 64.0),
			"la cámara del editor encuadra el mapa nuevo")
	_check(_controller.input_enabled and not _controller.can_undo(), "se puede editar otra vez y el historial está vacío")
	_check(UserSettings.load_map_size() == "M", "el tamaño elegido queda guardado")
	await _frames(5)
	await _check_picking("mapa M")
	var before: int = _world.get_block(Vector3i(100, 20, 100))
	_controller.apply_block(Vector3i(100, 20, 100), Blocks.STONE)
	_check(before == Blocks.AIR and _world.dirty_count() == 1, "una edición en el mapa M ensucia un solo chunk")
	await _key(KEY_Z, true)
	UserSettings.save_map_size(saved_size)


## Celdas libres cerca del centro del mapa que se ven desde la cámara sin nada delante:
## apuntar al centro de su piso da justo esa celda.
func _visible_free_cells(count: int) -> Array[Vector3i]:
	var camera: EditorCamera = _main.get("camera")
	var origin: Vector3 = camera.get_camera_transform().origin
	var found: Array[Vector3i] = []
	@warning_ignore("integer_division")
	var centre := Vector2i(_world.size_x / 2, _world.size_z / 2)
	for radius: int in range(2, 14):
		for dz: int in range(-radius, radius + 1, 2):
			for dx: int in range(-radius, radius + 1, 2):
				if maxi(absi(dx), absi(dz)) != radius or found.size() >= count:
					continue
				var cell := Vector3i(centre.x + dx, _world.column_height(centre.x + dx, centre.y + dz), centre.y + dz)
				if not _controller.is_free_cell(cell):
					continue
				var hit: Dictionary = _world.raycast(origin, Vector3(cell) + Vector3(0.5, 0.0, 0.5) - origin)
				if not hit["hit"] or hit["cell"] + hit["normal"] != cell:
					continue
				var apart: bool = true
				for other: Vector3i in found:
					if Vector3(other - cell).length() < 3.0:
						apart = false
				if apart:
					found.append(cell)
	return found


## Punto de la pantalla que apunta al piso de una celda.
func _floor_point(cell: Vector3i) -> Vector2:
	var camera: EditorCamera = _main.get("camera")
	return _to_window(camera.unproject_position(Vector3(cell) + Vector3(0.5, 0.0, 0.5)))


## Herramienta mover (arrastre y clic-clic) y montar un poni con la tecla E.
func _test_move_and_ride() -> void:
	var entities: EntityLayer = _main.get("entities")
	var ui: EditorUI = _main.get("ui")
	var play: PlayMode = _main.get("play")
	var camera: EditorCamera = _main.get("camera")
	camera.frame_world(Vector3(_world.size_x, _world.size_y, _world.size_z), camera.focus.y)
	await _frames(3)

	print("[mover]")
	var tool_buttons: Array[Button] = ui.get("_tool_buttons")
	_check(tool_buttons.size() == 8 and tool_buttons[2].tooltip_text.contains("convertir pasto en camino"),
			"cada herramienta tiene una ayuda con ejemplo (Pintar: «%s»)" % tool_buttons[2].tooltip_text.get_slice("\n", 1))
	await _key(KEY_8)
	_check(_controller.tool == EditorController.Tool.MOVE, "tecla 8 = mover")
	_check(ui.hint_text().begins_with("Mover:"), "la línea de estado explica la herramienta: «%s»" % ui.hint_text().left(60))
	var cells: Array[Vector3i] = _visible_free_cells(3)
	_check(cells.size() == 3, "hay tres celdas libres a la vista")
	if cells.size() < 3:
		return
	var a: Vector3i = cells[0]
	var b: Vector3i = cells[1]
	var c: Vector3i = cells[2]
	var rock: Dictionary = PropLayer.make_prop(PropLibrary.ROCK, 1, 2)
	_controller.apply_prop(a, rock)
	_controller.clear_history()
	var before: Dictionary = MapIO.serialize(_world, _props, 0, entities)
	await _frames(3)

	# Arrastre: apretar sobre la roca, llevarla a otra celda, girarla con R y soltar.
	var grab: Vector2 = _to_window(camera.unproject_position(Vector3(a) + Vector3(0.5, 0.25, 0.5)))
	await _move(grab)
	_check(_controller.has_hover() and _controller.hover_cell() == a, "el cursor marca la roca")
	await _button(grab, true)
	_check(_controller.is_moving(), "al apretar sobre un prop se lo levanta")
	await _move(_floor_point(b))
	_check(_controller.hover_cell() == b and _controller.get("_prop_valid"), "mientras se arrastra, el cursor marca dónde caería")
	await _key(KEY_R)
	await _button(_floor_point(b), false)
	_check(not _controller.is_moving() and not _props.has_prop(a)
			and _props.get_prop(b) == PropLayer.make_prop(PropLibrary.ROCK, 1, 3), "al soltar queda en la celda nueva, girado con R")
	await _key(KEY_Z, true)
	_check(MapIO.serialize(_world, _props, 0, entities) == before and not _controller.can_undo(), "un solo Ctrl+Z lo devuelve")

	# Arrastre a un lugar inválido (sobre otro prop): vuelve a su lugar.
	_controller.apply_prop(c, PropLayer.make_prop(PropLibrary.BUSH, 0, 0))
	_controller.clear_history()
	before = MapIO.serialize(_world, _props, 0, entities)
	await _move(grab)
	await _button(grab, true)
	await _move(_floor_point(c))
	_check(not _controller.get("_prop_valid"), "sobre otro prop el cursor avisa que no se puede")
	await _button(_floor_point(c), false)
	_check(not _controller.is_moving() and MapIO.serialize(_world, _props, 0, entities) == before and not _controller.can_undo(),
			"soltar en un lugar inválido lo deja donde estaba")

	# Clic para levantar y clic para soltar, con un aldeano.
	var npc: Dictionary = EntityLayer.make_entity(CharacterLibrary.VILLAGER, 1, 0, "Fermín", ["Buen día.", "Hasta luego."])
	_controller.apply_entity(b, npc)
	_controller.clear_history()
	await _frames(3)
	var npc_point: Vector2 = _to_window(camera.unproject_position(Vector3(b) + Vector3(0.5, 0.8, 0.5)))
	await _click(npc_point)
	_check(_controller.is_moving() and _controller.get("_move_kind") == EditorController.MOVE_ENTITY,
			"un clic sobre el aldeano lo levanta")
	_props.set_prop(c, {})
	await _frames(3)
	await _click(_floor_point(c))
	var moved: Dictionary = entities.get_entity(c)
	_check(not _controller.is_moving() and not entities.has_entity(b) and moved == npc,
			"otro clic lo suelta en la celda nueva, con su nombre y su diálogo")
	await _key(KEY_Z, true)
	_check(entities.get_entity(b) == npc and not entities.has_entity(c), "Ctrl+Z lo devuelve")

	print("[montar]")
	entities.set_entity(b, {})
	_props.set_prop(a, {})
	_controller.apply_entity(a, EntityLayer.make_entity(CharacterLibrary.PONY, 2, 0))
	_controller.clear_history()
	before = MapIO.serialize(_world, _props, 0, entities)
	await _key(KEY_1)
	await _move(_floor_point(b))
	await _key(KEY_F5)
	await _key(KEY_ENTER)
	await _frames(40)
	_check(_main.get("mode") == 2 and play.active, "entra al modo juego")
	var pony: EntityActor = entities.get_actor(a)
	pony.body.teleport(pony.home)
	play.player.body.teleport(Vector3(b) + Vector3(0.5, 0.0, 0.5))
	pony.body.teleport(Vector3(b) + Vector3(0.5, 0.0, 0.5) + Vector3(1.4, 0.0, 0.0))
	await _frames(6)
	_check(play.prompt_text().begins_with("E: montar"), "cerca del poni aparece «%s»" % play.prompt_text())
	await _key(KEY_E)
	_check(play.is_mounted() and pony.ridden, "la tecla E lo monta")
	var hint: Label = play.get("_hint_label")
	_check(hint.text.contains("galopar"), "el HUD muestra los controles de montar")
	var start: Vector3 = pony.body.pos
	await _hold(KEY_W, true)
	await _frames(45)
	await _hold(KEY_W, false)
	var ridden: float = Vector2(pony.body.pos.x - start.x, pony.body.pos.z - start.z).length()
	_check(ridden > 1.0, "W dirige al poni (%.2f bloques)" % ridden)
	_check(play.player.rig.seated and play.player.position.distance_to(pony.body.pos) < 2.2, "el jugador va sentado encima")
	await _frames(20)
	await _key(KEY_E)
	_check(not play.is_mounted() and not pony.ridden and not play.player.rig.seated, "E otra vez lo baja")
	await _frames(20)
	_check(play.player.body.on_ground or play.player.body.in_water, "queda de pie en el suelo")
	_check(hint.text.contains("correr"), "el HUD vuelve a los controles de a pie")
	await _key(KEY_ESCAPE)
	_check(_main.get("mode") == 0 and pony.position.is_equal_approx(pony.home) and pony.cell == a, "al salir, el poni vuelve a su celda")
	_check(MapIO.serialize(_world, _props, 0, entities) == before, "montar no cambia el mapa")
	entities.set_entity(a, {})
	_props.set_prop(c, {})
	_controller.clear_history()
