class_name ChunkMesher
extends RefCounted
## Genera el ArrayMesh de un chunk: solo caras expuestas, color por vértice,
## variación de tono por voxel y oclusión ambiental por vértice.

## Orden de caras: +X, -X, +Y, -Y, +Z, -Z. Para cada cara U x V = N.
const FACE_NORMAL: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const FACE_U: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1),
	Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0),
]
const FACE_V: Array[Vector3i] = [
	Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0),
]
## Signos de las 4 esquinas de una cara (antihorario vista desde afuera).
const CORNER_U: Array[int] = [-1, 1, 1, -1]
const CORNER_V: Array[int] = [-1, -1, 1, 1]
## Brillo según el nivel de oclusión (0 = más tapado, 3 = libre).
const AO_LEVELS: Array[float] = [0.52, 0.70, 0.86, 1.0]

const PAD: int = 18
const PAD_LAYER: int = 324
const PAD_VOLUME: int = 5832
## Valor usado en el borde inferior del mundo: se trata como sólido para no dibujar el piso.
const BEDROCK: int = 255
## Cuánto baja la superficie del agua.
const WATER_DROP: float = 0.125

var opaque_material: StandardMaterial3D
var water_material: StandardMaterial3D

var _opaque: PackedByteArray = PackedByteArray()
var _n_off: PackedInt32Array = PackedInt32Array()
var _u_off: PackedInt32Array = PackedInt32Array()
var _v_off: PackedInt32Array = PackedInt32Array()
var _corners: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()


func _init() -> void:
	opaque_material = make_opaque_material()
	water_material = StandardMaterial3D.new()
	water_material.vertex_color_use_as_albedo = true
	water_material.vertex_color_is_srgb = true
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.roughness = 0.35
	water_material.metallic_specular = 0.25

	_opaque.resize(256)
	_opaque.fill(0)
	for id: int in Blocks.COUNT:
		_opaque[id] = 0 if Blocks.is_transparent(id) else 1
	_opaque[BEDROCK] = 1

	for f: int in 6:
		_n_off.append(_pad_offset(FACE_NORMAL[f]))
		_u_off.append(_pad_offset(FACE_U[f]))
		_v_off.append(_pad_offset(FACE_V[f]))
		_normals.append(Vector3(FACE_NORMAL[f]))
		for k: int in 4:
			var corner: Vector3 = Vector3(FACE_NORMAL[f]) \
					+ Vector3(FACE_U[f]) * float(CORNER_U[k]) \
					+ Vector3(FACE_V[f]) * float(CORNER_V[k])
			_corners.append(corner * 0.5)


## Material opaco compartido por bloques y props.
static func make_opaque_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.1
	return mat


## Hash determinista de una celda, en el rango 0..1.
static func cell_hash(x: int, y: int, z: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


static func _pad_offset(v: Vector3i) -> int:
	return v.x + v.z * PAD + v.y * PAD_LAYER


## Construye la malla del chunk `key`. Devuelve null si no hay nada que dibujar.
func build(world: VoxelWorld, key: Vector3i) -> ArrayMesh:
	if not world.chunks.has(key):
		return null
	var base: Vector3i = key * VoxelWorld.CHUNK_SIZE

	# Copia local con un borde de 1 voxel: evita consultar el mundo en el bucle interno.
	var pad := PackedByteArray()
	pad.resize(PAD_VOLUME)
	var i: int = 0
	for y: int in range(-1, 17):
		var wy: int = base.y + y
		for z: int in range(-1, 17):
			var wz: int = base.z + z
			for x: int in range(-1, 17):
				pad[i] = world.get_block_padded(base.x + x, wy, wz)
				i += 1

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var w_verts := PackedVector3Array()
	var w_norms := PackedVector3Array()
	var w_cols := PackedColorArray()
	var w_idx := PackedInt32Array()
	var ao: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])

	for y: int in 16:
		for z: int in 16:
			var row: int = 1 + (z + 1) * PAD + (y + 1) * PAD_LAYER
			for x: int in 16:
				var pi: int = row + x
				var id: int = pad[pi]
				if id == Blocks.AIR:
					continue
				var center := Vector3(x + 0.5, y + 0.5, z + 0.5)
				var tint: float = 0.93 + 0.14 * cell_hash(base.x + x, base.y + y, base.z + z)

				if id == Blocks.WATER:
					var lowered: bool = pad[pi + PAD_LAYER] != Blocks.WATER
					var wc: Color = Blocks.COLORS[Blocks.WATER]
					var wt: float = 0.97 + 0.06 * (tint - 0.93) / 0.14
					var water_col := Color(wc.r * wt, wc.g * wt, wc.b * wt, wc.a)
					for f: int in 6:
						# El agua solo se dibuja contra el aire: entre dos voxeles de agua no hay cara.
						if pad[pi + _n_off[f]] != Blocks.AIR:
							continue
						var w_start: int = w_verts.size()
						for k: int in 4:
							var wp: Vector3 = center + _corners[f * 4 + k]
							if lowered and _corners[f * 4 + k].y > 0.0:
								wp.y -= WATER_DROP
							w_verts.append(wp)
							w_norms.append(_normals[f])
							w_cols.append(water_col)
						w_idx.append(w_start)
						w_idx.append(w_start + 2)
						w_idx.append(w_start + 1)
						w_idx.append(w_start)
						w_idx.append(w_start + 3)
						w_idx.append(w_start + 2)
					continue

				for f: int in 6:
					var ni: int = pi + _n_off[f]
					if _opaque[pad[ni]] == 1:
						continue
					var base_col: Color = Blocks.face_color(id, f)
					var uo: int = _u_off[f]
					var vo: int = _v_off[f]
					var start: int = verts.size()
					for k: int in 4:
						var su: int = CORNER_U[k] * uo
						var sv: int = CORNER_V[k] * vo
						var s1: int = _opaque[pad[ni + su]]
						var s2: int = _opaque[pad[ni + sv]]
						var level: int = 0
						if s1 == 0 or s2 == 0:
							level = 3 - (s1 + s2 + _opaque[pad[ni + su + sv]])
						ao[k] = level
						var b: float = tint * AO_LEVELS[level]
						verts.append(center + _corners[f * 4 + k])
						norms.append(_normals[f])
						cols.append(Color(base_col.r * b, base_col.g * b, base_col.b * b, 1.0))
					# Godot usa caras frontales en sentido horario. La diagonal se elige según
					# la oclusión para que el sombreado no dependa de la orientación del quad.
					if ao[0] + ao[2] < ao[1] + ao[3]:
						idx.append(start + 1)
						idx.append(start + 3)
						idx.append(start + 2)
						idx.append(start + 1)
						idx.append(start)
						idx.append(start + 3)
					else:
						idx.append(start)
						idx.append(start + 2)
						idx.append(start + 1)
						idx.append(start)
						idx.append(start + 3)
						idx.append(start + 2)

	if verts.is_empty() and w_verts.is_empty():
		return null

	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		_add_surface(mesh, verts, norms, cols, idx, opaque_material)
	if not w_verts.is_empty():
		_add_surface(mesh, w_verts, w_norms, w_cols, w_idx, water_material)
	return mesh


static func _add_surface(mesh: ArrayMesh, verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, idx: PackedInt32Array, material: Material) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
