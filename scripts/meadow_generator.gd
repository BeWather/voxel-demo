class_name MeadowGenerator
extends RefCounted
## Genera una pradera: lomas suaves, capas piedra/tierra/pasto, estanques y vegetación.
##
## El trabajo se hace por etapas y por filas para poder repartirlo en varios frames:
## se crea un generador y se llama a step() hasta que devuelve true. generate() hace
## todo de una vez. El resultado depende solo de la semilla y del tamaño del mundo,
## no de cómo se reparta el trabajo.

enum Phase { HEIGHTS, POND_SEARCH, PONDS, COLUMNS, PROPS, FREE_CELLS, ENTITIES, DONE }

const BASE_HEIGHT: float = 7.0
const HILL_AMPLITUDE: float = 5.0
const MIN_HEIGHT: int = 4
const MAX_HEIGHT: int = 10
## Tamaño de referencia (64 x 64): las cantidades escalan respecto de esta área.
const REFERENCE_AREA: float = 4096.0
## Los estanques se buscan uno por región de este tamaño y se separan al menos POND_SPACING.
const POND_REGION: int = 32
const POND_SPACING: float = 36.0
const MAX_DUCK_GROUPS: int = 4
const MAX_ANIMAL_REPEATS: int = 4
## Dónde van los aldeanos, como fracción del mapa (el primero, en el centro).
const VILLAGER_SPOTS: Array[Vector2] = [
	Vector2(0.5, 0.5), Vector2(0.25, 0.3), Vector2(0.75, 0.7),
	Vector2(0.28, 0.75), Vector2(0.72, 0.25), Vector2(0.5, 0.15),
]
## Grupos de animales (tipo, cantidad) para un mapa del tamaño de referencia.
const ANIMAL_GROUPS: Array[Vector2i] = [
	Vector2i(CharacterLibrary.SHEEP, 4), Vector2i(CharacterLibrary.SHEEP, 3),
	Vector2i(CharacterLibrary.COW, 3), Vector2i(CharacterLibrary.PIG, 3),
	Vector2i(CharacterLibrary.CHICKEN, 4), Vector2i(CharacterLibrary.RABBIT, 3),
	Vector2i(CharacterLibrary.RABBIT, 2), Vector2i(CharacterLibrary.FOX, 1),
]

var world: VoxelWorld
var props: PropLayer
var entities: EntityLayer
var map_seed: int = 0
var phase: int = Phase.HEIGHTS
## Centros de los estanques (x, z), disponibles después de la etapa PONDS.
var ponds: Array[Vector2i] = []

var _sx: int = 0
var _sz: int = 0
var _row: int = 0
var _top_limit: int = MAX_HEIGHT
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _hills: FastNoiseLite
var _detail: FastNoiseLite
var _forest: FastNoiseLite
var _patches: FastNoiseLite
var _raw: PackedFloat32Array = PackedFloat32Array()
var _heights: PackedInt32Array = PackedInt32Array()
var _is_sand: PackedByteArray = PackedByteArray()
var _is_water: PackedByteArray = PackedByteArray()
var _water_top: PackedInt32Array = PackedInt32Array()
var _trees: Dictionary[Vector2i, bool] = {}
var _pond_margin: int = 0
var _pond_candidates: Array[Vector3] = []
# Celdas libres para criaturas: pasto seco sin prop y arena seca de la orilla.
var _grass: Array[Vector3i] = []
var _grass_y: Dictionary[Vector2i, int] = {}
var _shore_y: Dictionary[Vector2i, int] = {}
var _shore_by_pond: Array[Array] = []


## Genera todo de una vez. `entities` es opcional: si se pasa, también se reparten
## animales y aldeanos.
static func generate(p_world: VoxelWorld, p_props: PropLayer, p_seed: int,
		p_entities: EntityLayer = null) -> void:
	var job := MeadowGenerator.new(p_world, p_props, p_seed, p_entities)
	while not job.step(0):
		pass


## Cantidad de estanques para un mapa de sx por sz: 1 en S, 3 en M y 8 en L.
static func pond_count(sx: int, sz: int) -> int:
	return maxi(1, roundi(pow(float(sx * sz) / REFERENCE_AREA, 0.75)))


## Cantidad de aldeanos: 1 en S, 3 en M y 6 en L.
static func villager_count(sx: int, sz: int) -> int:
	var scale: float = sqrt(float(sx * sz) / REFERENCE_AREA)
	return clampi(roundi(scale * 1.5 - 0.5), 1, VILLAGER_SPOTS.size())


## Cuántas veces se repite la lista de grupos de animales: 1 en S, 2 en M y 4 en L.
## Los animales crecen con el lado del mapa y no con el área, y tienen tope.
static func animal_repeats(sx: int, sz: int) -> int:
	return clampi(roundi(sqrt(float(sx * sz) / REFERENCE_AREA)), 1, MAX_ANIMAL_REPEATS)


## Cuántos unicornios (o dragones) lleva un mapa: en S, uno si hay suerte; uno en M y dos en L.
static func rare_count(sx: int, sz: int, lucky: bool) -> int:
	var repeats: int = animal_repeats(sx, sz)
	if repeats <= 1:
		return 1 if lucky else 0
	@warning_ignore("integer_division")
	return repeats / 2


## Vacía el mundo y deja todo listo para llamar a step().
func _init(p_world: VoxelWorld, p_props: PropLayer, p_seed: int, p_entities: EntityLayer = null) -> void:
	world = p_world
	props = p_props
	entities = p_entities
	map_seed = p_seed
	world.clear()
	props.clear()
	if entities != null:
		entities.clear()
	_sx = world.size_x
	_sz = world.size_z
	_top_limit = mini(MAX_HEIGHT, world.size_y - 6)
	_rng.seed = map_seed

	# La frecuencia del ruido no depende del tamaño: un mapa L es una pradera más
	# grande, no la misma pradera estirada.
	_hills = _make_noise(map_seed, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.022)
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = 3
	_detail = _make_noise(map_seed + 101, FastNoiseLite.TYPE_SIMPLEX, 0.12)
	_forest = _make_noise(map_seed + 202, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.045)
	_patches = _make_noise(map_seed + 303, FastNoiseLite.TYPE_SIMPLEX, 0.09)

	var area: int = _sx * _sz
	_raw.resize(area)
	_heights.resize(area)
	_is_sand.resize(area)
	_is_sand.fill(0)
	_is_water.resize(area)
	_is_water.fill(0)
	_water_top.resize(area)
	_water_top.fill(0)


static func _make_noise(noise_seed: int, type: FastNoiseLite.NoiseType, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = type
	noise.frequency = frequency
	return noise


## Avance entre 0 y 1.
func progress() -> float:
	var rows: float = float(_row) / float(maxi(_sz, 1))
	match phase:
		Phase.HEIGHTS:
			return 0.15 * rows
		Phase.POND_SEARCH, Phase.PONDS:
			return 0.15
		Phase.COLUMNS:
			return 0.17 + 0.48 * rows
		Phase.PROPS:
			return 0.65 + 0.28 * rows
		Phase.FREE_CELLS:
			return 0.93 + 0.05 * rows
		Phase.ENTITIES:
			return 0.98
		_:
			return 1.0


## Trabaja hasta agotar `budget_msec` milisegundos (0 = sin límite: hace todo lo que
## falta). Devuelve true cuando la pradera está completa.
func step(budget_msec: int) -> bool:
	var start: int = Time.get_ticks_msec()
	while phase != Phase.DONE:
		match phase:
			Phase.HEIGHTS:
				_heights_row(_row)
				_advance_row(Phase.POND_SEARCH)
				if phase == Phase.POND_SEARCH:
					@warning_ignore("integer_division")
					_pond_margin = mini(11, mini(_sx, _sz) / 4)
					_row = _pond_margin
			Phase.POND_SEARCH:
				_pond_search_row(_row)
				_row += POND_REGION
				if _row >= _sz - _pond_margin:
					_row = 0
					phase = Phase.PONDS
			Phase.PONDS:
				_make_ponds()
				phase = Phase.COLUMNS
			Phase.COLUMNS:
				_columns_row(_row)
				_advance_row(Phase.PROPS)
				if phase == Phase.PROPS:
					# Los bloques ya están: las mallas se pueden ir armando por partes.
					world.mark_all_dirty(true)
			Phase.PROPS:
				_props_row(_row)
				_advance_row(Phase.FREE_CELLS if entities != null else Phase.DONE)
				if phase == Phase.FREE_CELLS:
					for pond: Vector2i in ponds:
						_shore_by_pond.append([])
			Phase.FREE_CELLS:
				_free_cells_row(_row)
				_advance_row(Phase.ENTITIES)
			Phase.ENTITIES:
				_scatter_entities()
				phase = Phase.DONE
		if budget_msec > 0 and Time.get_ticks_msec() - start >= budget_msec:
			break
	return phase == Phase.DONE


func _advance_row(next_phase: int) -> void:
	_row += 1
	if _row >= _sz:
		_row = 0
		phase = next_phase


# ---------------------------------------------------------------- etapas

## 1. Mapa de alturas.
func _heights_row(z: int) -> void:
	for x: int in _sx:
		var h: float = BASE_HEIGHT + _hills.get_noise_2d(x, z) * HILL_AMPLITUDE
		_raw[x + z * _sx] = h
		_heights[x + z * _sx] = clampi(roundi(h), MIN_HEIGHT, _top_limit)


## 2. Estanques en las cuencas más bajas, lejos del borde y separados entre sí.
## Una fila de regiones: el punto más bajo de cada una es candidato a estanque
## (promedio en cruz para ignorar pozos de una sola celda).
func _pond_search_row(rz: int) -> void:
	var margin: int = _pond_margin
	for rx: int in range(margin, _sx - margin, POND_REGION):
		var best := Vector2i(-1, -1)
		var lowest: float = INF
		for z: int in range(rz, mini(rz + POND_REGION, _sz - margin)):
			for x: int in range(rx, mini(rx + POND_REGION, _sx - margin)):
				var avg: float = (_raw[x + z * _sx] + _raw[x - 2 + z * _sx] + _raw[x + 2 + z * _sx]
						+ _raw[x + (z - 2) * _sx] + _raw[x + (z + 2) * _sx]) / 5.0
				if avg < lowest:
					lowest = avg
					best = Vector2i(x, z)
		if best.x >= 0:
			_pond_candidates.append(Vector3(best.x, lowest, best.y))


func _make_ponds() -> void:
	_pond_candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	var wanted: int = pond_count(_sx, _sz)
	for candidate: Vector3 in _pond_candidates:
		if ponds.size() >= wanted:
			break
		var spot := Vector2i(roundi(candidate.x), roundi(candidate.z))
		var crowded: bool = false
		for other: Vector2i in ponds:
			if Vector2(spot - other).length() < POND_SPACING:
				crowded = true
		if not crowded:
			ponds.append(spot)
	if ponds.is_empty():
		ponds.append(Vector2i(_sx >> 1, _sz >> 1))
	for pond: Vector2i in ponds:
		_carve_pond(pond, _rng.randf_range(7.0, 9.0))


func _carve_pond(pond: Vector2i, radius: float) -> void:
	# water_y: y del voxel de agua más alto. Nivel fijo para todo el estanque.
	var water_y: int = maxi(_heights[pond.x + pond.y * _sx] - 1, 2)
	var reach: int = ceili(radius * 1.22 * 2.4) + 1
	for z: int in range(maxi(pond.y - reach, 0), mini(pond.y + reach + 1, _sz)):
		for x: int in range(maxi(pond.x - reach, 0), mini(pond.x + reach + 1, _sx)):
			var i: int = x + z * _sx
			# Las celdas de otro estanque (lecho u orilla) no se tocan.
			if _is_sand[i] == 1:
				continue
			var wobble: float = 1.0 + 0.22 * _detail.get_noise_2d(x, z)
			var d: float = Vector2(x - pond.x, z - pond.y).length() / (radius * wobble)
			if d < 1.0:
				# Lecho: más profundo hacia el centro.
				_heights[i] = maxi(water_y - roundi(2.3 * (1.0 - d * d)), 1)
				_is_water[i] = 1
				_is_sand[i] = 1
				_water_top[i] = water_y
			elif d < 1.5:
				# Orilla: nunca por debajo del agua y con pendiente suave.
				_heights[i] = clampi(_heights[i], water_y + 1, water_y + 1 + int((d - 1.0) * 6.0))
				_is_sand[i] = 1
			elif d < 2.4:
				# Transición: limita la pendiente para no dejar paredes alrededor del estanque.
				_heights[i] = clampi(_heights[i], water_y + 1, water_y + 4 + int((d - 1.5) * 7.0))


## 3. Columnas de bloques.
func _columns_row(z: int) -> void:
	for x: int in _sx:
		var i: int = x + z * _sx
		var h: int = _heights[i]
		for y: int in h:
			var id: int = Blocks.STONE
			if _is_sand[i] == 1 and y >= h - 2:
				id = Blocks.SAND
			elif y == h - 1:
				id = Blocks.GRASS
			elif y >= h - 3:
				id = Blocks.DIRT
			world.set_block_raw(x, y, z, id)
		if _is_water[i] == 1:
			for y: int in range(h, _water_top[i] + 1):
				world.set_block_raw(x, y, z, Blocks.WATER)


## 4. Vegetación: árboles escasos y agrupados, plantas chicas más frecuentes.
func _props_row(z: int) -> void:
	for x: int in _sx:
		var i: int = x + z * _sx
		if _is_sand[i] == 1 or _is_water[i] == 1:
			continue
		var h: int = _heights[i]
		var cell := Vector3i(x, h, z)
		if not world.in_bounds(cell):
			continue
		var roll: float = _rng.randf()
		var grove: float = _forest.get_noise_2d(x, z)
		var tree_chance: float = 0.004 + maxf(grove - 0.12, 0.0) * 0.30
		var id: int = -1
		if roll < tree_chance:
			if x < 1 or z < 1 or x >= _sx - 1 or z >= _sz - 1 or _tree_nearby(x, z):
				continue
			_trees[Vector2i(x, z)] = true
			var pine_chance: float = 0.75 if h >= 8 else 0.2
			id = PropLibrary.PINE if _rng.randf() < pine_chance else PropLibrary.OAK
		else:
			roll = _rng.randf()
			var patch: float = _patches.get_noise_2d(x, z)
			if roll < 0.10:
				id = PropLibrary.TALL_GRASS
			elif roll < 0.135:
				# El color de las flores cambia por manchones.
				if patch > 0.25:
					id = PropLibrary.FLOWER_RED
				elif patch < -0.25:
					id = PropLibrary.FLOWER_BLUE
				else:
					id = PropLibrary.FLOWER_YELLOW
			elif roll < 0.147:
				id = PropLibrary.BUSH
			elif roll < 0.155:
				id = PropLibrary.ROCK
			elif roll < 0.160 + maxf(grove, 0.0) * 0.02:
				id = PropLibrary.MUSHROOM
			elif roll < 0.1635 + maxf(grove, 0.0) * 0.02:
				id = PropLibrary.LOG
		if id >= 0:
			props.set_prop(cell, PropLayer.make_prop(id, _rng.randi_range(0, props.library.variant_count(id) - 1),
					_rng.randi_range(0, 3)))


func _tree_nearby(x: int, z: int) -> bool:
	for dz: int in range(-2, 3):
		for dx: int in range(-2, 3):
			if _trees.has(Vector2i(x + dx, z + dz)):
				return true
	return false


## 5. Criaturas: aldeanos repartidos, grupos chicos de la misma especie y patos junto
## a los estanques. Las cantidades crecen con el tamaño del mapa, con tope.
func _free_cells_row(z: int) -> void:
	if z < 2 or z >= _sz - 2:
		return
	for x: int in range(2, _sx - 2):
		var i: int = x + z * _sx
		var cell := Vector3i(x, _heights[i], z)
		if _is_water[i] == 1 or props.has_prop(cell) or not world.in_bounds(cell):
			continue
		if _is_sand[i] == 1:
			for p: int in ponds.size():
				if Vector2(x - ponds[p].x, z - ponds[p].y).length() < 13.0:
					_shore_by_pond[p].append(cell)
					_shore_y[Vector2i(x, z)] = cell.y
					break
		else:
			_grass.append(cell)
			_grass_y[Vector2i(x, z)] = cell.y


func _scatter_entities() -> void:
	var grass: Array[Vector3i] = _grass
	var grass_y: Dictionary[Vector2i, int] = _grass_y
	var shore_y: Dictionary[Vector2i, int] = _shore_y
	var shore_by_pond: Array[Array] = _shore_by_pond
	if grass.is_empty():
		return

	# Aldeanos: la celda de pasto libre más cercana a cada punto elegido.
	for spot: int in villager_count(_sx, _sz):
		var anchor := Vector2i(roundi(VILLAGER_SPOTS[spot].x * _sx), roundi(VILLAGER_SPOTS[spot].y * _sz))
		var npc_cell: Vector3i = _nearest_free(grass_y, anchor)
		if npc_cell.x < 0 or entities.has_entity(npc_cell):
			continue
		var npc_variant: int = _rng.randi_range(0, CharacterLibrary.VILLAGER_VARIANTS - 1)
		var npc_rot: int = _rng.randi_range(0, 3)
		entities.set_entity(npc_cell, EntityLayer.make_entity(CharacterLibrary.VILLAGER, npc_variant, npc_rot,
				CharacterLibrary.default_npc_name(npc_variant, _rng.randi_range(0, 99)),
				CharacterLibrary.DEFAULT_NPC_LINES))

	for repeat: int in animal_repeats(_sx, _sz):
		for group: Vector2i in ANIMAL_GROUPS:
			var anchor: Vector3i = grass[_rng.randi_range(0, grass.size() - 1)]
			_place_group(grass_y, anchor, group.x, group.y, 3)
	for p: int in mini(ponds.size(), MAX_DUCK_GROUPS):
		var shore: Array = shore_by_pond[p]
		if shore.is_empty():
			continue
		var duck_anchor: Vector3i = shore[_rng.randi_range(0, shore.size() - 1)]
		_place_group(shore_y, duck_anchor, CharacterLibrary.DUCK, 4, 5)

	# Ponis de vez en cuando, en grupos chicos. Unicornios y dragones son raros: en un
	# mapa S puede no haber ninguno y nunca hay más de uno de cada uno.
	var repeats: int = animal_repeats(_sx, _sz)
	var pony_groups: int = repeats if _rng.randf() < 0.7 else repeats - 1
	for group: int in pony_groups:
		var anchor: Vector3i = grass[_rng.randi_range(0, grass.size() - 1)]
		_place_group(grass_y, anchor, CharacterLibrary.PONY, _rng.randi_range(2, 3), 4)
	for rare: int in [CharacterLibrary.UNICORN, CharacterLibrary.DRAGON]:
		var chance: float = 0.6 if rare == CharacterLibrary.UNICORN else 0.5
		var count: int = rare_count(_sx, _sz, _rng.randf() < chance)
		for i: int in count:
			var anchor: Vector3i = grass[_rng.randi_range(0, grass.size() - 1)]
			_place_group(grass_y, anchor, rare, 1, 3)


## Celda libre más cercana a `anchor`, buscando en anillos cada vez más grandes.
static func _nearest_free(free_y: Dictionary[Vector2i, int], anchor: Vector2i) -> Vector3i:
	for radius: int in 40:
		var best := Vector3i(-1, -1, -1)
		var best_dist: float = INF
		for dz: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var key := Vector2i(anchor.x + dx, anchor.y + dz)
				if free_y.has(key) and Vector2(dx, dz).length() < best_dist:
					best_dist = Vector2(dx, dz).length()
					best = Vector3i(key.x, free_y[key], key.y)
		if best.x >= 0:
			return best
	return Vector3i(-1, -1, -1)


## Reparte `count` criaturas del mismo tipo en celdas libres cerca de `anchor`.
func _place_group(free_y: Dictionary[Vector2i, int], anchor: Vector3i, type: int, count: int,
		radius: int) -> void:
	var nearby: Array[Vector3i] = []
	for dz: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var key := Vector2i(anchor.x + dx, anchor.z + dz)
			if not free_y.has(key) or Vector2(dx, dz).length() > float(radius):
				continue
			var y: int = free_y[key]
			if absi(y - anchor.y) <= 1:
				nearby.append(Vector3i(key.x, y, key.y))
	var placed: int = 0
	while placed < count and not nearby.is_empty():
		var index: int = _rng.randi_range(0, nearby.size() - 1)
		var cell: Vector3i = nearby[index]
		nearby.remove_at(index)
		if entities.has_entity(cell):
			continue
		var variant: int = 0
		if CharacterLibrary.variant_count(type) > 1:
			variant = _rng.randi_range(0, CharacterLibrary.variant_count(type) - 1)
		entities.set_entity(cell, EntityLayer.make_entity(type, variant, _rng.randi_range(0, 3)))
		placed += 1
