class_name VoxelWorld
extends Node3D
## Datos del mundo en chunks de 16x16x16, mallas por chunk y raycast voxel.

const CHUNK_SIZE: int = 16
const CHUNK_VOLUME: int = 4096

var size_x: int = 64
var size_y: int = 32
var size_z: int = 64

## Clave: coordenada de chunk. Valor: 4096 bytes, índice x | z << 4 | y << 8.
var chunks: Dictionary[Vector3i, PackedByteArray] = {}
## Cantidad de chunks regenerados en la última pasada (para diagnóstico y pruebas).
var last_remesh_count: int = 0

## Milisegundos por frame dedicados a las mallas pendientes de una carga grande.
var slice_budget_msec: int = 10

var _nodes: Dictionary[Vector3i, MeshInstance3D] = {}
## Chunks tocados por ediciones: se regeneran todos en el mismo frame.
var _dirty: Dictionary[Vector3i, bool] = {}
## Chunks de una generación o carga: se regeneran de a pocos por frame.
var _pending: Dictionary[Vector3i, bool] = {}
var _pending_total: int = 0
var _mesher: ChunkMesher = ChunkMesher.new()


func _process(_delta: float) -> void:
	# Los chunks sucios se regeneran una vez por frame, no una vez por edición.
	if not _dirty.is_empty():
		_remesh_edits()
	if not _pending.is_empty():
		remesh_pending(slice_budget_msec)


func in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 \
			and cell.x < size_x and cell.y < size_y and cell.z < size_z


func get_block(cell: Vector3i) -> int:
	return get_block_xyz(cell.x, cell.y, cell.z)


func get_block_xyz(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= size_x or y >= size_y or z >= size_z:
		return Blocks.AIR
	var key := Vector3i(x >> 4, y >> 4, z >> 4)
	if not chunks.has(key):
		return Blocks.AIR
	var data: PackedByteArray = chunks[key]
	return data[(x & 15) | ((z & 15) << 4) | ((y & 15) << 8)]


## Igual que get_block_xyz, pero debajo del mundo devuelve un sólido ficticio
## para que el mallador no dibuje la cara inferior del mapa.
func get_block_padded(x: int, y: int, z: int) -> int:
	if y < 0:
		return ChunkMesher.BEDROCK
	return get_block_xyz(x, y, z)


## Cambia un voxel y marca los chunks afectados. Devuelve true si hubo cambio.
func set_block(cell: Vector3i, id: int) -> bool:
	if not in_bounds(cell):
		return false
	if not _write(cell.x, cell.y, cell.z, id):
		return false
	# La oclusión ambiental depende de los vecinos en diagonal, así que se marcan
	# todos los chunks que tocan el entorno 3x3x3 del voxel (normalmente uno solo).
	var cx0: int = maxi(cell.x - 1, 0) >> 4
	var cx1: int = mini(cell.x + 1, size_x - 1) >> 4
	var cy0: int = maxi(cell.y - 1, 0) >> 4
	var cy1: int = mini(cell.y + 1, size_y - 1) >> 4
	var cz0: int = maxi(cell.z - 1, 0) >> 4
	var cz1: int = mini(cell.z + 1, size_z - 1) >> 4
	for cy: int in range(cy0, cy1 + 1):
		for cz: int in range(cz0, cz1 + 1):
			for cx: int in range(cx0, cx1 + 1):
				_dirty[Vector3i(cx, cy, cz)] = true
	return true


## Escritura masiva sin marcar chunks (usar mark_all_dirty al terminar).
func set_block_raw(x: int, y: int, z: int, id: int) -> void:
	if x < 0 or y < 0 or z < 0 or x >= size_x or y >= size_y or z >= size_z:
		return
	_write(x, y, z, id)


func _write(x: int, y: int, z: int, id: int) -> bool:
	var key := Vector3i(x >> 4, y >> 4, z >> 4)
	var index: int = (x & 15) | ((z & 15) << 4) | ((y & 15) << 8)
	var data: PackedByteArray
	if chunks.has(key):
		data = chunks[key]
		if data[index] == id:
			return false
	else:
		if id == Blocks.AIR:
			return false
		data = PackedByteArray()
		data.resize(CHUNK_VOLUME)
		data.fill(0)
	data[index] = id
	chunks[key] = data
	return true


## Altura de la columna: y de la primera celda de aire sobre el bloque más alto.
func column_height(x: int, z: int) -> int:
	for y: int in range(size_y - 1, -1, -1):
		if get_block_xyz(x, y, z) != Blocks.AIR:
			return y + 1
	return 0


## Vacía el mundo (opcionalmente cambiando su tamaño) y libera las mallas.
func clear(new_size: Vector3i = Vector3i.ZERO) -> void:
	if new_size != Vector3i.ZERO:
		size_x = new_size.x
		size_y = new_size.y
		size_z = new_size.z
	chunks.clear()
	_dirty.clear()
	_pending.clear()
	_pending_total = 0
	for key: Vector3i in _nodes:
		_nodes[key].queue_free()
	_nodes.clear()


## Reemplaza todo el contenido del mundo (usado al cargar un mapa).
## Las mallas quedan pendientes y se arman de a pocas por frame.
func replace_all(new_size: Vector3i, new_chunks: Dictionary[Vector3i, PackedByteArray]) -> void:
	clear(new_size)
	chunks = new_chunks
	mark_all_dirty(true)


## Marca todos los chunks para regenerar. Con `sliced`, el trabajo se reparte en varios
## frames (carga o generación de un mapa); sin él, se hace todo en el próximo frame.
func mark_all_dirty(sliced: bool = false) -> void:
	for key: Vector3i in chunks:
		if sliced:
			_pending[key] = true
		else:
			_dirty[key] = true
	if sliced:
		_pending_total = _pending.size()


## Chunks marcados por ediciones (no cuenta los pendientes de una carga).
func dirty_count() -> int:
	return _dirty.size()


## Chunks de una carga o generación que todavía no tienen su malla.
func pending_count() -> int:
	return _pending.size()


## Avance (0 a 1) del armado de mallas de la última carga o generación.
func pending_progress() -> float:
	if _pending_total <= 0:
		return 1.0
	return 1.0 - float(_pending.size()) / float(_pending_total)


func is_chunk_dirty(key: Vector3i) -> bool:
	return _dirty.has(key)


## Regenera ya mismo todas las mallas marcadas, incluidas las pendientes de una carga.
## Devuelve cuántas se regeneraron.
func remesh_dirty() -> int:
	for key: Vector3i in _pending:
		_dirty[key] = true
	_pending.clear()
	return _remesh_edits()


func _remesh_edits() -> int:
	var count: int = 0
	for key: Vector3i in _dirty:
		_remesh_chunk(key)
		_pending.erase(key)
		count += 1
	_dirty.clear()
	last_remesh_count = count
	return count


## Regenera mallas pendientes hasta agotar `budget_msec` (al menos una).
## Devuelve cuántas quedan.
func remesh_pending(budget_msec: int) -> int:
	var start: int = Time.get_ticks_msec()
	var done: Array[Vector3i] = []
	for key: Vector3i in _pending:
		_remesh_chunk(key)
		done.append(key)
		if Time.get_ticks_msec() - start >= budget_msec:
			break
	for key: Vector3i in done:
		_pending.erase(key)
	return _pending.size()


func _remesh_chunk(key: Vector3i) -> void:
	var mesh: ArrayMesh = _mesher.build(self, key)
	if mesh == null:
		if _nodes.has(key):
			_nodes[key].queue_free()
			_nodes.erase(key)
		return
	var node: MeshInstance3D
	if _nodes.has(key):
		node = _nodes[key]
	else:
		node = MeshInstance3D.new()
		node.position = Vector3(key * CHUNK_SIZE)
		add_child(node)
		_nodes[key] = node
	node.mesh = mesh


func get_chunk_mesh(key: Vector3i) -> ArrayMesh:
	if _nodes.has(key):
		return _nodes[key].mesh as ArrayMesh
	return null


## Raycast voxel (DDA de Amanatides-Woo). No usa física.
## Con `skip_water` el agua no detiene el rayo.
## Devuelve {hit, cell, normal, block, distance}. La normal es la cara por la que entra el rayo.
func raycast(origin: Vector3, direction: Vector3, max_distance: float = 500.0,
		skip_water: bool = false) -> Dictionary:
	var result: Dictionary = {
		"hit": false, "cell": Vector3i.ZERO, "normal": Vector3i.ZERO,
		"block": Blocks.AIR, "distance": 0.0,
	}
	if direction.length_squared() < 1e-12:
		return result
	var dir: Vector3 = direction.normalized()
	var bmax := Vector3(size_x, size_y, size_z)

	# Recorte contra la caja del mundo.
	var t_enter: float = 0.0
	var t_exit: float = max_distance
	var normal := Vector3i.ZERO
	for a: int in 3:
		if absf(dir[a]) < 1e-9:
			if origin[a] < 0.0 or origin[a] >= bmax[a]:
				return result
			continue
		var t1: float = (0.0 - origin[a]) / dir[a]
		var t2: float = (bmax[a] - origin[a]) / dir[a]
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
		if t1 > t_enter:
			t_enter = t1
			normal = Vector3i.ZERO
			normal[a] = -1 if dir[a] > 0.0 else 1
		if t2 < t_exit:
			t_exit = t2
	if t_enter > t_exit:
		return result

	var start: Vector3 = origin + dir * t_enter
	var limit := Vector3i(size_x - 1, size_y - 1, size_z - 1)
	var probe: Vector3 = start + dir * 1e-4
	var cell: Vector3i = Vector3i(floori(probe.x), floori(probe.y), floori(probe.z)).clamp(Vector3i.ZERO, limit)

	var step := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for a: int in 3:
		if dir[a] > 1e-9:
			step[a] = 1
			t_delta[a] = 1.0 / dir[a]
			t_max[a] = t_enter + (float(cell[a] + 1) - start[a]) / dir[a]
		elif dir[a] < -1e-9:
			step[a] = -1
			t_delta[a] = -1.0 / dir[a]
			t_max[a] = t_enter + (float(cell[a]) - start[a]) / dir[a]

	var t: float = t_enter
	while true:
		var id: int = get_block_xyz(cell.x, cell.y, cell.z)
		if id != Blocks.AIR and not (skip_water and id == Blocks.WATER):
			result["hit"] = true
			result["cell"] = cell
			result["normal"] = normal
			result["block"] = id
			result["distance"] = t
			return result
		var axis: int = 0
		if t_max.y < t_max.x:
			axis = 1
		if t_max.z < t_max[axis]:
			axis = 2
		t = t_max[axis]
		if t > t_exit + 1e-3:
			return result
		cell[axis] += step[axis]
		if not in_bounds(cell):
			return result
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
		t_max[axis] += t_delta[axis]
	return result
