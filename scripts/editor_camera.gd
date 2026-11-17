class_name EditorCamera
extends Camera3D
## Cámara orbital alrededor de un punto de foco.
## Botón central: orbitar. Shift + central o botón derecho: desplazar. Rueda: zoom.
## WASD / flechas: mover el foco. Q / E: girar.

const MIN_PITCH: float = 0.10
const MAX_PITCH: float = 1.54
const MIN_DISTANCE: float = 5.0
const MAX_DISTANCE: float = 160.0
const ORBIT_SPEED: float = 0.006
const KEY_ROTATE_SPEED: float = 1.6

var focus: Vector3 = Vector3.ZERO
var yaw: float = 0.65
var pitch: float = 0.72
var distance: float = 48.0
var bounds_min: Vector3 = Vector3.ZERO
var bounds_max: Vector3 = Vector3(64.0, 32.0, 64.0)
## Zoom máximo permitido: crece con el mapa para poder verlo entero.
var max_distance: float = MAX_DISTANCE
## Se desactiva mientras hay un diálogo abierto.
var input_enabled: bool = true
## El desplazamiento con el mouse sube y baja el foco en vez de avanzar sobre el piso
## (lo usa el editor de objetos, donde importa recorrer el modelo en altura).
var pan_vertical: bool = false

var _orbiting: bool = false
var _panning: bool = false


func _ready() -> void:
	fov = 55.0
	near = 0.1
	far = 600.0
	update_view()


## Centra la cámara sobre un mundo del tamaño dado.
func frame_world(world_size: Vector3, ground_height: float) -> void:
	bounds_min = Vector3.ZERO
	bounds_max = world_size
	focus = Vector3(world_size.x * 0.5, ground_height, world_size.z * 0.5)
	var span: float = maxf(world_size.x, world_size.z)
	max_distance = maxf(MAX_DISTANCE, span * 2.0)
	# El plano lejano acompaña al zoom máximo para que no recorte el lado opuesto del mapa.
	far = maxf(600.0, max_distance + span * 2.0)
	# Distancia a la que el mapa entero entra en la vista, con margen para el panel lateral.
	distance = clampf(span * 1.28, MIN_DISTANCE, max_distance)
	yaw = 0.65
	pitch = 0.72
	update_view()


func update_view() -> void:
	# El cabeceo se limita para que la cámara nunca baje del horizonte.
	pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
	distance = clampf(distance, MIN_DISTANCE, max_distance)
	focus.x = clampf(focus.x, bounds_min.x, bounds_max.x)
	focus.z = clampf(focus.z, bounds_min.z, bounds_max.z)
	if pan_vertical:
		focus.y = clampf(focus.y, bounds_min.y, bounds_max.y)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), focus + offset)


func _flat_forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _flat_right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		match mb.button_index:
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_panning = mb.shift_pressed
					_orbiting = not mb.shift_pressed
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_panning = true
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance *= 0.9
					update_view()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance *= 1.1
					update_view()


func _input(event: InputEvent) -> void:
	# El arrastre y la suelta se atienden aquí para no perderlos si el cursor pasa sobre la interfaz.
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed and (mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT):
			_orbiting = false
			_panning = false
	elif event is InputEventMouseMotion and (_orbiting or _panning):
		var mm: InputEventMouseMotion = event
		if _orbiting:
			yaw -= mm.relative.x * ORBIT_SPEED
			pitch += mm.relative.y * ORBIT_SPEED
		else:
			var scale_factor: float = distance * 0.0016
			focus -= _flat_right() * mm.relative.x * scale_factor
			if pan_vertical:
				focus.y += mm.relative.y * scale_factor
			else:
				focus += _flat_forward() * mm.relative.y * scale_factor
		update_view()


func _process(delta: float) -> void:
	if not input_enabled or Input.is_key_pressed(KEY_CTRL):
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move += _flat_forward()
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move -= _flat_forward()
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move += _flat_right()
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move -= _flat_right()
	var turn: float = 0.0
	if Input.is_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_key_pressed(KEY_E):
		turn -= 1.0
	if move == Vector3.ZERO and turn == 0.0:
		return
	if move != Vector3.ZERO:
		focus += move.normalized() * distance * 0.9 * delta
	yaw += turn * KEY_ROTATE_SPEED * delta
	update_view()
