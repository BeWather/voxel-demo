class_name PlayMode
extends Node3D
## Modo juego: jugador en tercera persona, cámara que lo sigue, animales que deambulan,
## aldeanos con diálogo, monturas, y juntar cosas para hacerse amiga de los animales
## (ver PlayFriends). Nunca modifica bloques ni props; de las criaturas solo cambia su
## progreso de amistad (corazones, nombre, seguir), que no es una edición del mapa.

## El jugador pidió volver al editor (Esc o el botón del HUD).
signal exit_requested

const TALK_DISTANCE: float = 2.4
const MOUSE_SENSITIVITY: float = 0.0045
const MIN_PITCH: float = -0.35
const MAX_PITCH: float = 1.35
const MIN_DISTANCE: float = 2.0
const MAX_DISTANCE: float = 14.0
const CAMERA_MARGIN: float = 0.35
## Solo se simulan las criaturas a esta distancia horizontal del jugador (en bloques).
const SIMULATION_RADIUS: float = 48.0
const HINT: String = "WASD: moverse · Shift: correr · Espacio: saltar / nadar · Mouse: cámara · " \
		+ "E: hablar / montar / juntar · F: dar de comer · G: seguir · 1–6: elegir · Esc: editor"
const RIDE_HINT: String = "WASD: dirigir · Shift: galopar · Espacio: saltar · E: bajar · Mouse: cámara · " \
		+ "Rueda: zoom · Esc: volver al editor"
const DRAGON_HINT: String = "WASD: dirigir · Espacio: despegar y subir · C: bajar · Shift: más rápido · " \
		+ "E: desmontar (en el suelo) · Mouse: cámara · Esc: volver al editor"
## Distancia a la que se puede montar una criatura.
const MOUNT_DISTANCE: float = 2.6
## Cuánto se aleja la cámara al montar y al volar.
const RIDE_CAMERA_FACTOR: float = 1.3
const FLY_CAMERA_FACTOR: float = 1.9
const NOTICE_SECONDS: float = 2.5
## Aviso al querer montar un unicornio o un dragón que todavía no es amigo.
const BEFRIEND_FIRST: String = "Hazte su amiga primero"
const PROMPT_SEPARATOR: String = "    ·    "

var world: VoxelWorld
var props: PropLayer
var entities: EntityLayer
var library: CharacterLibrary

var active: bool = false
var player: Player
var play_camera: Camera3D
var cam_yaw: float = 0.0
var cam_pitch: float = 0.45
var cam_distance: float = 7.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Criaturas simuladas en el último paso (las que estaban cerca del jugador).
var simulated_count: int = 0
## Juntar cosas, mochila y amistad con los animales.
var friends: PlayFriends

var _keys: Dictionary[int, bool] = {}
var _capture_mouse: bool = false
var _dialog_actor: EntityActor
var _dialog_index: int = 0
var _nearby_npc: EntityActor
var _nearby_mount: EntityActor
var _avatar: int = 0
var _camera_factor: float = 1.0
var _notice: String = ""
var _notice_time: float = 0.0
var _hint_label: Label
var _hud_root: Control
var _backpack_hud: BackpackHud

var _hud_layer: CanvasLayer
var _prompt_label: Label
var _dialog_panel: PanelContainer
var _dialog_name: Label
var _dialog_text: Label
var _dialog_hint: Label


func setup(p_world: VoxelWorld, p_props: PropLayer, p_entities: EntityLayer,
		p_library: CharacterLibrary) -> void:
	world = p_world
	props = p_props
	entities = p_entities
	library = p_library


func _init() -> void:
	# Se arma en _init para que funcione aunque el nodo todavía no esté en el árbol.
	player = Player.new()
	player.visible = false
	add_child(player)
	play_camera = Camera3D.new()
	play_camera.fov = 62.0
	play_camera.near = 0.08
	play_camera.far = 600.0
	add_child(play_camera)
	friends = PlayFriends.new()
	friends.setup(self)
	add_child(friends)
	_build_hud()


# ================================================================ entrar y salir

## Empieza a jugar con el avatar elegido en el punto dado.
func start(avatar: int, spawn: Vector3, capture_mouse: bool = true) -> void:
	_avatar = avatar
	_camera_factor = 1.0
	_notice_time = 0.0
	_nearby_mount = null
	player.set_avatar(library.get_avatar_parts(avatar), CharacterLibrary.avatar_body_height(avatar))
	player.dismount_to(spawn, cam_yaw + PI)
	player.place_at(spawn)
	player.yaw = cam_yaw + PI
	player.visible = true
	player.respawn_count = 0
	rng.randomize()
	_keys.clear()
	_dialog_actor = null
	_nearby_npc = null
	active = true
	_capture_mouse = capture_mouse
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hud_layer.visible = true
	_dialog_panel.visible = false
	_prompt_label.visible = false
	play_camera.current = true
	friends.start()
	if _backpack_hud == null:
		_backpack_hud = BackpackHud.new()
		_backpack_hud.setup(friends.icons)
		_backpack_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_backpack_hud.offset_left = -200
		_backpack_hud.offset_right = 200
		_backpack_hud.offset_top = -90
		_backpack_hud.offset_bottom = -38
		_hud_root.add_child(_backpack_hud)
	_update_camera()


## Termina el juego. Quien llama devuelve la cámara del editor y las criaturas a su lugar.
func stop() -> void:
	# Si estaba montado, se baja sin más: las criaturas vuelven a su celda al salir.
	if player.mount != null:
		var ridden: EntityActor = player.mount
		player.dismount_to(player.body.pos, player.yaw)
		ridden.end_ride()
	friends.stop()
	active = false
	player.visible = false
	_hud_layer.visible = false
	_dialog_actor = null
	_keys.clear()
	if _capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	play_camera.current = false


## ¿Hay algo abierto que deja quieto al jugador? (un diálogo o la ventana de poner nombre)
func is_dialog_open() -> bool:
	return _dialog_actor != null or friends.naming_actor != null


func captures_mouse() -> bool:
	return _capture_mouse


func hud_root() -> Control:
	return _hud_root


## Muestra un aviso corto en el lugar de los carteles de "E: …".
func show_notice(text: String) -> void:
	_notice = text
	_notice_time = NOTICE_SECONDS


# ================================================================ entrada

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _capture_mouse:
			cam_yaw -= motion.relative.x * MOUSE_SENSITIVITY
			cam_pitch = clampf(cam_pitch + motion.relative.y * MOUSE_SENSITIVITY, MIN_PITCH, MAX_PITCH)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_distance = maxf(cam_distance * 0.9, MIN_DISTANCE)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_distance = minf(cam_distance * 1.1, MAX_DISTANCE)
	elif event is InputEventKey:
		var key: InputEventKey = event
		# El estado de las teclas se lleva a mano a partir de los eventos.
		if key.pressed:
			_keys[key.keycode] = true
		else:
			_keys.erase(key.keycode)
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				exit_requested.emit()
			elif friends.naming_actor != null:
				# Se está escribiendo un nombre: las letras no son órdenes.
				pass
			elif key.keycode == KEY_E:
				interact()
			elif key.keycode == KEY_F:
				friends.feed()
			elif key.keycode == KEY_G:
				friends.toggle_follow()
			elif key.keycode >= KEY_1 and key.keycode <= KEY_6:
				friends.selected = key.keycode - KEY_1


func _held(keycode: Key) -> bool:
	return _keys.has(keycode)


## Dirección de movimiento pedida por el teclado, relativa a la cámara.
func _wish_direction() -> Vector3:
	var forward := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var wish := Vector3.ZERO
	if _held(KEY_W) or _held(KEY_UP):
		wish += forward
	if _held(KEY_S) or _held(KEY_DOWN):
		wish -= forward
	if _held(KEY_D) or _held(KEY_RIGHT):
		wish += right
	if _held(KEY_A) or _held(KEY_LEFT):
		wish -= right
	return wish.normalized() if wish != Vector3.ZERO else wish


# ================================================================ simulación

func _process(delta: float) -> void:
	if not active:
		return
	simulate(minf(delta, 0.05), _wish_direction(), _held(KEY_SPACE), _held(KEY_SHIFT), _held(KEY_C))
	_notice_time = maxf(_notice_time - delta, 0.0)
	_update_camera(delta)
	_update_hud()


## Un paso de juego con la entrada dada (también lo usan las pruebas).
## `descend` es la tecla de bajar del dragón en vuelo.
func simulate(delta: float, wish: Vector3, jump: bool, run: bool, descend: bool = false) -> void:
	var frozen: bool = is_dialog_open()
	if player.mount != null:
		# Montado: la entrada dirige a la criatura y el jugador va sentado en su lomo.
		var ridden: EntityActor = player.mount
		if frozen:
			ridden.ride_tick(delta, world, props, Vector3.ZERO, false, false, false)
		else:
			ridden.ride_tick(delta, world, props, wish, jump, descend, run)
		player.ride_pose(ridden.seat_transform(CharacterLibrary.avatar_hip_height(_avatar)), ridden.body.pos, delta)
	elif frozen:
		# Con un diálogo abierto el jugador queda quieto (la gravedad sigue actuando).
		player.tick(delta, world, props, Vector3.ZERO, false, false)
	else:
		player.tick(delta, world, props, wish, jump, run)
	_nearby_npc = null
	_nearby_mount = null
	simulated_count = 0
	var nearest: float = TALK_DISTANCE
	var nearest_mount: float = MOUNT_DISTANCE
	var player_pos: Vector3 = player.body.pos
	for actor: EntityActor in entities.actors():
		# Las criaturas lejanas no se simulan: quedan quietas donde están.
		var dx: float = actor.body.pos.x - player_pos.x
		var dz: float = actor.body.pos.z - player_pos.z
		if dx * dx + dz * dz > SIMULATION_RADIUS * SIMULATION_RADIUS:
			continue
		simulated_count += 1
		if actor.ridden:
			continue
		actor.tick(delta, world, props, player_pos, rng)
		var dist: float = actor.body.pos.distance_to(player_pos)
		if actor.is_npc():
			if dist < nearest:
				nearest = dist
				_nearby_npc = actor
		elif actor.is_rideable() and player.mount == null and dist < nearest_mount:
			nearest_mount = dist
			_nearby_mount = actor
	# El aviso de "E" es para lo que esté más cerca: el aldeano o la montura.
	if _nearby_npc != null and _nearby_mount != null:
		if nearest <= nearest_mount:
			_nearby_mount = null
		else:
			_nearby_npc = null
	friends.tick(delta)


## Tecla E: avanza el diálogo abierto o baja de la montura; si no, por orden de prioridad,
## habla con el aldeano cercano, monta la criatura cercana o junta lo que haya al alcance.
func interact() -> void:
	if _dialog_actor != null:
		_dialog_index += 1
		var lines: Array = _dialog_actor.data["lines"]
		if _dialog_index >= lines.size():
			_dialog_actor = null
		return
	if friends.naming_actor != null:
		return
	if player.mount != null:
		dismount()
	elif _nearby_npc != null:
		open_dialog(_nearby_npc)
	elif _nearby_mount != null and friends.can_mount(_nearby_mount):
		mount(_nearby_mount)
	elif not friends.nearby_gather.is_empty():
		friends.gather()
	elif _nearby_mount != null:
		show_notice(BEFRIEND_FIRST)


func is_mounted() -> bool:
	return player.mount != null


## Sube al jugador a una criatura montable.
func mount(actor: EntityActor) -> bool:
	if actor == null or not actor.is_rideable() or player.mount != null or not friends.can_mount(actor):
		return false
	player.mount = actor
	actor.start_ride()
	_nearby_mount = null
	player.ride_pose(actor.seat_transform(CharacterLibrary.avatar_hip_height(_avatar)), actor.body.pos, 0.0)
	return true


## Baja de la montura a una celda libre a su lado. En vuelo no se puede: hay que aterrizar.
func dismount() -> bool:
	var ridden: EntityActor = player.mount
	if ridden == null:
		return false
	if ridden.flying:
		_notice = "Aterriza para bajar"
		_notice_time = NOTICE_SECONDS
		return false
	var spot: Vector3 = find_dismount_spot(ridden)
	player.dismount_to(spot, ridden.yaw)
	ridden.end_ride()
	return true


## Dónde queda el jugador al bajar: una celda vecina con piso firme, sin agua, sin caída y
## con lugar para su cuerpo. Primero a los costados, después atrás, adelante y más lejos.
func find_dismount_spot(ridden: EntityActor) -> Vector3:
	var side := Vector3(cos(ridden.yaw), 0.0, -sin(ridden.yaw))
	var forward := Vector3(sin(ridden.yaw), 0.0, cos(ridden.yaw))
	var offsets: Array[Vector3] = [side, -side, -forward, forward, side - forward, -side - forward,
			side + forward, -side + forward, side * 2.0, -side * 2.0, -forward * 2.0, forward * 2.0]
	var base_y: int = floori(ridden.body.pos.y + 0.05)
	var probe := GridBody.new(player.body.half, player.body.height)
	for offset: Vector3 in offsets:
		var point: Vector3 = ridden.body.pos + offset * 1.05
		var x: int = floori(point.x)
		var z: int = floori(point.z)
		if x < 0 or z < 0 or x >= world.size_x or z >= world.size_z:
			continue
		for dy: int in [0, 1, -1]:
			var y: int = base_y + dy
			if not Blocks.is_solid(world.get_block_xyz(x, y - 1, z)) or world.get_block_xyz(x, y, z) != Blocks.AIR:
				continue
			probe.pos = Vector3(x + 0.5, y, z + 0.5)
			if probe.overlapping(world, props).is_empty():
				return probe.pos
	# Sin lugar alrededor (por ejemplo, encerrado): queda de pie sobre la montura.
	return ridden.body.pos + Vector3(0.0, ridden.body.height + 0.05, 0.0)


func open_dialog(actor: EntityActor) -> void:
	_dialog_actor = actor
	_dialog_index = 0


func _update_camera(delta: float = 0.0) -> void:
	# La cámara mira a la altura de la cabeza del avatar, sea adulto o niña.
	var target: Vector3 = player.body.pos + Vector3(0.0, player.body.height * 0.85, 0.0)
	var wanted_factor: float = 1.0
	if player.mount != null:
		# Montado, mira al jinete; en vuelo se aleja para disfrutar el mapa desde arriba.
		target = player.position + Vector3(0.0, player.body.height * 0.7, 0.0)
		wanted_factor = FLY_CAMERA_FACTOR if player.mount.flying else RIDE_CAMERA_FACTOR
	_camera_factor = lerpf(_camera_factor, wanted_factor, clampf(delta * 2.5, 0.0, 1.0)) if delta > 0.0 else wanted_factor
	var offset := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	var reach: float = cam_distance * _camera_factor
	var distance: float = reach
	# Si hay terreno entre el jugador y la cámara, la cámara se acerca.
	var hit: Dictionary = world.raycast(target, offset, reach + CAMERA_MARGIN, true)
	if hit["hit"]:
		var hit_distance: float = hit["distance"]
		distance = clampf(hit_distance - CAMERA_MARGIN, 0.5, reach)
	play_camera.transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), target + offset * distance)


# ================================================================ HUD

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.visible = false
	add_child(_hud_layer)
	var root := Control.new()
	_hud_root = root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = EditorUI.make_theme()
	_hud_layer.add_child(root)

	var back := Button.new()
	back.text = "Editar (Esc)"
	back.focus_mode = Control.FOCUS_NONE
	back.position = Vector2(10, 10)
	back.pressed.connect(func() -> void: exit_requested.emit())
	root.add_child(back)

	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -30
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var hint := Label.new()
	_hint_label = hint
	hint.text = HINT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", EditorUI.COL_DIM)
	bar.add_child(hint)

	_prompt_label = Label.new()
	_prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -460
	_prompt_label.offset_right = 460
	_prompt_label.offset_top = -128
	_prompt_label.offset_bottom = -98
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_prompt_label.add_theme_constant_override("outline_size", 6)
	root.add_child(_prompt_label)

	_dialog_panel = PanelContainer.new()
	_dialog_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_dialog_panel.offset_left = -380
	_dialog_panel.offset_right = 380
	_dialog_panel.offset_top = -190
	_dialog_panel.offset_bottom = -48
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.13, 0.94)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.62, 0.86, 0.55)
	style.set_content_margin_all(16)
	_dialog_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_dialog_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_dialog_panel.add_child(box)
	_dialog_name = Label.new()
	_dialog_name.add_theme_font_size_override("font_size", 18)
	_dialog_name.add_theme_color_override("font_color", Color(0.62, 0.86, 0.55))
	box.add_child(_dialog_name)
	_dialog_text = Label.new()
	_dialog_text.add_theme_font_size_override("font_size", 17)
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_dialog_text)
	_dialog_hint = Label.new()
	_dialog_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dialog_hint.add_theme_font_size_override("font_size", 12)
	_dialog_hint.add_theme_color_override("font_color", EditorUI.COL_DIM)
	box.add_child(_dialog_hint)


func _update_hud() -> void:
	# La línea de controles cambia según se camine, se monte o se vuele.
	var hint_text: String = HINT
	if player.mount != null:
		hint_text = DRAGON_HINT if player.mount.can_fly() else RIDE_HINT
	if _hint_label.text != hint_text:
		_hint_label.text = hint_text
	if _dialog_actor != null:
		var lines: Array = _dialog_actor.data["lines"]
		_dialog_panel.visible = true
		_prompt_label.visible = false
		_dialog_name.text = _dialog_actor.display_name()
		_backpack_hud.visible = false
		if lines.is_empty():
			_dialog_text.text = "..."
		else:
			_dialog_text.text = str(lines[mini(_dialog_index, lines.size() - 1)])
		var last: bool = _dialog_index >= lines.size() - 1
		_dialog_hint.text = "E: %s   (%d/%d)" % ["cerrar" if last else "continuar",
				mini(_dialog_index + 1, maxi(lines.size(), 1)), maxi(lines.size(), 1)]
		return
	_dialog_panel.visible = false
	_backpack_hud.visible = true
	_backpack_hud.refresh(friends.backpack)
	_backpack_hud.select(friends.selected)
	var prompt: String = prompt_text()
	_prompt_label.text = prompt
	_prompt_label.visible = not prompt.is_empty()


## Aviso que corresponde mostrar ahora ("E: montar…", "E: hablar…", un mensaje), o "".
func prompt_text() -> String:
	if _dialog_actor != null:
		return ""
	if _notice_time > 0.0:
		return _notice
	# El cartel siempre dice qué hace cada tecla ahora: E (hablar, montar o juntar), F (dar
	# de comer o acariciar a la criatura cercana) y G (que la siga o se quede).
	var parts: Array[String] = []
	if _nearby_npc != null:
		parts.append("E: hablar con %s" % _nearby_npc.display_name())
	elif _nearby_mount != null and friends.can_mount(_nearby_mount):
		parts.append("E: montar (%s)" % _nearby_mount.display_name().to_lower())
	elif not friends.nearby_gather.is_empty():
		var item: int = friends.nearby_gather["item"]
		parts.append("E: juntar %s" % Items.NAMES[item])
	elif _nearby_mount != null:
		parts.append(BEFRIEND_FIRST)
	var creature: EntityActor = friends.nearby_creature
	if creature != null:
		var food: int = friends.food_for(creature)
		if food >= 0:
			parts.append("F: dar %s" % Items.NAMES[food])
		else:
			parts.append("F: acariciar")
		if creature.hearts() >= Items.HEARTS_FRIEND:
			parts.append("G: que se quede" if creature.is_following() else "G: que te siga")
	return PROMPT_SEPARATOR.join(parts)
