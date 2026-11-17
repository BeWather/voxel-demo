extends Node3D
## Punto de entrada: arma el árbol de nodos por código y conecta las piezas del editor
## y del modo juego.
##
## Argumentos de usuario (después de "--"):
##   --shot=<ruta png absoluta>   guarda una captura y cierra.
##   --shot-mode=<modo>           qué capturar: editor (por defecto), selector, play, dialogo,
##                                montando (una niña sobre un poni) o volando (sobre el dragón).
##   --shot-size=<ancho>x<alto>   tamaño de la ventana para la captura.
##   --seed=<entero>              semilla de la pradera inicial.
##   --size=<S|M|L>               tamaño del mapa inicial (S por defecto).
##   --ui-scale=<número>          fuerza la escala de la interfaz (por defecto, automática).
##   --objects                    arranca en el editor de objetos.
##   --object=<clave>             arranca en el editor de objetos con ese objeto abierto.

enum Mode { EDIT, SELECT, PLAY, OBJECTS }

const SHOT_FRAMES: int = 30
const SHOT_SETTLE_FRAMES: int = 50
## Milisegundos por frame dedicados a generar un mapa grande.
const GENERATION_BUDGET_MSEC: int = 8
## Parte de la barra de progreso que corresponde a generar (el resto es armar mallas).
const GENERATION_SHARE: float = 0.45

var world: VoxelWorld
var props: PropLayer
var entities: EntityLayer
var library: PropLibrary
var characters: CharacterLibrary
var camera: EditorCamera
var controller: EditorController
var ui: EditorUI
var selector: AvatarSelector
var play: PlayMode
var object_editor: ObjectEditor
var object_ui: ObjectUI
## Carpeta de los objetos guardados. Las pruebas la cambian antes de agregar el nodo al árbol.
var props_dir: String = PropIO.PROPS_DIR
var current_seed: int = 0
var mode: int = Mode.EDIT
var avatar: int = 0
## Tamaño (S, M o L) del último mapa generado.
var map_size_key: String = AppConfig.DEFAULT_SIZE
var overlay: BusyOverlay
var new_dialog: NewMapDialog
## Milisegundos que tardó el último mapa en quedar listo (generación o carga + mallas).
var last_load_msec: int = 0
## Capturar el mouse al jugar. Las pruebas automáticas lo apagan para no mover el cursor real.
var capture_mouse_in_play: bool = true

var _modal_open: bool = false
var _new_dialog_open: bool = false
## Hay un mapa generándose o cargándose: la edición espera.
var _busy: bool = false
var _busy_text: String = ""
var _busy_start: int = 0
var _generator: MeadowGenerator
var _sun: DirectionalLight3D
var _ui_scale_override: float = 0.0
var _windowed_mode: Window.Mode = Window.MODE_WINDOWED
var _spawn_hint: Vector2i = Vector2i(-1, -1)
var _shot_path: String = ""
var _shot_mode: String = "editor"
var _frames: int = 0
var _shot_stage: int = 0


func _ready() -> void:
	var start_seed: int = -1
	var start_objects: bool = false
	var start_object_key: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--shot-mode="):
			_shot_mode = arg.trim_prefix("--shot-mode=")
		elif arg.begins_with("--seed=") and arg.trim_prefix("--seed=").is_valid_int():
			start_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--size=") and AppConfig.is_size_key(arg.trim_prefix("--size=")):
			map_size_key = arg.trim_prefix("--size=").to_upper()
		elif arg.begins_with("--shot-size="):
			_apply_shot_size(arg.trim_prefix("--shot-size="))
		elif arg.begins_with("--ui-scale=") and arg.trim_prefix("--ui-scale=").is_valid_float():
			_ui_scale_override = arg.trim_prefix("--ui-scale=").to_float()
		elif arg == "--objects":
			start_objects = true
		elif arg.begins_with("--object="):
			start_objects = true
			start_object_key = arg.trim_prefix("--object=")

	_build_environment()

	library = PropLibrary.new(props_dir)
	characters = CharacterLibrary.new()
	world = VoxelWorld.new()
	world.name = "Mundo"
	add_child(world)
	props = PropLayer.new()
	props.name = "Props"
	props.library = library
	add_child(props)
	entities = EntityLayer.new()
	entities.name = "Criaturas"
	entities.library = characters
	add_child(entities)

	camera = EditorCamera.new()
	camera.name = "Camara"
	add_child(camera)
	camera.current = true

	controller = EditorController.new()
	controller.name = "Controlador"
	controller.setup(world, props, camera, entities)
	add_child(controller)

	play = PlayMode.new()
	play.name = "Juego"
	play.setup(world, props, entities, characters)
	add_child(play)

	object_editor = ObjectEditor.new()
	object_editor.name = "EditorDeObjetos"
	object_editor.setup(library)
	add_child(object_editor)
	object_editor.set_active(false)

	var layer := CanvasLayer.new()
	layer.name = "Interfaz"
	add_child(layer)
	ui = EditorUI.new()
	ui.library = library
	layer.add_child(ui)
	object_ui = ObjectUI.new()
	object_ui.setup(object_editor, library)
	object_ui.visible = false
	layer.add_child(object_ui)
	selector = AvatarSelector.new()
	selector.setup(characters)
	layer.add_child(selector)
	overlay = BusyOverlay.new()
	layer.add_child(overlay)
	# El diálogo cuelga de la interfaz para heredar su tema.
	new_dialog = NewMapDialog.new()
	ui.add_child(new_dialog)
	new_dialog.create_requested.connect(_on_new_map_chosen)
	new_dialog.visibility_changed.connect(_on_new_dialog_visibility)
	get_window().size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()

	ui.tool_selected.connect(controller.set_tool)
	ui.block_selected.connect(_on_block_selected)
	ui.prop_selected.connect(_on_prop_selected)
	ui.entity_selected.connect(_on_entity_selected)
	ui.brush_changed.connect(controller.set_brush)
	ui.new_requested.connect(_on_new_requested)
	ui.undo_requested.connect(controller.undo)
	ui.redo_requested.connect(controller.redo)
	ui.save_path_chosen.connect(_on_save_path)
	ui.load_path_chosen.connect(_on_load_path)
	ui.modal_changed.connect(_on_modal_changed)
	ui.play_requested.connect(request_play)
	ui.npc_edited.connect(_on_npc_edited)
	controller.tool_changed.connect(ui.set_tool)
	controller.tool_changed.connect(_on_tool_changed)
	controller.history_changed.connect(ui.set_history)
	controller.status_changed.connect(ui.set_status)
	controller.npc_edit_requested.connect(_on_npc_edit_requested)
	selector.chosen.connect(_on_avatar_chosen)
	selector.cancelled.connect(_on_selector_cancelled)
	play.exit_requested.connect(stop_play)
	ui.object_editor_requested.connect(open_object_editor)
	object_ui.back_requested.connect(close_object_editor)
	object_ui.modal_changed.connect(_on_modal_changed)
	library.prop_changed.connect(_on_prop_changed)

	MapIO.ensure_maps_dir()
	avatar = UserSettings.load_avatar()
	_new_map(start_seed if start_seed >= 0 else _random_seed())
	for warning: String in library.load_warnings:
		ui.show_message(warning, true)
	if start_objects:
		open_object_editor(start_object_key)


func _process(_delta: float) -> void:
	if _busy:
		_advance_loading()
	_update_shadow_distance()
	_update_view_offset()
	if not _shot_path.is_empty() and not _busy:
		_run_shot_script()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if key.pressed and not key.echo and key.keycode == KEY_F5 and mode == Mode.EDIT:
		get_viewport().set_input_as_handled()
		request_play()
	elif key.pressed and not key.echo and key.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		toggle_fullscreen()


# ================================================================ ventana

## F11: alterna entre pantalla completa y el modo de ventana anterior.
func toggle_fullscreen() -> void:
	var window: Window = get_window()
	if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		window.mode = _windowed_mode
	else:
		_windowed_mode = window.mode
		window.mode = Window.MODE_FULLSCREEN


## La interfaz se agranda en ventanas altas (1440p, 4K) para no quedar minúscula. El texto
## se vuelve a dibujar a la nueva escala, no se estira. La vista 3D siempre usa toda la ventana.
func _apply_ui_scale() -> void:
	var window: Window = get_window()
	var scale_factor: float = _ui_scale_override
	if scale_factor <= 0.0:
		scale_factor = AppConfig.ui_scale_for_height(window.size.y)
	if not is_equal_approx(window.content_scale_factor, scale_factor):
		window.content_scale_factor = scale_factor


## --shot-size=1920x1080: tamaño de ventana para la captura. Si no entra en la pantalla
## con bordes, la ventana se pone sin bordes.
func _apply_shot_size(text: String) -> void:
	var parts: PackedStringArray = text.to_lower().split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return
	var wanted := Vector2i(clampi(parts[0].to_int(), 320, 7680), clampi(parts[1].to_int(), 240, 4320))
	var window: Window = get_window()
	var screen: Vector2i = DisplayServer.screen_get_size()
	if wanted.x >= screen.x or wanted.y >= screen.y - 80:
		window.borderless = true
		window.position = DisplayServer.screen_get_position()
	window.size = wanted


## Las sombras llegan hasta donde alcanza la vista: lejos al ver un mapa grande entero,
## cerca (y más nítidas) al acercarse o al jugar.
func _update_shadow_distance() -> void:
	var wanted: float = 150.0
	if mode == Mode.EDIT:
		wanted = clampf(camera.distance * 2.4, 150.0, 1200.0)
	if absf(_sun.directional_shadow_max_distance - wanted) > 1.0:
		_sun.directional_shadow_max_distance = wanted


## El panel lateral tapa parte de la vista: la cámara del editor se corre hacia un costado
## para que su punto de foco quede en el centro de la zona libre, a cualquier tamaño de ventana.
func _update_view_offset() -> void:
	var visible_size: Vector2 = get_viewport().get_visible_rect().size
	if visible_size.x <= 0.0 or visible_size.y <= 0.0:
		return
	var panel_share: float = clampf(float(EditorUI.SIDE_WIDTH) / visible_size.x, 0.0, 0.5)
	var view_width: float = 2.0 * camera.distance * tan(deg_to_rad(camera.fov) * 0.5) * visible_size.x / visible_size.y
	var wanted: float = -0.5 * panel_share * view_width
	if absf(camera.h_offset - wanted) > 0.001:
		camera.h_offset = wanted


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.24, 0.47, 0.84)
	sky_material.sky_horizon_color = Color(0.70, 0.82, 0.93)
	sky_material.ground_horizon_color = Color(0.70, 0.82, 0.93)
	sky_material.ground_bottom_color = Color(0.42, 0.50, 0.58)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	var world_env := WorldEnvironment.new()
	world_env.name = "Entorno"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sol"
	sun.rotation_degrees = Vector3(-50.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)
	_sun = sun


func _random_seed() -> int:
	return randi() % 1000000


## Genera una pradera nueva del tamaño `size_key` (por defecto, el del mapa anterior).
## Un mapa S se arma en el momento; los más grandes se generan y mallan repartidos en
## varios frames, con el cartel de progreso y la edición en espera.
func _new_map(map_seed: int, size_key: String = "") -> void:
	if AppConfig.is_size_key(size_key):
		map_size_key = size_key.to_upper()
	var side: int = AppConfig.side_for(map_size_key)
	_busy_start = Time.get_ticks_msec()
	current_seed = map_seed
	# El historial apunta al mapa viejo: se vacía antes de reemplazarlo.
	controller.clear_history()
	world.clear(Vector3i(side, world.size_y, side))
	_generator = MeadowGenerator.new(world, props, map_seed, entities)
	ui.set_seed(map_seed)
	_frame_camera()
	if side <= AppConfig.INSTANT_SIDE:
		_generator.step(0)
		_generator = null
		world.remesh_dirty()
		props.rebuild_dirty()
		_finish_loading("Pradera generada")
	else:
		_set_busy("Generando")


func _set_busy(text: String) -> void:
	_busy = true
	_busy_text = text
	overlay.show_progress(text, 0.0)
	_update_input_state()


## Un frame de trabajo de la generación o carga en curso.
func _advance_loading() -> void:
	var fraction: float = 0.0
	if _generator != null:
		if _generator.step(GENERATION_BUDGET_MSEC):
			_generator = null
			fraction = GENERATION_SHARE
		else:
			fraction = _generator.progress() * GENERATION_SHARE
	elif world.pending_count() > 0:
		var share: float = GENERATION_SHARE if _busy_text == "Generando" else 0.0
		fraction = share + (1.0 - share) * world.pending_progress()
	elif props.dirty_count() > 0:
		# Faltan armar los últimos grupos de props.
		fraction = 0.99
	else:
		_finish_loading("Pradera generada" if _busy_text == "Generando" else "Mapa cargado")
		return
	overlay.show_progress(_busy_text, fraction)


func _finish_loading(what: String) -> void:
	_busy = false
	overlay.hide_progress()
	last_load_msec = Time.get_ticks_msec() - _busy_start
	_frame_camera()
	_update_input_state()
	print("%s: tamaño %s, semilla %d, %d chunks, %d props, %d criaturas, %d ms" % [
			what, AppConfig.world_label(world.size_x, world.size_z), current_seed, world.chunks.size(),
			props.props.size(), entities.entities.size(), last_load_msec])


func is_busy() -> bool:
	return _busy


func _frame_camera() -> void:
	@warning_ignore("integer_division")
	var ground: int = world.column_height(world.size_x / 2, world.size_z / 2)
	camera.frame_world(Vector3(world.size_x, world.size_y, world.size_z), float(ground))


## La edición solo recibe entrada en modo edición y sin diálogos abiertos.
func _update_input_state() -> void:
	var editing: bool = mode == Mode.EDIT and not _modal_open and not _new_dialog_open and not _busy
	controller.input_enabled = editing
	camera.input_enabled = editing
	object_editor.set_input_enabled(mode == Mode.OBJECTS and not _modal_open)


# ================================================================ edición

## Al elegir una herramienta, la línea de estado explica para qué sirve.
func _on_tool_changed(tool: int) -> void:
	ui.show_tool_hint("%s: %s" % [EditorController.TOOL_NAMES[tool], EditorController.TOOL_HINTS[tool]])


func _on_block_selected(id: int) -> void:
	controller.set_block(id)
	# Elegir un bloque con otra clase de herramienta activa vuelve a "colocar bloque".
	if controller.tool > EditorController.Tool.PAINT:
		controller.set_tool(EditorController.Tool.PLACE)


func _on_prop_selected(id: int) -> void:
	controller.set_prop(id)
	controller.set_tool(EditorController.Tool.PROP_PLACE)


func _on_entity_selected(type: int) -> void:
	controller.set_entity_type(type)
	controller.set_tool(EditorController.Tool.ENTITY_PLACE)


func _on_npc_edit_requested(cell: Vector3i) -> void:
	var data: Dictionary = entities.get_entity(cell)
	if data.is_empty():
		return
	var npc_name: String = data["name"]
	var lines: Array = data["lines"]
	ui.open_npc_editor(cell, npc_name, lines)


func _on_npc_edited(cell: Vector3i, npc_name: String, lines: Array) -> void:
	var data: Dictionary = entities.get_entity(cell)
	if data.is_empty():
		return
	var type: int = data["type"]
	var variant: int = data["variant"]
	var rot: int = data["rot"]
	# Pasa por el controlador para que el cambio se pueda deshacer.
	if controller.apply_entity(cell, EntityLayer.make_entity(type, variant, rot, npc_name, lines)):
		ui.show_message("Aldeano actualizado.")


## Botón "Nuevo": abre el diálogo de tamaño y semilla.
func _on_new_requested() -> void:
	if _busy or mode != Mode.EDIT:
		return
	new_dialog.open(UserSettings.load_map_size())


func _on_new_map_chosen(size_key: String, map_seed: int) -> void:
	if _busy or mode != Mode.EDIT:
		return
	UserSettings.save_map_size(size_key)
	_new_map(map_seed, size_key)
	ui.show_message("Pradera nueva: tamaño %s." % AppConfig.size_label(size_key))


func _on_new_dialog_visibility() -> void:
	_new_dialog_open = new_dialog.visible
	_update_input_state()


func _on_save_path(path: String) -> void:
	var error: String = MapIO.save_file(path, world, props, current_seed, entities)
	if error.is_empty():
		ui.show_message("Mapa guardado: %s" % path.get_file())
	else:
		ui.show_error(error)


func _on_load_path(path: String) -> void:
	if _busy:
		return
	# El cartel se dibuja antes de leer el archivo, que es la parte que no se puede repartir.
	_busy_start = Time.get_ticks_msec()
	overlay.show_progress("Cargando", 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var result: Dictionary = MapIO.load_file(path, world, props, entities)
	overlay.hide_progress()
	if not result["ok"]:
		var message: String = result["error"]
		ui.show_error("No se pudo cargar el mapa. %s" % message)
		return
	current_seed = result["seed"]
	controller.clear_history()
	_frame_camera()
	ui.set_seed(current_seed)
	var loaded_key: String = AppConfig.key_for_side(world.size_x) if world.size_x == world.size_z else ""
	if not loaded_key.is_empty():
		map_size_key = loaded_key
	# Las mallas del mapa cargado se arman de a pocas por frame.
	if world.pending_count() > 0:
		_set_busy("Cargando")
	var warning: String = result["warning"]
	if warning.is_empty():
		ui.show_message("Mapa cargado: %s" % path.get_file())
	else:
		ui.show_message("Mapa cargado: %s. %s" % [path.get_file(), warning], true)


func _on_modal_changed(open: bool) -> void:
	_modal_open = open
	_update_input_state()


# ================================================================ modo juego

## Abre el selector de avatar (botón Jugar o F5).
func request_play() -> void:
	if mode != Mode.EDIT or _modal_open or _new_dialog_open or _busy:
		return
	# El jugador aparece donde apuntaba el mouse, o en el centro del mapa.
	_spawn_hint = Vector2i(-1, -1)
	if controller.has_hover():
		var cell: Vector3i = controller.hover_cell()
		_spawn_hint = Vector2i(cell.x, cell.z)
	mode = Mode.SELECT
	_update_input_state()
	selector.open(avatar)


func _on_selector_cancelled() -> void:
	if mode != Mode.SELECT:
		return
	selector.close()
	mode = Mode.EDIT
	_update_input_state()


func _on_avatar_chosen(index: int) -> void:
	if mode != Mode.SELECT:
		return
	avatar = index
	UserSettings.save_avatar(index)
	selector.close()
	@warning_ignore("integer_division")
	var near: Vector2i = Vector2i(world.size_x / 2, world.size_z / 2)
	if _spawn_hint.x >= 0:
		near = _spawn_hint
	start_play(Player.find_spawn(world, props, near.x, near.y), capture_mouse_in_play)


func start_play(spawn: Vector3, capture_mouse: bool) -> void:
	mode = Mode.PLAY
	_update_input_state()
	ui.visible = false
	# La cámara del juego arranca mirando en la misma dirección que la del editor.
	play.cam_yaw = camera.yaw
	play.start(avatar, spawn, capture_mouse)


## Vuelve al editor: las criaturas regresan a su celda y la cámara del editor queda como estaba.
func stop_play() -> void:
	if mode != Mode.PLAY:
		return
	play.stop()
	entities.reset_actors()
	ui.visible = true
	camera.current = true
	mode = Mode.EDIT
	_update_input_state()


# ================================================================ editor de objetos

## Pasa al editor de objetos. El mapa no se toca: solo se oculta y deja de recibir entrada.
## Con `key` abre ese objeto; sin ella, la primera vez abre el prop elegido en la paleta
## y después retoma el objeto que se estaba editando.
func open_object_editor(key: String = "") -> void:
	if mode != Mode.EDIT or _modal_open or _new_dialog_open or _busy:
		return
	mode = Mode.OBJECTS
	_set_map_visible(false)
	object_editor.set_active(true)
	object_ui.visible = true
	var id: int = library.key_to_id(key)
	if id < 0 and not key.is_empty():
		object_ui.show_message("No existe el objeto «%s»." % key, true)
	if id < 0 and object_editor.is_new() and not object_editor.modified:
		id = controller.prop_id
	if id >= 0:
		object_editor.open_object(id)
	_update_input_state()


## Vuelve al editor de mapas, con el mapa, el historial y la cámara como estaban.
func close_object_editor() -> void:
	if mode != Mode.OBJECTS:
		return
	object_editor.set_active(false)
	object_ui.visible = false
	_set_map_visible(true)
	camera.current = true
	mode = Mode.EDIT
	_update_input_state()


func _set_map_visible(shown: bool) -> void:
	world.visible = shown
	props.visible = shown
	entities.visible = shown
	controller.visible = shown
	ui.visible = shown


## Un objeto cambió o se agregó: se rehacen las mallas de los props ya colocados y la paleta.
func _on_prop_changed(id: int) -> void:
	props.refresh_prop(id)
	ui.refresh_props(controller.prop_id)
	# La variante sorteada para la próxima colocación puede haber dejado de existir.
	controller.set_prop(controller.prop_id)


# ================================================================ capturas

## Guion de la captura automática según --shot-mode.
func _run_shot_script() -> void:
	_frames += 1
	if _shot_stage == 0 and _frames >= SHOT_FRAMES:
		_shot_stage = 1
		_frames = 0
		match _shot_mode:
			"selector":
				request_play()
			"play", "dialogo":
				_stage_play_shot(_shot_mode == "dialogo")
			"montando", "volando":
				_stage_ride_shot(_shot_mode == "volando")
	elif _shot_stage == 1 and (_shot_mode == "editor" or _frames >= SHOT_SETTLE_FRAMES):
		_shot_stage = 2
		_take_shot()


## Prepara una escena de juego para la captura: el jugador junto al aldeano (diálogo) o
## junto al grupo de animales más numeroso, con la cámara un poco de costado.
func _stage_play_shot(with_dialog: bool) -> void:
	var npc: EntityActor = null
	var crowd: EntityActor = null
	var crowd_size: int = -1
	for actor: EntityActor in entities.actors():
		if actor.is_npc():
			npc = actor
			continue
		var neighbours: int = 0
		for other: EntityActor in entities.actors():
			if other.home.distance_to(actor.home) < 5.0:
				neighbours += 1
		if neighbours > crowd_size:
			crowd_size = neighbours
			crowd = actor
	var subject: EntityActor = npc if with_dialog else crowd
	@warning_ignore("integer_division")
	var near := Vector2i(world.size_x / 2, world.size_z / 2)
	var focus := Vector3(near.x, 0.0, near.y)
	if subject != null:
		focus = subject.home
		# Se elige el lado más despejado: sin terreno más alto entre el sujeto y la cámara.
		var gap: int = 2 if with_dialog else 4
		var best_rise: int = 999
		for side: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
			var rise: int = 0
			for reach: int in range(1, gap + 5):
				var x: int = clampi(subject.cell.x + side.x * reach, 0, world.size_x - 1)
				var z: int = clampi(subject.cell.z + side.y * reach, 0, world.size_z - 1)
				rise = maxi(rise, absi(world.column_height(x, z) - subject.cell.y))
			if rise < best_rise:
				best_rise = rise
				near = Vector2i(subject.cell.x, subject.cell.z) + side * gap
	var spawn: Vector3 = Player.find_spawn(world, props, near.x, near.y)
	mode = Mode.SELECT
	start_play(spawn, false)
	var to_focus: Vector3 = focus - spawn
	play.cam_yaw = atan2(-to_focus.x, -to_focus.z) + (-0.7 if with_dialog else 0.55)
	play.cam_pitch = 0.5 if with_dialog else 0.38
	play.cam_distance = 5.0 if with_dialog else 6.5
	play.player.yaw = atan2(to_focus.x, to_focus.z)
	if with_dialog and npc != null:
		play.open_dialog(npc)


## Prepara la captura de una niña montando: pone un poni (o el dragón, en vuelo) en un
## lugar llano cerca del centro del mapa, la sube y acomoda la cámara.
func _stage_ride_shot(in_flight: bool) -> void:
	@warning_ignore("integer_division")
	var centre := Vector2i(world.size_x / 2, world.size_z / 2)
	var cell := Vector3i(-1, -1, -1)
	for radius: int in 24:
		for dz: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if cell.x >= 0 or maxi(absi(dx), absi(dz)) != radius:
					continue
				var candidate := Vector3i(centre.x + dx, world.column_height(centre.x + dx, centre.y + dz), centre.y + dz)
				# Lugar llano y despejado: la celda y sus vecinas, libres y a la misma altura.
				var flat: bool = true
				for nz: int in range(-2, 3):
					for nx: int in range(-2, 3):
						if not controller.is_free_cell(candidate + Vector3i(nx, 0, nz)):
							flat = false
				if flat:
					cell = candidate
	if cell.x < 0:
		return
	var type: int = CharacterLibrary.DRAGON if in_flight else CharacterLibrary.PONY
	entities.set_entity(cell, EntityLayer.make_entity(type, 0 if in_flight else 2, 0))
	avatar = 0
	mode = Mode.SELECT
	start_play(Vector3(cell.x + 2.0, cell.y, cell.z + 0.5), false)
	play.mount(entities.get_actor(cell))
	if in_flight:
		# Despega y sube un rato hacia adelante; después planea solo.
		for i: int in 170:
			play.simulate(1.0 / 60.0, Vector3(0.3, 0.0, 1.0).normalized(), i < 120, false)
		play.cam_yaw = 0.55
		play.cam_pitch = 0.42
		play.cam_distance = 3.6
	else:
		play.cam_yaw = 0.85
		play.cam_pitch = 0.28
		play.cam_distance = 4.2


func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(_shot_path)
	if error == OK:
		print("Captura guardada en %s" % _shot_path)
	else:
		push_error("No se pudo guardar la captura (error %d)." % error)
	get_tree().quit()
