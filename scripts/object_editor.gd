class_name ObjectEditor
extends Node3D
## Editor de objetos: edita los modelos mini-voxel de un prop (todas sus variantes) y los
## guarda en la biblioteca. Trabaja en mini-voxeles: un voxel del modelo mide 1 unidad en
## esta escena y el origen es el centro de la base, igual que al colocarlo en el mapa.
## Un trazo (presionar, arrastrar, soltar) es un paso de deshacer de la variante activa.

signal tool_changed(tool: int)
signal color_changed(color: Color)
signal history_changed(can_undo: bool, can_redo: bool)
signal status_changed(text: String)
## Cambió el documento: objeto abierto, nombre, variantes, variante activa o "sin guardar".
signal document_changed
## Cambió la lista de colores usados en la variante activa.
signal palette_changed(colors: Array[Color])
## Se pidió guardar con el teclado (Ctrl+S); la interfaz decide si hace falta pedir un nombre.
signal save_requested

enum Tool { PLACE, ERASE, PAINT, PICK }

const TOOL_NAMES: Array[String] = ["Colocar voxel", "Borrar voxel", "Pintar voxel", "Tomar color"]
const NEW_NAME: String = "Objeto nuevo"
## Lado de la celda de un bloque del mapa, en mini-voxeles.
const FOOTPRINT: int = 8
const HALF_FOOTPRINT: int = 4
const CURSOR_GROW: float = 0.03

var library: PropLibrary
var camera: EditorCamera

var tool: int = Tool.PLACE
var color: Color = Color.html("5ca83d")
## Solo se atiende la entrada con el modo activo y sin diálogos abiertos.
var input_enabled: bool = false

# --- documento
## Clave del objeto abierto. Vacía = objeto nuevo que todavía no se guardó.
var object_key: String = ""
var object_name: String = NEW_NAME
## Variante activa (la que se ve y se edita).
var variant: int = 0
## Hay cambios sin guardar.
var modified: bool = false

var _variants: Array[ObjectModel] = [ObjectModel.new()]

# --- estado del puntero
var _dragging: bool = false
var _mouse_pos: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _target_valid: bool = false
var _target: Vector3i = Vector3i.ZERO
var _hover_axis: int = 1
var _hover_layer: int = 0
var _hover_plane: float = 0.0
# Colocar y borrar: el arrastre queda fijado a la capa del primer clic (igual que en el mapa).
var _lock_axis: int = -1
var _lock_layer: int = 0
var _lock_plane: float = 0.0
var _previous_tool: int = Tool.PLACE

# --- visuales
var _mesh_node: MeshInstance3D
var _cursor: MeshInstance3D
var _fill_material: StandardMaterial3D
var _line_material: StandardMaterial3D
var _shown_model: ObjectModel
var _shown_revision: int = -1
var _shown_colors: Array[Color] = []
var _shown_target: Vector3i = Vector3i.ZERO
var _shown_cursor: bool = false
var _shown_color: Color = Color.BLACK
var _last_status: String = ""
var _info: String = ""


func setup(p_library: PropLibrary) -> void:
	library = p_library


## Muestra u oculta el editor completo y le da (o no) la cámara activa.
func set_active(active: bool) -> void:
	visible = active
	if active:
		if camera != null:
			camera.make_current()
	else:
		_cancel_drag()
		set_input_enabled(false)


## Habilita la edición y la cámara (se apaga con un diálogo abierto o en modo mapa).
func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if camera != null:
		camera.input_enabled = enabled


func _ready() -> void:
	_build_stage()
	_fill_material = StandardMaterial3D.new()
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "Modelo"
	# La malla sale en bloques (1/8 por voxel); aquí cada voxel ocupa una unidad.
	_mesh_node.scale = Vector3.ONE / PropLibrary.VOXEL
	add_child(_mesh_node)
	_cursor = MeshInstance3D.new()
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor.visible = false
	add_child(_cursor)

	camera = EditorCamera.new()
	camera.name = "CamaraObjetos"
	camera.pan_vertical = true
	camera.input_enabled = false
	add_child(camera)
	frame_camera()
	_mouse_pos = get_viewport().get_mouse_position()


# ================================================================ documento

## Variante activa.
func model() -> ObjectModel:
	return _variants[variant]


func variant_count() -> int:
	return _variants.size()


## ¿El objeto todavía no existe en la biblioteca?
func is_new() -> bool:
	return object_key.is_empty()


## Id del objeto abierto en la biblioteca, o -1 si es nuevo.
func object_id() -> int:
	return library.key_to_id(object_key)


## ¿El objeto abierto es un incorporado modificado que se puede volver al original?
func can_restore() -> bool:
	var id: int = object_id()
	return id >= 0 and library.is_overridden(id)


func can_add_variant() -> bool:
	return _variants.size() < PropLibrary.MAX_VARIANTS


func can_remove_variant() -> bool:
	return _variants.size() > 1


## Empieza un objeto vacío. Descarta lo que hubiera abierto.
func new_object() -> void:
	_cancel_drag()
	object_key = ""
	object_name = NEW_NAME
	_variants = [ObjectModel.new()]
	variant = 0
	modified = false
	frame_camera()
	_document_changed()


## Abre una copia de un objeto de la biblioteca. Descarta lo que hubiera abierto.
func open_object(id: int, p_variant: int = 0) -> void:
	if not library.is_valid(id):
		return
	_cancel_drag()
	object_key = library.prop_key(id)
	object_name = library.prop_name(id)
	_variants = []
	# Colores a 8 bits por canal desde el principio: lo que se ve es lo que se guarda.
	for entry: Dictionary in PropIO.quantize_variants(library.get_variants(id)):
		var vox: Dictionary[int, Color] = entry
		_variants.append(ObjectModel.new(vox))
	variant = clampi(p_variant, 0, _variants.size() - 1)
	modified = false
	frame_camera()
	_document_changed()


func set_variant(index: int) -> void:
	if index < 0 or index >= _variants.size() or index == variant:
		return
	_cancel_drag()
	variant = index
	_document_changed()


## Agrega una variante que es copia de la activa y pasa a editarla.
func add_variant() -> void:
	if not can_add_variant():
		return
	_cancel_drag()
	_variants.append(ObjectModel.new(model().voxels))
	variant = _variants.size() - 1
	modified = true
	_document_changed()


## Quita la variante activa (nunca la última).
func remove_variant() -> void:
	if not can_remove_variant():
		return
	_cancel_drag()
	_variants.remove_at(variant)
	variant = mini(variant, _variants.size() - 1)
	modified = true
	_document_changed()


## Guarda sobre el objeto abierto (todas sus variantes). Devuelve "" o un mensaje de error.
func save() -> String:
	if is_new():
		return "El objeto todavía no tiene nombre."
	return save_as(object_name, object_key)


## Guarda con otro nombre y clave; el documento pasa a ser ese objeto.
func save_as(display_name: String, key: String) -> String:
	_cancel_drag()
	var data: Array[Dictionary] = []
	for entry: ObjectModel in _variants:
		data.append(entry.voxels.duplicate())
	var result: Dictionary = library.save_prop(key, display_name.strip_edges(), data)
	if not result["ok"]:
		var error: String = result["error"]
		return error
	object_key = key
	object_name = display_name.strip_edges()
	modified = false
	_document_changed()
	return ""


## Vuelve un incorporado a su modelo original y lo reabre. Devuelve "" o un mensaje de error.
func restore_original() -> String:
	var id: int = object_id()
	if id < 0:
		return "El objeto no está en la biblioteca."
	var error: String = library.restore_builtin(id)
	if error.is_empty():
		open_object(id, variant)
	return error


func _document_changed() -> void:
	document_changed.emit()
	_emit_history()


func _mark_modified() -> void:
	if not modified:
		modified = true
		document_changed.emit()


# ================================================================ selección

func set_tool(new_tool: int) -> void:
	if new_tool == tool or new_tool < 0 or new_tool >= TOOL_NAMES.size():
		return
	if _dragging:
		_finish_drag()
	_previous_tool = tool
	tool = new_tool
	tool_changed.emit(tool)


func set_color(new_color: Color) -> void:
	# Mismo redondeo que al guardar, así la paleta del modelo no junta casi-duplicados.
	var rounded: Color = Color.html(new_color.to_html(false))
	if rounded == color:
		return
	color = rounded
	color_changed.emit(color)


# ================================================================ historial

func can_undo() -> bool:
	return model().can_undo()


func can_redo() -> bool:
	return model().can_redo()


func undo() -> void:
	if model().undo():
		_mark_modified()
		_emit_history()


func redo() -> void:
	if model().redo():
		_mark_modified()
		_emit_history()


func _emit_history() -> void:
	history_changed.emit(can_undo(), can_redo())


# ================================================================ entrada

func _unhandled_input(event: InputEvent) -> void:
	# Solo llegan aquí los clics que la interfaz no consumió.
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _dragging:
			_start_drag()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		var mouse_event: InputEventMouse = event
		_mouse_pos = mouse_event.position
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _dragging:
			_finish_drag()


func _unhandled_key_input(event: InputEvent) -> void:
	if not input_enabled or not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed:
		return
	if key.ctrl_pressed or key.meta_pressed:
		if key.keycode == KEY_Z and key.shift_pressed:
			redo()
		elif key.keycode == KEY_Z:
			undo()
		elif key.keycode == KEY_Y:
			redo()
		elif key.keycode == KEY_S and not key.echo:
			save_requested.emit()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if key.echo:
		return
	match key.keycode:
		KEY_1, KEY_KP_1:
			set_tool(Tool.PLACE)
		KEY_2, KEY_KP_2:
			set_tool(Tool.ERASE)
		KEY_3, KEY_KP_3:
			set_tool(Tool.PAINT)
		KEY_4, KEY_KP_4:
			set_tool(Tool.PICK)


func _start_drag() -> void:
	_dragging = true
	_lock_axis = -1
	model().begin_stroke()
	_update_hover()
	_try_lock()
	_apply_tool()


## Fija el arrastre a la capa del primer voxel apuntado: un trazo no apila una torre hacia
## la cámara ni cava un pozo.
func _try_lock() -> void:
	if _lock_axis < 0 and _has_target and (tool == Tool.PLACE or tool == Tool.ERASE):
		_lock_axis = _hover_axis
		_lock_layer = _hover_layer
		_lock_plane = _hover_plane


func _finish_drag() -> void:
	_dragging = false
	_lock_axis = -1
	if model().end_stroke():
		_mark_modified()
		_emit_history()


## Cierra el trazo en curso antes de cambiar de variante o de documento.
func _cancel_drag() -> void:
	if _dragging:
		_finish_drag()


func _process(_delta: float) -> void:
	if camera == null or not visible:
		return
	_update_hover()
	if _dragging:
		if input_enabled:
			_try_lock()
			_apply_tool()
		else:
			_finish_drag()
	_refresh_model()
	_refresh_cursor()
	_refresh_status()


# ================================================================ puntero

static func _axis_of(normal: Vector3i) -> int:
	if normal.x != 0:
		return 0
	if normal.z != 0:
		return 2
	return 1


## Calcula qué voxel afectaría la herramienta con el mouse donde está ahora.
## El mismo voxel se usa para dibujar el cursor y para aplicar la herramienta.
func _update_hover() -> void:
	_has_target = false
	_target_valid = false
	if not input_enabled:
		return
	var viewport: Viewport = get_viewport()
	if not _dragging and viewport.gui_get_hovered_control() != null:
		return
	var origin: Vector3 = camera.project_ray_origin(_mouse_pos)
	var dir: Vector3 = camera.project_ray_normal(_mouse_pos)
	if tool == Tool.PLACE:
		_hover_place(origin, dir)
	else:
		_hover_voxel(origin, dir)


func _hover_place(origin: Vector3, dir: Vector3) -> void:
	var cell: Vector3i
	if _dragging and _lock_axis >= 0:
		if not _locked_point_valid(origin, dir):
			return
		cell = _locked_cell(origin, dir)
	else:
		var hit: Dictionary = model().raycast(origin, dir)
		var normal: Vector3i = hit["normal"]
		if hit["hit"]:
			if normal == Vector3i.ZERO:
				return
			var hit_cell: Vector3i = hit["cell"]
			cell = hit_cell + normal
			_hover_axis = _axis_of(normal)
			_hover_plane = float(cell[_hover_axis]) if normal[_hover_axis] > 0 else float(cell[_hover_axis] + 1)
		elif hit["floor"]:
			# Sin voxeles en esa dirección: se apoya sobre la cuadrícula del piso.
			cell = hit["cell"]
			_hover_axis = 1
			_hover_plane = 0.0
		else:
			return
		_hover_layer = cell[_hover_axis]
	_target = cell
	_has_target = ObjectModel.in_bounds(cell)
	_target_valid = _has_target and not model().has_voxel(cell)


func _hover_voxel(origin: Vector3, dir: Vector3) -> void:
	var cell: Vector3i
	if tool == Tool.ERASE and _dragging and _lock_axis >= 0:
		# Arrastre de borrado: solo se borra la capa del primer clic.
		if not _locked_point_valid(origin, dir):
			return
		cell = _locked_cell(origin, dir)
	else:
		var hit: Dictionary = model().raycast(origin, dir)
		if not hit["hit"]:
			return
		cell = hit["cell"]
		var normal: Vector3i = hit["normal"]
		_hover_axis = _axis_of(normal)
		_hover_layer = cell[_hover_axis]
		_hover_plane = float(cell[_hover_axis] + 1) if normal[_hover_axis] > 0 else float(cell[_hover_axis])
	_target = cell
	_has_target = ObjectModel.in_bounds(cell)
	_target_valid = _has_target and model().has_voxel(cell)
	if _target_valid and tool == Tool.PAINT:
		_target_valid = model().get_voxel(cell) != color


## Durante un arrastre fijado: ¿el rayo cruza el plano del primer clic delante de la cámara?
func _locked_point_valid(origin: Vector3, dir: Vector3) -> bool:
	if absf(dir[_lock_axis]) < 1e-6:
		return false
	var t: float = (_lock_plane - origin[_lock_axis]) / dir[_lock_axis]
	return t > 0.0 and t < 2000.0


## Voxel de la capa fijada que queda bajo el mouse.
func _locked_cell(origin: Vector3, dir: Vector3) -> Vector3i:
	var t: float = (_lock_plane - origin[_lock_axis]) / dir[_lock_axis]
	var p: Vector3 = origin + dir * t
	var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	cell[_lock_axis] = _lock_layer
	return cell


func _apply_tool() -> void:
	if not _target_valid:
		return
	match tool:
		Tool.PLACE, Tool.PAINT:
			model().set_voxel(_target, color)
		Tool.ERASE:
			model().erase_voxel(_target)
		Tool.PICK:
			set_color(model().get_voxel(_target))
			# Con el color tomado se vuelve a la herramienta anterior.
			set_tool(_previous_tool if _previous_tool != Tool.PICK else Tool.PAINT)
	_target_valid = false


# ================================================================ visuales

## Encuadra la variante activa.
func frame_camera() -> void:
	if camera == null:
		return
	var box: AABB = model().bounds()
	var reach: float = maxf(box.size.y, maxf(box.size.x, box.size.z))
	camera.bounds_min = Vector3(PropLibrary.MIN_XZ, 0.0, PropLibrary.MIN_XZ)
	camera.bounds_max = Vector3(PropLibrary.MAX_XZ + 1, PropLibrary.MAX_Y + 1, PropLibrary.MAX_XZ + 1)
	camera.focus = Vector3(0.0, maxf(box.end.y * 0.5, 2.0), 0.0)
	camera.distance = clampf(reach * 1.7 + 10.0, 18.0, 150.0)
	camera.yaw = 0.65
	camera.pitch = 0.48
	camera.update_view()


## Regenera la malla si el modelo cambió; como mucho una vez por frame.
func _refresh_model() -> void:
	var current: ObjectModel = model()
	if current == _shown_model and current.revision == _shown_revision:
		return
	_shown_model = current
	_shown_revision = current.revision
	_mesh_node.mesh = PropLibrary.mesh_from_voxels(current.voxels, library.material)
	var box: AABB = current.bounds()
	_info = "%d voxeles · %d × %d × %d" % [current.count(), int(box.size.x), int(box.size.y), int(box.size.z)]
	var colors: Array[Color] = current.used_colors()
	if colors != _shown_colors:
		_shown_colors = colors
		palette_changed.emit(colors)


## Cantidad de voxeles y tamaño (ancho × alto × fondo) de la variante activa.
func info_text() -> String:
	return _info


func _cursor_color() -> Color:
	match tool:
		Tool.PLACE:
			return Color(0.45, 1.0, 0.55)
		Tool.ERASE:
			return Color(1.0, 0.33, 0.28)
		Tool.PAINT:
			return color.lightened(0.25)
		_:
			return Color(1.0, 1.0, 1.0)


func _refresh_cursor() -> void:
	var cursor_color: Color = _cursor_color()
	if _target_valid == _shown_cursor and _target == _shown_target and cursor_color == _shown_color:
		return
	_shown_cursor = _target_valid
	_shown_target = _target
	_shown_color = cursor_color
	_cursor.visible = _target_valid
	if not _target_valid:
		return
	_fill_material.albedo_color = Color(cursor_color.r, cursor_color.g, cursor_color.b, 0.30)
	_line_material.albedo_color = cursor_color
	_cursor.mesh = _build_cursor_mesh(_target)


## Malla del cursor: una caja translúcida con aristas alrededor del voxel.
func _build_cursor_mesh(cell: Vector3i) -> ArrayMesh:
	var tris := PackedVector3Array()
	var lines := PackedVector3Array()
	var g: float = 0.5 + CURSOR_GROW
	var center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	for f: int in 6:
		var n := Vector3(ChunkMesher.FACE_NORMAL[f])
		var u := Vector3(ChunkMesher.FACE_U[f])
		var v := Vector3(ChunkMesher.FACE_V[f])
		var c0: Vector3 = center + (n - u - v) * g
		var c1: Vector3 = center + (n + u - v) * g
		var c2: Vector3 = center + (n + u + v) * g
		var c3: Vector3 = center + (n - u + v) * g
		tris.append_array(PackedVector3Array([c0, c2, c1, c0, c3, c2]))
		lines.append_array(PackedVector3Array([c0, c1, c1, c2, c2, c3, c3, c0]))
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tris
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _fill_material)
	arrays[Mesh.ARRAY_VERTEX] = lines
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh.surface_set_material(1, _line_material)
	return mesh


func _refresh_status() -> void:
	var cell_text: String = "Voxel: —"
	if _has_target:
		cell_text = "Voxel: (%d, %d, %d)" % [_target.x, _target.y, _target.z]
	var detail: String = TOOL_NAMES[tool]
	if tool == Tool.PLACE or tool == Tool.PAINT:
		detail += ": #%s" % color.to_html(false)
	var text: String = "%s   |   %s   |   %s" % [cell_text, detail, _info]
	if text != _last_status:
		_last_status = text
		status_changed.emit(text)


# ================================================================ escenario

## Piso, cuadrícula del volumen de edición y contorno de la celda del mapa.
func _build_stage() -> void:
	var lo: float = float(PropLibrary.MIN_XZ)
	var hi: float = float(PropLibrary.MAX_XZ + 1)
	var top: float = float(PropLibrary.MAX_Y + 1)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(hi - lo, hi - lo)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.25, 0.26, 0.28)
	floor_material.roughness = 1.0
	floor_mesh.material = floor_material
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Piso"
	floor_node.mesh = floor_mesh
	floor_node.position = Vector3(0.0, -0.04, 0.0)
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_node)

	# Cuadrícula: una línea por mini-voxel y una más marcada cada 8 (un bloque del mapa).
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var fine := Color(1.0, 1.0, 1.0, 0.07)
	var strong := Color(1.0, 1.0, 1.0, 0.30)
	for i: int in range(PropLibrary.MIN_XZ, PropLibrary.MAX_XZ + 2):
		var line_color: Color = strong if posmod(i - HALF_FOOTPRINT, FOOTPRINT) == 0 else fine
		if i == PropLibrary.MIN_XZ or i == PropLibrary.MAX_XZ + 1:
			line_color = strong
		var at: float = float(i)
		verts.append_array(PackedVector3Array([
			Vector3(at, 0.0, lo), Vector3(at, 0.0, hi), Vector3(lo, 0.0, at), Vector3(hi, 0.0, at),
		]))
		cols.append_array(PackedColorArray([line_color, line_color, line_color, line_color]))
	# Aristas del volumen de edición.
	var edge := Color(1.0, 1.0, 1.0, 0.16)
	for corner: Vector2 in [Vector2(lo, lo), Vector2(hi, lo), Vector2(hi, hi), Vector2(lo, hi)]:
		verts.append_array(PackedVector3Array([Vector3(corner.x, 0.0, corner.y), Vector3(corner.x, top, corner.y)]))
		cols.append_array(PackedColorArray([edge, edge]))
	verts.append_array(PackedVector3Array([
		Vector3(lo, top, lo), Vector3(hi, top, lo), Vector3(hi, top, lo), Vector3(hi, top, hi),
		Vector3(hi, top, hi), Vector3(lo, top, hi), Vector3(lo, top, hi), Vector3(lo, top, lo),
	]))
	for i: int in 8:
		cols.append(edge)
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_material.vertex_color_use_as_albedo = true
	var grid := MeshInstance3D.new()
	grid.name = "Cuadricula"
	grid.mesh = _mesh_from(Mesh.PRIMITIVE_LINES, verts, cols, grid_material)
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid)

	# Contorno de la celda del mapa (8 × 8 centrada en el origen): un marco con grosor,
	# apenas hundido para que los voxeles de la base lo tapen solo donde lo pisan.
	var half: float = float(HALF_FOOTPRINT)
	var width: float = 0.22
	var frame_verts := PackedVector3Array()
	for side: int in 4:
		var along := Vector3(1.0, 0.0, 0.0) if side % 2 == 0 else Vector3(0.0, 0.0, 1.0)
		var across := Vector3(0.0, 0.0, 1.0) if side % 2 == 0 else Vector3(1.0, 0.0, 0.0)
		var offset: float = -half - width if side < 2 else half
		var a: Vector3 = along * (-half - width) + across * offset
		var b: Vector3 = along * (half + width) + across * offset
		var c: Vector3 = b + across * width
		var d: Vector3 = a + across * width
		frame_verts.append_array(PackedVector3Array([a, b, c, a, c, d]))
	var frame_material := StandardMaterial3D.new()
	frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame_material.albedo_color = Color(1.0, 0.76, 0.18)
	frame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame := MeshInstance3D.new()
	frame.name = "CeldaDelMapa"
	frame.mesh = _mesh_from(Mesh.PRIMITIVE_TRIANGLES, frame_verts, PackedColorArray(), frame_material)
	frame.position = Vector3(0.0, -0.01, 0.0)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(frame)
	# El mismo marco, tenue y sin prueba de profundidad: se trasluce cuando el modelo lo tapa.
	var ghost_material := StandardMaterial3D.new()
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.albedo_color = Color(1.0, 0.76, 0.18, 0.30)
	ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost_material.no_depth_test = true
	var ghost := MeshInstance3D.new()
	ghost.name = "CeldaDelMapaTraslucida"
	ghost.mesh = _mesh_from(Mesh.PRIMITIVE_TRIANGLES, frame_verts, PackedColorArray(), ghost_material)
	ghost.position = frame.position
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)


static func _mesh_from(primitive: Mesh.PrimitiveType, verts: PackedVector3Array, cols: PackedColorArray,
		mesh_material: Material) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if not cols.is_empty():
		arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(primitive, arrays)
	mesh.surface_set_material(0, mesh_material)
	return mesh
