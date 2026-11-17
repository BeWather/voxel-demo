class_name GridBody
extends RefCounted
## Cuerpo con colisión directa contra la grilla de voxeles (sin nodos de física).
## Es una caja alineada a los ejes; `pos` es el centro de la base (los pies).
## El movimiento se resuelve eje por eje: X, Z y por último Y.

const GRAVITY: float = 26.0
const WATER_GRAVITY_FACTOR: float = 0.25
const WATER_SINK_SPEED: float = 2.5
const MAX_STEP: float = 0.45
const EPSILON: float = 0.0005

var pos: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO
var half: float = 0.3
var height: float = 1.7
var on_ground: bool = false
var in_water: bool = false
var hit_wall: bool = false
## Si es false, el cuerpo no cae (lo usa el pato cuando flota).
var use_gravity: bool = true


func _init(p_half: float = 0.3, p_height: float = 1.7) -> void:
	half = p_half
	height = p_height


func teleport(new_pos: Vector3) -> void:
	pos = new_pos
	vel = Vector3.ZERO
	on_ground = false
	in_water = false
	hit_wall = false


## ¿El agua llega al cuerpo? Se mira un poco por debajo de la mitad de la altura.
static func water_at(world: VoxelWorld, point: Vector3) -> bool:
	return world.get_block_xyz(floori(point.x), floori(point.y), floori(point.z)) == Blocks.WATER


## Avanza la simulación `delta` segundos. `props` puede ser null.
func step(world: VoxelWorld, props: PropLayer, delta: float) -> void:
	in_water = water_at(world, pos + Vector3(0.0, height * 0.4, 0.0))
	if use_gravity:
		if in_water:
			vel.y = maxf(vel.y - GRAVITY * WATER_GRAVITY_FACTOR * delta, -WATER_SINK_SPEED)
		else:
			vel.y -= GRAVITY * delta
	var motion: Vector3 = vel * delta
	# Pasos cortos: un cuerpo rápido nunca atraviesa un voxel entero.
	var steps: int = maxi(1, ceili(maxf(absf(motion.x), maxf(absf(motion.y), absf(motion.z))) / MAX_STEP))
	motion /= float(steps)
	on_ground = false
	hit_wall = false
	for i: int in steps:
		_move_axis(world, props, 0, motion.x)
		_move_axis(world, props, 2, motion.z)
		_move_axis(world, props, 1, motion.y)


func _move_axis(world: VoxelWorld, props: PropLayer, axis: int, amount: float) -> void:
	if amount == 0.0:
		return
	pos[axis] += amount
	var boxes: Array[AABB] = overlapping(world, props)
	if boxes.is_empty():
		return
	for box: AABB in boxes:
		if axis == 1:
			if amount < 0.0:
				pos.y = maxf(pos.y, box.end.y)
				on_ground = true
			else:
				pos.y = minf(pos.y, box.position.y - height - EPSILON)
		elif amount > 0.0:
			pos[axis] = minf(pos[axis], box.position[axis] - half - EPSILON)
		else:
			pos[axis] = maxf(pos[axis], box.end[axis] + half + EPSILON)
	vel[axis] = 0.0
	if axis != 1:
		hit_wall = true


## Cajas sólidas (voxeles y props con colisión) que se superponen con el cuerpo.
func overlapping(world: VoxelWorld, props: PropLayer) -> Array[AABB]:
	var result: Array[AABB] = []
	var x0: int = floori(pos.x - half)
	var x1: int = floori(pos.x + half)
	var y0: int = floori(pos.y)
	var y1: int = floori(pos.y + height)
	var z0: int = floori(pos.z - half)
	var z1: int = floori(pos.z + half)
	for y: int in range(y0, y1 + 1):
		for z: int in range(z0, z1 + 1):
			for x: int in range(x0, x1 + 1):
				if Blocks.is_solid(world.get_block_xyz(x, y, z)):
					var box := AABB(Vector3(x, y, z), Vector3.ONE)
					if _touches(box):
						result.append(box)
	if props == null or props.props.is_empty():
		return result
	# Los troncos son más altos que una celda: se miran también las celdas de abajo.
	for y: int in range(y0 - 3, y1 + 1):
		for z: int in range(z0, z1 + 1):
			for x: int in range(x0, x1 + 1):
				var cell := Vector3i(x, y, z)
				if not props.props.has(cell):
					continue
				var id: int = props.props[cell]["id"]
				var r: float = prop_block_half(id)
				if r <= 0.0:
					continue
				var box := AABB(Vector3(x + 0.5 - r, y, z + 0.5 - r),
						Vector3(r * 2.0, PropLibrary.BLOCK_HEIGHT[id], r * 2.0))
				if _touches(box):
					result.append(box)
	return result


## Mitad del ancho de la caja de colisión de un prop (0 si no bloquea el paso).
## Los props que no están en la tabla (por ejemplo, los creados por el usuario) no bloquean.
static func prop_block_half(id: int) -> float:
	if id < 0 or id >= PropLibrary.BLOCK_HALF.size():
		return 0.0
	return PropLibrary.BLOCK_HALF[id]


## Superposición estricta: tocar una cara no cuenta.
func _touches(box: AABB) -> bool:
	return pos.x + half > box.position.x and pos.x - half < box.end.x \
			and pos.y + height > box.position.y and pos.y < box.end.y \
			and pos.z + half > box.position.z and pos.z - half < box.end.z
