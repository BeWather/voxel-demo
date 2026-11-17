class_name ObjectModel
extends RefCounted
## Modelo mini-voxel en edición (una variante de un objeto): datos, deshacer/rehacer y raycast.
## Las coordenadas son mini-voxeles dentro del volumen de edición de PropLibrary; el origen es
## el centro de la base. Un trazo (begin_stroke ... end_stroke) es un paso de deshacer.

const MAX_HISTORY: int = 200

## Clave: PropLibrary.voxel_key. Valor: color del voxel.
var voxels: Dictionary[int, Color] = {}
## Sube con cada cambio de los datos; sirve para saber cuándo regenerar la malla.
var revision: int = 0

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
## Clave de voxel -> [valor anterior, valor nuevo]; null significa "vacío".
var _stroke: Dictionary[int, Array] = {}
var _stroke_open: bool = false


func _init(initial: Dictionary[int, Color] = {}) -> void:
	voxels = initial.duplicate()


static func in_bounds(cell: Vector3i) -> bool:
	return PropLibrary.in_volume(cell.x, cell.y, cell.z)


func has_voxel(cell: Vector3i) -> bool:
	return voxels.has(PropLibrary.voxel_key(cell.x, cell.y, cell.z))


## Color del voxel. Solo tiene sentido si has_voxel(cell).
func get_voxel(cell: Vector3i) -> Color:
	return voxels.get(PropLibrary.voxel_key(cell.x, cell.y, cell.z), Color.BLACK)


func count() -> int:
	return voxels.size()


## Coloca o repinta un voxel dentro del trazo actual. Devuelve true si hubo cambio.
func set_voxel(cell: Vector3i, color: Color) -> bool:
	if not in_bounds(cell):
		return false
	return _change(PropLibrary.voxel_key(cell.x, cell.y, cell.z), Color(color.r, color.g, color.b, 1.0))


func erase_voxel(cell: Vector3i) -> bool:
	if not in_bounds(cell):
		return false
	return _change(PropLibrary.voxel_key(cell.x, cell.y, cell.z), null)


## Colores usados en el modelo, del más al menos frecuente.
func used_colors() -> Array[Color]:
	var counts: Dictionary[Color, int] = {}
	for key: int in voxels:
		var color: Color = voxels[key]
		counts[color] = counts.get(color, 0) + 1
	var colors: Array[Color] = []
	colors.assign(counts.keys())
	colors.sort_custom(func(a: Color, b: Color) -> bool:
		if counts[a] != counts[b]:
			return counts[a] > counts[b]
		return a.to_rgba32() < b.to_rgba32())
	return colors


## Caja que ocupa el modelo, en mini-voxeles (tamaño cero si está vacío).
func bounds() -> AABB:
	if voxels.is_empty():
		return AABB()
	var lo := Vector3i(999, 999, 999)
	var hi := Vector3i(-999, -999, -999)
	for key: int in voxels:
		var cell: Vector3i = PropLibrary.voxel_cell(key)
		lo = lo.min(cell)
		hi = hi.max(cell)
	return AABB(Vector3(lo), Vector3(hi - lo + Vector3i.ONE))


# ================================================================ historial

func begin_stroke() -> void:
	if _stroke_open:
		end_stroke()
	_stroke = {}
	_stroke_open = true


## Cierra el trazo y lo guarda como un único paso de deshacer (si cambió algo).
## Devuelve true si se agregó un paso.
func end_stroke() -> bool:
	if not _stroke_open:
		return false
	_stroke_open = false
	var changes: Dictionary[int, Array] = {}
	for key: int in _stroke:
		var entry: Array = _stroke[key]
		if entry[0] != entry[1]:
			changes[key] = entry
	_stroke = {}
	if changes.is_empty():
		return false
	_undo.append(changes)
	if _undo.size() > MAX_HISTORY:
		_undo.pop_front()
	_redo.clear()
	return true


func is_stroke_open() -> bool:
	return _stroke_open


## ¿El trazo abierto ya tocó este voxel? (para que un arrastre no apile sobre lo recién puesto).
func stroke_touched(cell: Vector3i) -> bool:
	return _stroke.has(PropLibrary.voxel_key(cell.x, cell.y, cell.z))


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> bool:
	if _stroke_open or _undo.is_empty():
		return false
	var step: Dictionary = _undo.pop_back()
	_restore(step, 0)
	_redo.append(step)
	return true


func redo() -> bool:
	if _stroke_open or _redo.is_empty():
		return false
	var step: Dictionary = _redo.pop_back()
	_restore(step, 1)
	_undo.append(step)
	return true


func clear_history() -> void:
	_undo.clear()
	_redo.clear()
	_stroke = {}
	_stroke_open = false


func _change(key: int, value: Variant) -> bool:
	var old: Variant = voxels.get(key)
	if old == value:
		return false
	var single: bool = not _stroke_open
	if single:
		begin_stroke()
	if _stroke.has(key):
		_stroke[key][1] = value
	else:
		_stroke[key] = [old, value]
	_write(key, value)
	if single:
		end_stroke()
	return true


func _write(key: int, value: Variant) -> void:
	if value == null:
		voxels.erase(key)
	else:
		var color: Color = value
		voxels[key] = color
	revision += 1


## Aplica el lado `side` de un paso (0 = estado anterior, 1 = estado nuevo) sin registrar nada.
func _restore(step: Dictionary, side: int) -> void:
	for key: int in step:
		var entry: Array = step[key]
		_write(key, entry[side])


# ================================================================ raycast

## Raycast voxel (DDA de Amanatides-Woo) dentro del volumen de edición. No usa física.
## `origin` y `direction` van en mini-voxeles. Devuelve:
##   hit: bool         el rayo tocó un voxel.
##   cell: Vector3i    voxel tocado, o la celda del piso (y = 0) si `floor` es true.
##   normal: Vector3i  cara por la que entra el rayo (hacia arriba en el piso).
##   floor: bool       no tocó ningún voxel pero sí la cuadrícula del piso.
##   distance: float
func raycast(origin: Vector3, direction: Vector3, max_distance: float = 2000.0) -> Dictionary:
	var result: Dictionary = {
		"hit": false, "cell": Vector3i.ZERO, "normal": Vector3i.ZERO, "floor": false, "distance": 0.0,
	}
	if direction.length_squared() < 1e-12:
		return result
	var dir: Vector3 = direction.normalized()
	var bmin := Vector3(PropLibrary.MIN_XZ, 0.0, PropLibrary.MIN_XZ)
	var bmax := Vector3(PropLibrary.MAX_XZ + 1, PropLibrary.MAX_Y + 1, PropLibrary.MAX_XZ + 1)

	# Punto donde el rayo cruza el piso (y = 0): es el resultado si no toca ningún voxel.
	if dir.y < -1e-9 and origin.y > 0.0:
		var t_floor: float = -origin.y / dir.y
		var p: Vector3 = origin + dir * t_floor
		if t_floor <= max_distance and p.x >= bmin.x and p.x < bmax.x and p.z >= bmin.z and p.z < bmax.z:
			result["floor"] = true
			result["cell"] = Vector3i(floori(p.x), 0, floori(p.z))
			result["normal"] = Vector3i.UP
			result["distance"] = t_floor

	# Recorte contra la caja del volumen.
	var t_enter: float = 0.0
	var t_exit: float = max_distance
	var normal := Vector3i.ZERO
	for a: int in 3:
		if absf(dir[a]) < 1e-9:
			if origin[a] < bmin[a] or origin[a] >= bmax[a]:
				return result
			continue
		var t1: float = (bmin[a] - origin[a]) / dir[a]
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
	var lo := Vector3i(PropLibrary.MIN_XZ, 0, PropLibrary.MIN_XZ)
	var hi := Vector3i(PropLibrary.MAX_XZ, PropLibrary.MAX_Y, PropLibrary.MAX_XZ)
	var probe: Vector3 = start + dir * 1e-4
	var cell: Vector3i = Vector3i(floori(probe.x), floori(probe.y), floori(probe.z)).clamp(lo, hi)

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
		if voxels.has(PropLibrary.voxel_key(cell.x, cell.y, cell.z)):
			result["hit"] = true
			result["floor"] = false
			result["cell"] = cell
			result["normal"] = normal
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
