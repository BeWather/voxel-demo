class_name EntityActor
extends Node3D
## Una criatura en el mapa (animal o aldeano). En modo edición queda quieta en su celda;
## en modo juego los animales deambulan con una máquina de estados y los aldeanos miran
## al jugador cuando se acerca.

enum State { IDLE, WALK, LOOK, FLEE }

const LEASH: float = 6.0
const FLEE_DISTANCE: float = 3.5
const FLEE_SPEED_FACTOR: float = 2.0
const STEP_JUMP_SPEED: float = 8.0
const HOP_SPEED: float = 4.2
const NPC_LOOK_DISTANCE: float = 5.0
## Montura: salto, vuelo del dragón y límites.
const RIDE_JUMP_SPEED: float = 9.2
const RIDE_ACCELERATION: float = 9.0
const FLY_SPEED: float = 9.0
const FLY_CLIMB_SPEED: float = 5.5
const FLY_VERTICAL_ACCELERATION: float = 16.0
const FLY_ACCELERATION: float = 3.5
## El dragón puede subir hasta este margen por encima del límite de altura del mundo.
const FLY_CEILING_MARGIN: float = 8.0
const MAP_EDGE_MARGIN: float = 0.6
## Seguir al jugador: a qué distancia se detiene y qué tan rápido puede ir para no perderlo.
const FOLLOW_STOP_DISTANCE: float = 2.4
const FOLLOW_MAX_SPEED: float = 8.5
const HAPPY_HOP_SPEED: float = 3.6
## Resultado de mirar el terreno hacia adelante.
const AHEAD_BLOCKED: int = 0
const AHEAD_OK: int = 1
const AHEAD_STEP_UP: int = 2

var cell: Vector3i = Vector3i.ZERO
var type: int = 0
var data: Dictionary = {}
var rig: CharacterRig
var body: GridBody
var home: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var state: int = State.IDLE
## La está montando el jugador: su comportamiento propio queda en pausa.
var ridden: bool = false
## Dragón en vuelo (solo montado).
var flying: bool = false

var _base_yaw: float = 0.0
var _timer: float = 1.0
var _target: Vector3 = Vector3.ZERO
var _flee_dir: Vector3 = Vector3.ZERO
var _shake_time: float = 0.0


func setup(library: CharacterLibrary, p_cell: Vector3i, p_data: Dictionary) -> void:
	cell = p_cell
	data = p_data
	type = data["type"]
	var variant: int = data["variant"]
	rig = CharacterRig.new()
	add_child(rig)
	rig.setup(library.get_entity_parts(type, variant))
	body = GridBody.new(CharacterLibrary.BODY_HALF[type], CharacterLibrary.BODY_HEIGHT[type])
	var rot: int = data["rot"]
	_base_yaw = float(rot) * PI * 0.5
	home = Vector3(cell.x + 0.5, cell.y, cell.z + 0.5)
	reset()


func is_npc() -> bool:
	return type == CharacterLibrary.VILLAGER


func display_name() -> String:
	var custom: String = data["name"]
	return custom if not custom.is_empty() else CharacterLibrary.ENTITY_NAMES[type]


## Vuelve a la celda donde fue colocada, en pose de reposo.
func reset() -> void:
	home = Vector3(cell.x + 0.5, cell.y, cell.z + 0.5)
	ridden = false
	flying = false
	body.teleport(home)
	body.use_gravity = true
	yaw = _base_yaw
	state = State.IDLE
	_timer = 1.0
	rig.reset_pose()
	rig.rotation = Vector3.ZERO
	_sync()


# ================================================================ amistad

## Puntos de amistad (0 a Items.MAX_POINTS). Viven en los datos de la criatura.
func friendship() -> int:
	return data.get("friendship", 0)


## Corazones de amistad, de 0 a 3.
func hearts() -> int:
	return Items.hearts_for(friendship())


## Suma puntos de amistad. Devuelve true si con eso ganó un corazón.
func add_friendship(points: int) -> bool:
	var before: int = hearts()
	data["friendship"] = clampi(friendship() + points, 0, Items.MAX_POINTS)
	return hearts() > before


## ¿Está siguiendo al jugador? Hace falta ser amigos (2 corazones) y habérselo pedido.
func is_following() -> bool:
	return data.get("follow", false) and hearts() >= Items.HEARTS_FRIEND and not is_npc()


func set_following(on: bool) -> void:
	data["follow"] = on
	if on:
		state = State.IDLE
	else:
		home = body.pos


## Dice que no con la cabeza (cuando le ofrecen algo que no quiere).
func shake_head() -> void:
	_shake_time = 0.6


## Seguir al jugador: va hacia él y se detiene cerca. No entra al agua (salvo el pato) ni
## se tira de bordes altos; si queda lejos, el modo juego lo trae a una celda cercana.
func _follow_tick(delta: float, world: VoxelWorld, props: PropLayer, to_player: Vector3,
		player_dist: float) -> void:
	var is_duck: bool = type == CharacterLibrary.DUCK
	var dir := Vector3.ZERO
	var jump: bool = false
	var speed: float = 0.0
	if player_dist > FOLLOW_STOP_DISTANCE and player_dist < INF:
		speed = clampf(player_dist * 2.2, CharacterLibrary.WALK_SPEED[type], FOLLOW_MAX_SPEED)
		var straight: Vector3 = to_player.normalized()
		for turn: float in [0.0, 0.8, -0.8, 1.5, -1.5]:
			var candidate: Vector3 = straight.rotated(Vector3.UP, turn)
			var ahead: int = look_ahead(world, candidate, is_duck)
			if ahead != AHEAD_BLOCKED:
				dir = candidate
				jump = ahead == AHEAD_STEP_UP
				break
	body.vel.x = dir.x * speed
	body.vel.z = dir.z * speed
	var floating: bool = is_duck and _duck_float(world, delta)
	if dir != Vector3.ZERO:
		if jump and (body.on_ground or floating):
			body.vel.y = STEP_JUMP_SPEED
			body.use_gravity = true
		elif type == CharacterLibrary.RABBIT and body.on_ground:
			body.vel.y = HOP_SPEED
		yaw = lerp_angle(yaw, atan2(dir.x, dir.z), clampf(delta * 9.0, 0.0, 1.0))
	var before: Vector3 = body.pos
	body.step(world, props, delta)
	if not _has_floor(world, body.pos, is_duck):
		body.pos.x = before.x
		body.pos.z = before.z
	# Su lugar es donde esté: cuando deje de seguir, se queda paseando por ahí.
	home = body.pos
	rig.animate(delta, Vector2(body.vel.x, body.vel.z).length())
	_sync()


# ================================================================ montura

func is_rideable() -> bool:
	return CharacterLibrary.is_rideable(type)


func can_fly() -> bool:
	return type == CharacterLibrary.DRAGON


## El jugador se sube: la criatura deja de decidir por su cuenta.
func start_ride() -> void:
	ridden = true
	flying = false
	state = State.IDLE
	rig.head_yaw = 0.0


## El jugador se baja: la criatura retoma su vida desde donde quedó. Su punto de origen
## pasa a ser ese lugar, así no cruza el mapa para volver al anterior.
func end_ride() -> void:
	ridden = false
	flying = false
	home = body.pos
	body.use_gravity = true
	body.vel = Vector3.ZERO
	state = State.IDLE
	_timer = 2.0
	rig.flight = 0.0
	rig.rotation = Vector3.ZERO
	_sync()


## Dónde va sentado el jinete: transformación de sus pies en el mundo. `hip_height` es la
## altura de su cadera, que se apoya un voxel por encima del lomo.
func seat_transform(hip_height: float) -> Transform3D:
	var frame: Basis = Basis(Vector3.UP, yaw) * rig.basis
	var local: Vector3 = CharacterLibrary.seat_position(type) + Vector3(0.0, PropLibrary.VOXEL - hip_height, 0.0)
	return Transform3D(frame, body.pos + frame * local)


## Un paso con el jugador montado. `wish` es la dirección pedida (largo 0 a 1).
func ride_tick(delta: float, world: VoxelWorld, props: PropLayer, wish: Vector3, jump: bool,
		descend: bool, gallop: bool) -> void:
	if can_fly() and not flying and jump:
		# El dragón despega con el salto.
		flying = true
		body.use_gravity = false
		body.vel.y = FLY_CLIMB_SPEED * 0.6
	if flying:
		_fly_tick(delta, world, props, wish, jump, descend, gallop)
		return
	var speed: float = CharacterLibrary.RIDE_SPEED[type] * (CharacterLibrary.GALLOP_FACTOR if gallop else 1.0)
	var dir: Vector3 = wish
	var step_up: bool = false
	if dir != Vector3.ZERO:
		var ahead: int = ride_ahead(world, dir.normalized())
		if ahead == AHEAD_BLOCKED:
			# Agua o borde del mapa: frena en seco, sin deslizarse hacia adentro.
			dir = Vector3.ZERO
			body.vel.x = 0.0
			body.vel.z = 0.0
		elif ahead == AHEAD_STEP_UP:
			step_up = true
	var blend: float = clampf(RIDE_ACCELERATION * delta, 0.0, 1.0)
	body.vel.x = lerpf(body.vel.x, dir.x * speed, blend)
	body.vel.z = lerpf(body.vel.z, dir.z * speed, blend)
	if body.on_ground:
		if jump:
			body.vel.y = RIDE_JUMP_SPEED
		elif step_up:
			# Sube sola los escalones de un bloque: nadie queda trabado en una terraza.
			body.vel.y = STEP_JUMP_SPEED
	body.use_gravity = true
	body.step(world, props, delta)
	_keep_inside(world)
	if dir != Vector3.ZERO:
		yaw = lerp_angle(yaw, atan2(dir.x, dir.z), clampf(delta * 7.0, 0.0, 1.0))
	rig.flight = lerpf(rig.flight, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	rig.rotation = rig.rotation.lerp(Vector3.ZERO, clampf(delta * 8.0, 0.0, 1.0))
	rig.animate(delta, Vector2(body.vel.x, body.vel.z).length())
	_sync()


## Terreno delante de la montura: las monturas de tierra no entran al agua ni salen del
## mapa; los escalones de un bloque se suben. Las caídas quedan a criterio del jinete.
func ride_ahead(world: VoxelWorld, dir: Vector3) -> int:
	var probe: Vector3 = body.pos + dir * (body.half + 0.4)
	var x: int = floori(probe.x)
	var z: int = floori(probe.z)
	if x < 0 or z < 0 or x >= world.size_x or z >= world.size_z:
		return AHEAD_BLOCKED
	if x == floori(body.pos.x) and z == floori(body.pos.z):
		return AHEAD_OK
	var feet: int = floori(body.pos.y + 0.05)
	if Blocks.is_solid(world.get_block_xyz(x, feet + 1, z)):
		return AHEAD_BLOCKED
	if Blocks.is_solid(world.get_block_xyz(x, feet, z)):
		return AHEAD_STEP_UP
	for y: int in range(feet, -1, -1):
		var block: int = world.get_block_xyz(x, y, z)
		if block == Blocks.WATER:
			return AHEAD_BLOCKED
		if Blocks.is_solid(block):
			return AHEAD_OK
	return AHEAD_BLOCKED


## Vuelo del dragón: Espacio sube, `descend` baja y sin ninguna de las dos planea nivelado.
func _fly_tick(delta: float, world: VoxelWorld, props: PropLayer, wish: Vector3, jump: bool,
		descend: bool, fast: bool) -> void:
	var climb: float = 0.0
	if jump:
		climb = FLY_CLIMB_SPEED
	elif descend:
		climb = -FLY_CLIMB_SPEED
	body.vel.y = move_toward(body.vel.y, climb, FLY_VERTICAL_ACCELERATION * delta)
	var speed: float = FLY_SPEED * (1.45 if fast else 1.0)
	var blend: float = clampf(FLY_ACCELERATION * delta, 0.0, 1.0)
	body.vel.x = lerpf(body.vel.x, wish.x * speed, blend)
	body.vel.z = lerpf(body.vel.z, wish.z * speed, blend)
	body.use_gravity = false
	body.step(world, props, delta)
	_keep_inside(world)
	# Techo de vuelo.
	var ceiling: float = float(world.size_y) + FLY_CEILING_MARGIN
	if body.pos.y > ceiling:
		body.pos.y = ceiling
		body.vel.y = minf(body.vel.y, 0.0)
	# Sobre el agua no se hunde: queda al ras de la superficie.
	var surface: float = _water_surface(world)
	if surface > -INF and body.pos.y < surface + 0.05:
		body.pos.y = surface + 0.05
		body.vel.y = maxf(body.vel.y, 0.0)
	elif body.on_ground and not jump:
		# Tocó tierra: aterriza.
		flying = false
		body.use_gravity = true
	var old_yaw: float = yaw
	var flat := Vector2(body.vel.x, body.vel.z)
	if flat.length() > 0.5:
		yaw = lerp_angle(yaw, atan2(flat.x, flat.y), clampf(delta * 4.0, 0.0, 1.0))
	# El cuerpo se inclina al subir o bajar y se ladea en los giros.
	var turn_rate: float = angle_difference(old_yaw, yaw) / maxf(delta, 0.0001)
	var pitch: float = clampf(-body.vel.y * 0.06, -0.38, 0.38)
	var roll: float = clampf(-turn_rate * 0.22, -0.45, 0.45)
	rig.rotation = rig.rotation.lerp(Vector3(pitch, 0.0, roll), clampf(delta * 5.0, 0.0, 1.0))
	rig.flight = lerpf(rig.flight, 1.0 if flying else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	rig.flap_rate = 11.0 if body.vel.y > 0.5 else 6.5
	rig.animate(delta, 0.0)
	_sync()


## Borde del mapa: la montura frena ahí en vez de caerse fuera.
func _keep_inside(world: VoxelWorld) -> void:
	var max_x: float = float(world.size_x) - MAP_EDGE_MARGIN
	var max_z: float = float(world.size_z) - MAP_EDGE_MARGIN
	if body.pos.x < MAP_EDGE_MARGIN or body.pos.x > max_x:
		body.pos.x = clampf(body.pos.x, MAP_EDGE_MARGIN, max_x)
		body.vel.x = 0.0
	if body.pos.z < MAP_EDGE_MARGIN or body.pos.z > max_z:
		body.pos.z = clampf(body.pos.z, MAP_EDGE_MARGIN, max_z)
		body.vel.z = 0.0


## Altura de la superficie del agua bajo los pies, o -INF si no hay agua ahí.
func _water_surface(world: VoxelWorld) -> float:
	var x: int = floori(body.pos.x)
	var z: int = floori(body.pos.z)
	var y: int = floori(body.pos.y)
	if world.get_block_xyz(x, y, z) != Blocks.WATER and world.get_block_xyz(x, y - 1, z) == Blocks.WATER \
			and body.pos.y - float(y) < 0.1:
		y -= 1
	if world.get_block_xyz(x, y, z) != Blocks.WATER:
		return -INF
	while world.get_block_xyz(x, y + 1, z) == Blocks.WATER:
		y += 1
	return float(y + 1) - ChunkMesher.WATER_DROP


func _sync() -> void:
	position = body.pos
	rotation.y = yaw


## Un paso de comportamiento en modo juego.
func tick(delta: float, world: VoxelWorld, props: PropLayer, player_pos: Vector3,
		rng: RandomNumberGenerator) -> void:
	var to_player := Vector3(player_pos.x - body.pos.x, 0.0, player_pos.z - body.pos.z)
	var player_dist: float = to_player.length()
	if absf(player_pos.y - body.pos.y) > 3.0:
		player_dist = INF

	if _shake_time > 0.0:
		_shake_time -= delta
		rig.head_yaw = sin(_shake_time * 26.0) * 0.55 if _shake_time > 0.0 else 0.0

	if is_npc():
		# El aldeano no se mueve: gira hacia el jugador si está cerca.
		var wanted: float = _base_yaw
		if player_dist < NPC_LOOK_DISTANCE and player_dist > 0.05:
			wanted = atan2(to_player.x, to_player.z)
		yaw = lerp_angle(yaw, wanted, clampf(delta * 5.0, 0.0, 1.0))
		rig.animate(delta, 0.0)
		_sync()
		return

	if is_following():
		_follow_tick(delta, world, props, to_player, player_dist)
		return

	var is_duck: bool = type == CharacterLibrary.DUCK
	var speed: float = CharacterLibrary.WALK_SPEED[type]
	var dir := Vector3.ZERO

	# Con tres corazones, de vez en cuando da un saltito de alegría cerca del jugador.
	if hearts() >= Items.HEARTS_BEST and player_dist < 6.0 and body.on_ground and state == State.IDLE \
			and rng.randf() < delta * 0.5:
		body.vel.y = HAPPY_HOP_SPEED

	# Con un corazón ya no le tiene miedo al jugador.
	if CharacterLibrary.FLEES[type] and hearts() < Items.HEARTS_NO_FLEE and player_dist < FLEE_DISTANCE \
			and state != State.FLEE:
		state = State.FLEE
		_timer = 1.6
		_flee_dir = -to_player.normalized() if player_dist > 0.05 else Vector3(1.0, 0.0, 0.0)

	_timer -= delta
	match state:
		State.IDLE:
			if _timer <= 0.0:
				if rng.randf() < 0.3:
					state = State.LOOK
					_timer = rng.randf_range(1.0, 2.2)
					rig.head_yaw = rng.randf_range(-0.9, 0.9)
				else:
					_pick_target(world, rng, is_duck)
		State.LOOK:
			if _timer <= 0.0:
				rig.head_yaw = 0.0
				state = State.IDLE
				_timer = rng.randf_range(0.8, 2.5)
		State.WALK:
			var to_target := Vector3(_target.x - body.pos.x, 0.0, _target.z - body.pos.z)
			if to_target.length() < 0.25 or _timer <= 0.0:
				_go_idle(rng)
			else:
				dir = to_target.normalized()
		State.FLEE:
			speed *= FLEE_SPEED_FACTOR
			if _timer <= 0.0:
				_go_idle(rng)
			else:
				dir = _choose_flee_dir(world, is_duck)

	# Antes de avanzar se mira el terreno: ni paredes, ni caídas altas, ni agua (salvo el pato).
	var jump: bool = false
	if dir != Vector3.ZERO:
		var ahead: int = look_ahead(world, dir, is_duck)
		if ahead == AHEAD_BLOCKED or not _within_leash(body.pos + dir * 0.6):
			dir = Vector3.ZERO
			if state == State.WALK:
				_go_idle(rng)
		elif ahead == AHEAD_STEP_UP:
			jump = true

	body.vel.x = dir.x * speed
	body.vel.z = dir.z * speed
	var floating: bool = is_duck and _duck_float(world, delta)
	if dir != Vector3.ZERO:
		if jump and (body.on_ground or floating):
			body.vel.y = STEP_JUMP_SPEED
			body.use_gravity = true
		elif type == CharacterLibrary.RABBIT and body.on_ground:
			body.vel.y = HOP_SPEED
		yaw = lerp_angle(yaw, atan2(dir.x, dir.z), clampf(delta * 8.0, 0.0, 1.0))

	var before: Vector3 = body.pos
	body.step(world, props, delta)
	# Red de seguridad: si el centro quedó sobre un vacío, se deshace el avance horizontal.
	if not _has_floor(world, body.pos, is_duck):
		body.pos.x = before.x
		body.pos.z = before.z
		if state == State.WALK:
			_go_idle(rng)
	# Si chocó de costado contra algo (un bloque, un tronco), deja de empujar.
	if body.hit_wall and state == State.WALK and not jump:
		_go_idle(rng)
	rig.animate(delta, Vector2(body.vel.x, body.vel.z).length())
	_sync()


func _go_idle(rng: RandomNumberGenerator) -> void:
	state = State.IDLE
	_timer = rng.randf_range(1.0, 4.0)


func _within_leash(point: Vector3) -> bool:
	var offset := Vector2(point.x - home.x, point.z - home.z)
	var current := Vector2(body.pos.x - home.x, body.pos.z - home.z)
	# Siempre se permite volver hacia el punto de origen.
	return offset.length() <= LEASH or offset.length() < current.length()


## Elige un destino cercano dentro del radio permitido. El pato prefiere el agua.
func _pick_target(world: VoxelWorld, rng: RandomNumberGenerator, is_duck: bool) -> void:
	var best := Vector3.ZERO
	var found: bool = false
	for attempt: int in 6:
		var angle: float = rng.randf_range(0.0, TAU)
		var reach: float = rng.randf_range(1.5, 4.0)
		var candidate: Vector3 = body.pos + Vector3(cos(angle), 0.0, sin(angle)) * reach
		var offset := Vector2(candidate.x - home.x, candidate.z - home.z)
		if offset.length() > LEASH - 0.5:
			offset = offset.normalized() * (LEASH - 0.5)
			candidate = Vector3(home.x + offset.x, candidate.y, home.z + offset.y)
		if not found:
			best = candidate
			found = true
		if not is_duck:
			break
		var top: int = world.column_height(floori(candidate.x), floori(candidate.z))
		if top > 0 and world.get_block_xyz(floori(candidate.x), top - 1, floori(candidate.z)) == Blocks.WATER:
			best = candidate
			break
	_target = best
	state = State.WALK
	_timer = 6.0


## Al huir se prueba la dirección opuesta al jugador y, si está tapada, giros a los lados.
func _choose_flee_dir(world: VoxelWorld, is_duck: bool) -> Vector3:
	for turn: float in [0.0, 0.8, -0.8, 1.5, -1.5]:
		var candidate: Vector3 = _flee_dir.rotated(Vector3.UP, turn)
		if look_ahead(world, candidate, is_duck) != AHEAD_BLOCKED and _within_leash(body.pos + candidate * 0.6):
			return candidate
	return Vector3.ZERO


## Mira la columna de adelante: ¿se puede pasar, hay que subir un escalón o está cerrado?
func look_ahead(world: VoxelWorld, dir: Vector3, is_duck: bool) -> int:
	var probe: Vector3 = body.pos + dir * (body.half + 0.35)
	var x: int = floori(probe.x)
	var z: int = floori(probe.z)
	if x < 0 or z < 0 or x >= world.size_x or z >= world.size_z:
		return AHEAD_BLOCKED
	if x == floori(body.pos.x) and z == floori(body.pos.z):
		return AHEAD_OK
	var feet: int = floori(body.pos.y + 0.05)
	if Blocks.is_solid(world.get_block_xyz(x, feet + 1, z)):
		return AHEAD_BLOCKED
	var at_feet: int = world.get_block_xyz(x, feet, z)
	if Blocks.is_solid(at_feet):
		return AHEAD_STEP_UP
	if at_feet == Blocks.WATER:
		return AHEAD_OK if is_duck else AHEAD_BLOCKED
	# Piso al mismo nivel o un bloque más abajo; más que eso es una caída alta.
	for drop: int in [1, 2]:
		var below: int = world.get_block_xyz(x, feet - drop, z)
		if Blocks.is_solid(below):
			return AHEAD_OK
		if below == Blocks.WATER:
			return AHEAD_OK if is_duck else AHEAD_BLOCKED
	return AHEAD_BLOCKED


## ¿Hay piso (o agua, para el pato) a no más de un bloque por debajo de los pies?
static func _has_floor(world: VoxelWorld, point: Vector3, is_duck: bool) -> bool:
	var x: int = floori(point.x)
	var z: int = floori(point.z)
	var feet: int = floori(point.y + 0.05)
	for drop: int in [0, 1, 2]:
		var block: int = world.get_block_xyz(x, feet - drop, z)
		if Blocks.is_solid(block):
			return true
		if block == Blocks.WATER:
			return is_duck
	return false


## El pato flota: si hay agua a la altura de la panza, sube hasta la superficie y no cae.
## Devuelve true mientras está a flote.
func _duck_float(world: VoxelWorld, delta: float) -> bool:
	var x: int = floori(body.pos.x)
	var z: int = floori(body.pos.z)
	var y: int = floori(body.pos.y + 0.3)
	if world.get_block_xyz(x, y, z) != Blocks.WATER:
		body.use_gravity = true
		return false
	while world.get_block_xyz(x, y + 1, z) == Blocks.WATER:
		y += 1
	var surface: float = float(y + 1) - ChunkMesher.WATER_DROP
	body.use_gravity = false
	body.vel.y = clampf((surface - 0.22 - body.pos.y) * 6.0, -2.0, 2.0)
	if absf(body.vel.y) < 0.02 * delta:
		body.vel.y = 0.0
	return true
