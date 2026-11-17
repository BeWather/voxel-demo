class_name PropLayer
extends Node3D
## Props colocados en el mapa. Un prop por celda (la celda de aire sobre un bloque sólido).
## Se dibujan con un MultiMeshInstance3D por cada (región, prop, variante). Partir por
## regiones de REGION_SIZE celdas permite que el motor descarte las que no se ven y que
## una edición solo reescriba las instancias de su región.

## Lado de una región, en celdas. Un mapa S (64 x 64) es una sola región.
const REGION_SIZE: int = 64
const REGION_SHIFT: int = 6
## Las claves de grupo son clave_de_malla + región * REGION_STRIDE. En la región 0
## coinciden con la clave de malla.
const REGION_STRIDE: int = 1 << 40
const REGIONS_PER_ROW: int = 1 << 16
## Los props bajos (flores, pasto, hongos…) dejan de dibujarse cuando su región queda a
## más de esta distancia de la cámara: a esa distancia miden uno o dos píxeles.
const DETAIL_MAX_HEIGHT: float = 1.0
const DETAIL_RANGE: float = 170.0
const DETAIL_RANGE_MARGIN: float = 12.0
## Milisegundos por frame para reconstruir grupos cuando hay muchos pendientes.
const REBUILD_BUDGET_MSEC: int = 5

var library: PropLibrary
## Clave: celda. Valor: {"id": int, "variant": int, "rot": int (pasos de 90°)}.
var props: Dictionary[Vector3i, Dictionary] = {}

## Índice por grupo: clave de grupo -> conjunto de celdas.
var _by_mesh: Dictionary[int, Dictionary] = {}
var _instances: Dictionary[int, MultiMeshInstance3D] = {}
var _dirty: Dictionary[int, bool] = {}


func _process(_delta: float) -> void:
	if not _dirty.is_empty():
		rebuild_some(REBUILD_BUDGET_MSEC)


static func make_prop(id: int, variant: int, rot: int) -> Dictionary:
	return {"id": id, "variant": variant, "rot": posmod(rot, 4)}


static func mesh_key(data: Dictionary) -> int:
	var id: int = data["id"]
	var variant: int = data["variant"]
	return id * PropLibrary.MAX_VARIANTS + variant


## Región (x, z) a la que pertenece una celda.
static func region_of(cell: Vector3i) -> int:
	return (cell.x >> REGION_SHIFT) + (cell.z >> REGION_SHIFT) * REGIONS_PER_ROW


## Clave del grupo (región + malla) donde se dibuja un prop.
static func group_key(cell: Vector3i, data: Dictionary) -> int:
	return mesh_key(data) + region_of(cell) * REGION_STRIDE


## Transformación de un prop: centrado en la base de su celda y girado en pasos de 90°.
static func cell_transform(cell: Vector3i, rot: int) -> Transform3D:
	var turn := Basis(Vector3.UP, float(rot) * PI * 0.5)
	return Transform3D(turn, Vector3(cell.x + 0.5, cell.y, cell.z + 0.5))


func has_prop(cell: Vector3i) -> bool:
	return props.has(cell)


## Devuelve una copia de los datos del prop, o un diccionario vacío si no hay.
func get_prop(cell: Vector3i) -> Dictionary:
	if props.has(cell):
		return props[cell].duplicate()
	return {}


## Coloca o reemplaza el prop de una celda. Un diccionario vacío lo quita.
func set_prop(cell: Vector3i, data: Dictionary) -> void:
	if props.has(cell):
		var old_key: int = group_key(cell, props[cell])
		_by_mesh[old_key].erase(cell)
		_dirty[old_key] = true
		props.erase(cell)
	if data.is_empty():
		return
	var stored: Dictionary = data.duplicate()
	var key: int = group_key(cell, stored)
	props[cell] = stored
	if not _by_mesh.has(key):
		_by_mesh[key] = {}
	_by_mesh[key][cell] = true
	_dirty[key] = true


func clear() -> void:
	for key: int in _by_mesh:
		_dirty[key] = true
	props.clear()
	_by_mesh.clear()


## Marca para reconstruir todas las instancias de un prop (cuando cambia su modelo).
func refresh_prop(id: int) -> void:
	for key: int in _by_mesh:
		@warning_ignore("integer_division")
		if (key % REGION_STRIDE) / PropLibrary.MAX_VARIANTS == id:
			_dirty[key] = true


func dirty_count() -> int:
	return _dirty.size()


## Cantidad de grupos (región, prop, variante) que se están dibujando.
func group_count() -> int:
	return _instances.size()


## Reconstruye ya mismo todos los MultiMesh cuyas instancias cambiaron.
func rebuild_dirty() -> void:
	for key: int in _dirty:
		_rebuild(key)
	_dirty.clear()


## Reconstruye grupos pendientes hasta agotar `budget_msec` (al menos uno). Una edición
## toca uno o dos grupos y se resuelve en el mismo frame; una carga grande se reparte.
func rebuild_some(budget_msec: int) -> void:
	var start: int = Time.get_ticks_msec()
	var done: Array[int] = []
	for key: int in _dirty:
		_rebuild(key)
		done.append(key)
		if Time.get_ticks_msec() - start >= budget_msec:
			break
	for key: int in done:
		_dirty.erase(key)


func _rebuild(key: int) -> void:
	var cells: Dictionary = _by_mesh.get(key, {})
	if cells.is_empty():
		_by_mesh.erase(key)
		if _instances.has(key):
			_instances[key].queue_free()
			_instances.erase(key)
		return
	var mesh_id: int = key % REGION_STRIDE
	@warning_ignore("integer_division")
	var id: int = mesh_id / PropLibrary.MAX_VARIANTS
	var node: MultiMeshInstance3D
	if _instances.has(key):
		node = _instances[key]
	else:
		node = MultiMeshInstance3D.new()
		add_child(node)
		_instances[key] = node
	# El recorte por distancia se mide desde el centro de la región.
	@warning_ignore("integer_division")
	var region: int = key / REGION_STRIDE
	@warning_ignore("integer_division")
	var origin := Vector3(((region % REGIONS_PER_ROW) + 0.5) * REGION_SIZE, 0.0,
			((region / REGIONS_PER_ROW) + 0.5) * REGION_SIZE)
	node.position = origin
	if library.pick_height(id) < DETAIL_MAX_HEIGHT:
		node.visibility_range_end = DETAIL_RANGE
		node.visibility_range_end_margin = DETAIL_RANGE_MARGIN
	else:
		node.visibility_range_end = 0.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = library.get_mesh(id, mesh_id % PropLibrary.MAX_VARIANTS)
	mm.instance_count = cells.size()
	var i: int = 0
	for cell: Vector3i in cells:
		var rot: int = props[cell]["rot"]
		var xform: Transform3D = cell_transform(cell, rot)
		xform.origin -= origin
		mm.set_instance_transform(i, xform)
		i += 1
	node.multimesh = mm


## Busca el prop más cercano que cruza el rayo, hasta `max_distance`.
## Devuelve {"cell": Vector3i, "distance": float} o un diccionario vacío.
func pick(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = max_distance
	var dir: Vector3 = direction.normalized()
	# Primero se descartan las regiones que el rayo no cruza.
	var region_hit: Dictionary[int, bool] = {}
	for key: int in _by_mesh:
		@warning_ignore("integer_division")
		var region: int = key / REGION_STRIDE
		if not region_hit.has(region):
			@warning_ignore("integer_division")
			var corner := Vector3((region % REGIONS_PER_ROW) * REGION_SIZE - 2.0, -1.0,
					(region / REGIONS_PER_ROW) * REGION_SIZE - 2.0)
			var region_box := AABB(corner, Vector3(REGION_SIZE + 4.0, 80.0, REGION_SIZE + 4.0))
			region_hit[region] = region_box.has_point(origin) or region_box.intersects_ray(origin, dir) != null
		if not region_hit[region]:
			continue
		@warning_ignore("integer_division")
		var id: int = (key % REGION_STRIDE) / PropLibrary.MAX_VARIANTS
		var r: float = library.pick_radius(id)
		var height: float = library.pick_height(id)
		# Descarte rápido: distancia del centro del prop a la recta del rayo.
		var reach: float = r * 1.5 + height * 0.5 + 0.1
		var reach_sq: float = reach * reach
		var cells: Dictionary = _by_mesh[key]
		for cell: Vector3i in cells:
			var to_center := Vector3(cell.x + 0.5 - origin.x, cell.y + height * 0.5 - origin.y,
					cell.z + 0.5 - origin.z)
			var along: float = to_center.dot(dir)
			if along < -reach or along - reach > best_dist \
					or to_center.length_squared() - along * along > reach_sq:
				continue
			var box := AABB(Vector3(cell.x + 0.5 - r, cell.y, cell.z + 0.5 - r), Vector3(r * 2.0, height, r * 2.0))
			var point: Variant = box.intersects_ray(origin, dir)
			if point == null:
				continue
			var hit_point: Vector3 = point
			var dist: float = origin.distance_to(hit_point)
			if dist < best_dist:
				best_dist = dist
				best = {"cell": cell, "distance": dist}
	return best
