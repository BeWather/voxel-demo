class_name Player
extends Node3D
## Personaje del modo juego: camina, corre, salta y nada sobre la grilla de voxeles.

const WALK_SPEED: float = 4.5
const RUN_SPEED: float = 7.5
const JUMP_SPEED: float = 8.6
const SWIM_UP_SPEED: float = 3.2
const WATER_SPEED_FACTOR: float = 0.55
const ACCELERATION: float = 14.0
const BODY_HALF: float = 0.3
const BODY_HEIGHT: float = 1.7
## Por debajo de esta altura el jugador reaparece.
const FALL_LIMIT: float = -3.0
## Trepar para salir del agua: al nadar contra un borde de hasta MANTLE_REACH bloques por
## encima de los pies, el jugador sube solo a MANTLE_SPEED hasta quedar arriba.
const MANTLE_REACH: float = 2.05
const MANTLE_SPEED: float = 5.0
const MANTLE_MAX_TIME: float = 2.0
const MANTLE_CLEARANCE: float = 0.12

var body: GridBody = GridBody.new(BODY_HALF, BODY_HEIGHT)
var rig: CharacterRig
var spawn: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var respawn_count: int = 0
## Se puede apagar para reproducir el comportamiento anterior (sin trepar) en las pruebas.
var mantle_enabled: bool = true
## Criatura que está montando, o null.
var mount: EntityActor

var _mantling: bool = false
var _mantle_top: float = 0.0
var _mantle_time: float = 0.0


func _init() -> void:
	rig = CharacterRig.new()
	add_child(rig)


## Cambia el modelo y el alto de la caja de colisión (una niña es más baja que un adulto).
func set_avatar(parts: Array[Dictionary], body_height: float = BODY_HEIGHT) -> void:
	rig.setup(parts)
	body.height = body_height


## Coloca al jugador y recuerda el punto como lugar de reaparición.
func place_at(point: Vector3) -> void:
	spawn = point
	_mantling = false
	body.teleport(point)
	_sync()


func is_mantling() -> bool:
	return _mantling


## Un paso de simulación. `wish` es la dirección horizontal deseada (largo 0 a 1).
func tick(delta: float, world: VoxelWorld, props: PropLayer, wish: Vector3, jump: bool, run: bool) -> void:
	var speed: float = RUN_SPEED if run else WALK_SPEED
	if body.in_water:
		speed *= WATER_SPEED_FACTOR
	var target: Vector3 = wish * speed
	var blend: float = clampf(ACCELERATION * delta, 0.0, 1.0)
	body.vel.x = lerpf(body.vel.x, target.x, blend)
	body.vel.z = lerpf(body.vel.z, target.z, blend)
	if jump:
		if body.on_ground and not body.in_water:
			body.vel.y = JUMP_SPEED
		elif body.in_water:
			# En el agua, mantener el salto hace subir.
			body.vel.y = move_toward(body.vel.y, SWIM_UP_SPEED, 30.0 * delta)
	if mantle_enabled:
		_update_mantle(world, wish, delta)
	body.step(world, props, delta)
	if body.pos.y < FALL_LIMIT:
		respawn_count += 1
		body.teleport(spawn)
	if wish.length_squared() > 0.01:
		yaw = lerp_angle(yaw, atan2(wish.x, wish.z), clampf(delta * 12.0, 0.0, 1.0))
	rig.animate(delta, Vector2(body.vel.x, body.vel.z).length())
	_sync()


## Salir del agua. Nadando, el impulso hacia arriba se corta en cuanto el pecho sale del
## agua, así que un salto desde el agua queda mucho más corto que uno desde el piso. Por eso,
## al avanzar contra un borde alcanzable, el jugador trepa solo hasta quedar encima.
func _update_mantle(world: VoxelWorld, wish: Vector3, delta: float) -> void:
	if wish.length_squared() < 0.01:
		_mantling = false
		return
	if not _mantling:
		if not body.in_water:
			return
		var top: float = _ledge_ahead(world, wish)
		if top < 0.0:
			return
		_mantling = true
		_mantle_top = top
		_mantle_time = 0.0
	_mantle_time += delta
	if _mantle_time > MANTLE_MAX_TIME:
		_mantling = false
		return
	if body.pos.y < _mantle_top + MANTLE_CLEARANCE:
		body.vel.y = MANTLE_SPEED
	else:
		# Ya está por encima del borde: termina de subir y la gravedad lo apoya arriba.
		body.vel.y = minf(body.vel.y, 1.0)
		_mantling = false


## Altura (y) del borde trepable que hay delante, o -1 si no hay: un bloque sólido con
## lugar libre encima para el cuerpo, a no más de MANTLE_REACH sobre los pies.
func _ledge_ahead(world: VoxelWorld, wish: Vector3) -> float:
	var dir: Vector3 = wish.normalized()
	var reach: float = body.half + 0.3
	# Se prueba la dirección de avance y sus dos componentes (por si se llega en diagonal).
	for probe_dir: Vector3 in [dir, Vector3(signf(dir.x), 0.0, 0.0) * absf(dir.x), Vector3(0.0, 0.0, signf(dir.z)) * absf(dir.z)]:
		if probe_dir.length_squared() < 0.04:
			continue
		var probe: Vector3 = body.pos + probe_dir.normalized() * reach
		var x: int = floori(probe.x)
		var z: int = floori(probe.z)
		if x == floori(body.pos.x) and z == floori(body.pos.z):
			continue
		var feet: int = floori(body.pos.y)
		var clearance: int = ceili(body.height)
		for y: int in range(feet, feet + 3):
			if not Blocks.is_solid(world.get_block_xyz(x, y, z)):
				continue
			var free: bool = true
			for above: int in range(1, clearance + 1):
				if Blocks.is_solid(world.get_block_xyz(x, y + above, z)):
					free = false
			var top: float = float(y + 1)
			if free and top > body.pos.y + 0.3 and top - body.pos.y <= MANTLE_REACH:
				return top
	return -1.0


## Mientras monta, el jugador no se simula: va sentado donde indique la montura.
func ride_pose(seat: Transform3D, ground: Vector3, delta: float) -> void:
	body.pos = ground
	body.vel = Vector3.ZERO
	body.on_ground = true
	body.in_water = false
	_mantling = false
	position = seat.origin
	rig.basis = seat.basis
	rig.seated = true
	rig.animate(delta, 0.0)


## Baja de la montura y queda de pie en `point`.
func dismount_to(point: Vector3, facing: float) -> void:
	mount = null
	rig.seated = false
	rig.basis = Basis.IDENTITY
	yaw = facing
	body.teleport(point)
	_sync()


func _sync() -> void:
	position = body.pos
	rig.rotation = Vector3(0.0, yaw, 0.0)


## Busca dónde aparecer cerca de la columna (x, z): sobre el bloque más alto, en una celda
## seca y sin props que estorben si hay alguna a pocas celdas.
static func find_spawn(world: VoxelWorld, props: PropLayer, near_x: int, near_z: int) -> Vector3:
	var cx: int = clampi(near_x, 0, world.size_x - 1)
	var cz: int = clampi(near_z, 0, world.size_z - 1)
	for radius: int in 9:
		for dz: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var x: int = cx + dx
				var z: int = cz + dz
				if x < 0 or z < 0 or x >= world.size_x or z >= world.size_z:
					continue
				var top: int = world.column_height(x, z)
				if top < 1 or not Blocks.is_solid(world.get_block_xyz(x, top - 1, z)):
					continue
				var cell := Vector3i(x, top, z)
				if props != null and props.props.has(cell):
					var prop_id: int = props.props[cell]["id"]
					if GridBody.prop_block_half(prop_id) > 0.0:
						continue
				return Vector3(x + 0.5, top, z + 0.5)
	# Sin celda seca cerca: se aparece igual sobre la columna pedida.
	return Vector3(cx + 0.5, world.column_height(cx, cz), cz + 0.5)
