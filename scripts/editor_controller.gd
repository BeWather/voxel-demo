class_name EditorController
extends Node3D
## Herramientas de edición, cursor 3D y deshacer/rehacer.
## Un trazo (desde que se presiona el botón hasta que se suelta) es un paso de deshacer.

signal tool_changed(tool: int)
signal history_changed(can_undo: bool, can_redo: bool)
signal status_changed(text: String)
## El mapa cambió por una edición (un trazo, deshacer o rehacer).
signal edited
## Se hizo clic sobre un aldeano con la herramienta "colocar criatura".
signal npc_edit_requested(cell: Vector3i)

enum Tool { PLACE, ERASE, PAINT, PROP_PLACE, PROP_ERASE, ENTITY_PLACE, ENTITY_ERASE, MOVE }

const TOOL_NAMES: Array[String] = [
	"Colocar bloque", "Borrar bloque", "Pintar bloque", "Colocar prop", "Borrar prop",
	"Colocar criatura", "Borrar criatura", "Mover",
]
## Qué hace cada herramienta, en una línea y con un ejemplo (ayuda emergente y línea de estado).
const TOOL_HINTS: Array[String] = [
	"Agrega bloques del tipo elegido sobre la cara apuntada — p. ej. levantar una loma o un muro.",
	"Quita bloques — p. ej. cavar un pozo o abrir un túnel.",
	"Cambia el tipo de un bloque que ya existe, sin agregar ni quitar — p. ej. convertir pasto en camino.",
	"Pone el prop elegido (árbol, flor, roca…) sobre un bloque. R lo gira antes de ponerlo.",
	"Quita un prop con un clic sobre él — p. ej. sacar un árbol que estorba.",
	"Pone el animal o aldeano elegido. Un clic sobre un aldeano ya puesto edita su nombre y su diálogo.",
	"Quita un animal o un aldeano con un clic sobre él.",
	"Cambia de lugar un prop, animal o aldeano: arrástralo, o haz clic para levantarlo y otro clic para soltarlo. R lo gira.",
]
const MOVE_NONE: int = 0
const MOVE_PROP: int = 1
const MOVE_ENTITY: int = 2
## Si el mouse se movió menos que esto entre apretar y soltar, cuenta como un clic.
const MOVE_CLICK_PIXELS: float = 6.0
const MAX_HISTORY: int = 200
const MAX_BRUSH: int = 5
const CURSOR_GROW: float = 0.02

var world: VoxelWorld
var props: PropLayer
var camera: Camera3D
## Capa de criaturas. Puede ser null (por ejemplo en pruebas que no la usan).
var entities: EntityLayer

var tool: int = Tool.PLACE
var block_id: int = Blocks.GRASS
var prop_id: int = PropLibrary.OAK
## Rotación (pasos de 90°) del próximo prop o criatura.
var prop_rot: int = 0
var prop_variant: int = 0
var entity_type: int = CharacterLibrary.SHEEP
var entity_variant: int = 0
var brush: int = 1
## Se desactiva mientras hay un diálogo abierto o se está en modo juego.
var input_enabled: bool = true

# --- historial
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _stroke_blocks: Dictionary[Vector3i, Array] = {}
var _stroke_props: Dictionary[Vector3i, Array] = {}
var _stroke_entities: Dictionary[Vector3i, Array] = {}
var _stroke_open: bool = false

# --- estado del puntero
var _dragging: bool = false
# Última posición del mouse vista en un evento (coordenadas del viewport).
var _mouse_pos: Vector2 = Vector2.ZERO
var _targets: Array[Vector3i] = []
var _has_hover: bool = false
var _hover_cell: Vector3i = Vector3i.ZERO
var _hover_axis: int = 1
var _hover_layer: int = 0
var _hover_plane: float = 0.0
var _prop_valid: bool = false
# Colocar criatura: el mouse está sobre un aldeano existente (el clic edita su diálogo).
var _hover_npc: bool = false
var _click_on_map: bool = false
# Herramienta mover: qué se está llevando (MOVE_*), desde dónde, con qué datos y rotación.
var _move_kind: int = MOVE_NONE
var _move_from: Vector3i = Vector3i.ZERO
var _move_data: Dictionary = {}
var _move_rot: int = 0
# El botón sigue apretado desde que se levantó el objeto (arrastre).
var _move_pressing: bool = false
var _move_press_pos: Vector2 = Vector2.ZERO
# Qué hay bajo el mouse cuando todavía no se levantó nada.
var _move_hover_kind: int = MOVE_NONE
# Colocar y borrar bloque: el arrastre queda fijado a la capa del primer clic, así un trazo
# nunca apila una torre hacia la cámara ni cava un pozo cada vez más hondo.
var _lock_axis: int = -1
var _lock_layer: int = 0
var _lock_plane: float = 0.0

# --- visuales
var _cursor: MeshInstance3D
var _ghost: MeshInstance3D
var _entity_ghost: CharacterRig
var _entity_ghost_key: int = -1
var _fill_material: StandardMaterial3D
var _line_material: StandardMaterial3D
var _ghost_material: StandardMaterial3D
var _shown_targets: Array[Vector3i] = []
var _shown_color: Color = Color.BLACK
var _last_status: String = ""


func setup(p_world: VoxelWorld, p_props: PropLayer, p_camera: Camera3D,
		p_entities: EntityLayer = null) -> void:
	world = p_world
	props = p_props
	camera = p_camera
	entities = p_entities


func _ready() -> void:
	_fill_material = StandardMaterial3D.new()
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.vertex_color_use_as_albedo = true
	_ghost_material.vertex_color_is_srgb = true
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(1.0, 1.0, 1.0, 0.6)

	_cursor = MeshInstance3D.new()
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor.visible = false
	add_child(_cursor)
	_ghost = MeshInstance3D.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.material_override = _ghost_material
	_ghost.visible = false
	add_child(_ghost)
	_entity_ghost = CharacterRig.new()
	_entity_ghost.visible = false
	add_child(_entity_ghost)
	prop_variant = props.library.random_variant(prop_id)
	entity_variant = randi() % CharacterLibrary.VILLAGER_VARIANTS
	_mouse_pos = get_viewport().get_mouse_position()


# ================================================================ selección

func set_tool(new_tool: int) -> void:
	if new_tool == tool or new_tool < 0 or new_tool >= TOOL_NAMES.size():
		return
	if _dragging:
		_finish_drag()
	cancel_move()
	tool = new_tool
	tool_changed.emit(tool)


func set_block(id: int) -> void:
	if Blocks.is_valid(id) and id != Blocks.AIR:
		block_id = id


## Elige el prop a colocar y sortea su variante (cada prop tiene su propia cantidad).
func set_prop(id: int) -> void:
	if props.library.is_valid(id):
		prop_id = id
		prop_variant = props.library.random_variant(id)


func set_entity_type(type: int) -> void:
	if CharacterLibrary.is_valid_entity(type):
		entity_type = type
		# Aspecto al azar entre los que tiene esa criatura (la vista previa lo muestra).
		entity_variant = randi() % CharacterLibrary.variant_count(type)


func set_brush(brush_size: int) -> void:
	brush = clampi(brush_size, 1, MAX_BRUSH)


func rotate_prop() -> void:
	prop_rot = (prop_rot + 1) % 4


# ================================================================ mover

## ¿Hay un objeto levantado con la herramienta mover?
func is_moving() -> bool:
	return _move_kind != MOVE_NONE


## Suelta lo que se estaba moviendo sin cambiar nada: vuelve a su lugar.
func cancel_move() -> void:
	_move_kind = MOVE_NONE
	_move_pressing = false
	_move_data = {}


## Celda libre para dejar un objeto: aire sobre un bloque sólido, sin prop ni criatura.
func is_free_cell(cell: Vector3i) -> bool:
	if props.has_prop(cell) or (entities != null and entities.has_entity(cell)):
		return false
	return _is_standable(cell)


## Mueve el prop o la criatura de `from` a `to` conservando todos sus datos (variante,
## nombre y diálogo de un aldeano, objeto propio…). `new_rot` (0 a 3) cambia la rotación;
## -1 la deja igual. Es un solo paso de deshacer. Devuelve false si no se pudo.
func move_object(from: Vector3i, to: Vector3i, new_rot: int = -1) -> bool:
	var is_entity: bool = entities != null and entities.has_entity(from)
	if not is_entity and not props.has_prop(from):
		return false
	var data: Dictionary = entities.get_entity(from) if is_entity else props.get_prop(from)
	var original: Dictionary = data.duplicate(true)
	if new_rot >= 0:
		data["rot"] = posmod(new_rot, 4)
	if to == from:
		if data == original:
			return false
	elif not is_free_cell(to):
		return false
	var single: bool = not _stroke_open
	if single:
		begin_stroke()
	if is_entity:
		apply_entity(from, {})
		apply_entity(to, data)
	else:
		apply_prop(from, {})
		apply_prop(to, data)
	if single:
		end_stroke()
	return true


## ¿El mouse apunta a una celda del mapa? (se usa para elegir dónde aparece el jugador).
func has_hover() -> bool:
	return _has_hover


func hover_cell() -> Vector3i:
	return _hover_cell


# ================================================================ historial

func begin_stroke() -> void:
	if _stroke_open:
		end_stroke()
	_stroke_blocks = {}
	_stroke_props = {}
	_stroke_entities = {}
	_stroke_open = true


## Cierra el trazo y lo guarda como un único paso de deshacer (si cambió algo).
func end_stroke() -> void:
	if not _stroke_open:
		return
	_stroke_open = false
	var blocks: Dictionary[Vector3i, Array] = _changed_entries(_stroke_blocks)
	var prop_changes: Dictionary[Vector3i, Array] = _changed_entries(_stroke_props)
	var entity_changes: Dictionary[Vector3i, Array] = _changed_entries(_stroke_entities)
	_stroke_blocks = {}
	_stroke_props = {}
	_stroke_entities = {}
	if blocks.is_empty() and prop_changes.is_empty() and entity_changes.is_empty():
		return
	_undo.append({"blocks": blocks, "props": prop_changes, "entities": entity_changes})
	if _undo.size() > MAX_HISTORY:
		_undo.pop_front()
	_redo.clear()
	_emit_history()
	edited.emit()


## Deja solo las entradas [anterior, nuevo] donde realmente hubo cambio.
static func _changed_entries(entries: Dictionary[Vector3i, Array]) -> Dictionary[Vector3i, Array]:
	var changed: Dictionary[Vector3i, Array] = {}
	for cell: Vector3i in entries:
		var entry: Array = entries[cell]
		if entry[0] != entry[1]:
			changed[cell] = entry
	return changed


## Cambia un bloque dentro del trazo actual. También quita lo que dependía de él: el prop o
## la criatura de la celda (si se coloca un bloque) y los de arriba (si deja de ser sólido).
func apply_block(cell: Vector3i, id: int) -> bool:
	if not world.in_bounds(cell):
		return false
	var old: int = world.get_block(cell)
	if old == id:
		return false
	var single: bool = not _stroke_open
	if single:
		begin_stroke()
	if _stroke_blocks.has(cell):
		_stroke_blocks[cell][1] = id
	else:
		_stroke_blocks[cell] = [old, id]
	world.set_block(cell, id)
	if id != Blocks.AIR:
		apply_prop(cell, {})
		apply_entity(cell, {})
	if not Blocks.is_solid(id):
		apply_prop(cell + Vector3i.UP, {})
		apply_entity(cell + Vector3i.UP, {})
	if single:
		end_stroke()
	return true


## Coloca, reemplaza o quita (diccionario vacío) un prop dentro del trazo actual.
func apply_prop(cell: Vector3i, data: Dictionary) -> bool:
	var old: Dictionary = props.get_prop(cell)
	if old == data:
		return false
	var single: bool = not _stroke_open
	if single:
		begin_stroke()
	if _stroke_props.has(cell):
		_stroke_props[cell][1] = data.duplicate()
	else:
		_stroke_props[cell] = [old, data.duplicate()]
	props.set_prop(cell, data)
	if single:
		end_stroke()
	return true


## Coloca, reemplaza o quita (diccionario vacío) una criatura dentro del trazo actual.
func apply_entity(cell: Vector3i, data: Dictionary) -> bool:
	if entities == null:
		return false
	var old: Dictionary = entities.get_entity(cell)
	if old == data:
		return false
	var single: bool = not _stroke_open
	if single:
		begin_stroke()
	if _stroke_entities.has(cell):
		_stroke_entities[cell][1] = data.duplicate(true)
	else:
		_stroke_entities[cell] = [old, data.duplicate(true)]
	entities.set_entity(cell, data)
	if single:
		end_stroke()
	return true


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	if _stroke_open or _undo.is_empty():
		return
	var step: Dictionary = _undo.pop_back()
	_restore(step, 0)
	_redo.append(step)
	_emit_history()
	edited.emit()


func redo() -> void:
	if _stroke_open or _redo.is_empty():
		return
	var step: Dictionary = _redo.pop_back()
	_restore(step, 1)
	_undo.append(step)
	_emit_history()
	edited.emit()


func clear_history() -> void:
	_undo.clear()
	_redo.clear()
	_stroke_open = false
	_dragging = false
	_emit_history()


## Aplica el lado `side` de un paso (0 = estado anterior, 1 = estado nuevo) sin registrar nada.
func _restore(step: Dictionary, side: int) -> void:
	var blocks: Dictionary = step["blocks"]
	for cell: Vector3i in blocks:
		var entry: Array = blocks[cell]
		var id: int = entry[side]
		world.set_block(cell, id)
	var prop_changes: Dictionary = step["props"]
	for cell: Vector3i in prop_changes:
		var entry: Array = prop_changes[cell]
		var data: Dictionary = entry[side]
		props.set_prop(cell, data)
	var entity_changes: Dictionary = step["entities"]
	if entities == null:
		return
	# La amistad (corazones, nombre de un animal, seguir) es progreso del juego, no una
	# edición: si este paso vuelve a ubicar una criatura que está ahora en el mapa (por
	# ejemplo, al deshacer un "mover"), conserva el progreso que tiene en este momento.
	var current: Array[Dictionary] = []
	for cell: Vector3i in entity_changes:
		if entities.has_entity(cell):
			current.append(entities.get_entity(cell))
	for cell: Vector3i in entity_changes:
		var entry: Array = entity_changes[cell]
		var data: Dictionary = entry[side]
		if not data.is_empty():
			data = _with_current_progress(data, current)
		entities.set_entity(cell, data)


## Devuelve `data` con el progreso de la criatura equivalente de `current`, si hay una.
static func _with_current_progress(data: Dictionary, current: Array[Dictionary]) -> Dictionary:
	for other: Dictionary in current:
		if other["type"] != data["type"] or other["variant"] != data["variant"] or other["lines"] != data["lines"]:
			continue
		var merged: Dictionary = data.duplicate(true)
		merged["friendship"] = other.get("friendship", 0)
		merged["follow"] = other.get("follow", false)
		# El nombre de un aldeano se edita en el mapa; el de un animal se lo pone el jugador.
		if data["type"] != CharacterLibrary.VILLAGER:
			merged["name"] = other["name"]
		return merged
	return data


func _emit_history() -> void:
	history_changed.emit(can_undo(), can_redo())


# ================================================================ reglas

## ¿La celda es aire sobre un bloque sólido?
func _is_standable(cell: Vector3i) -> bool:
	if not world.in_bounds(cell) or cell.y < 1:
		return false
	if world.get_block(cell) != Blocks.AIR:
		return false
	return Blocks.is_solid(world.get_block(cell + Vector3i.DOWN))


func can_place_prop(cell: Vector3i) -> bool:
	if entities != null and entities.has_entity(cell):
		return false
	return _is_standable(cell)


## Las criaturas no comparten celda con un prop ni con otra criatura.
func can_place_entity(cell: Vector3i) -> bool:
	if entities == null or entities.has_entity(cell) or props.has_prop(cell):
		return false
	return _is_standable(cell)


static func _axis_of(normal: Vector3i) -> int:
	if normal.x != 0:
		return 0
	if normal.z != 0:
		return 2
	return 1


## Huella cuadrada del pincel sobre el plano perpendicular a `axis`.
func _footprint(center: Vector3i, axis: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var a1: int = (axis + 1) % 3
	var a2: int = (axis + 2) % 3
	@warning_ignore("integer_division")
	var lo: int = -((brush - 1) / 2)
	@warning_ignore("integer_division")
	var hi: int = brush / 2
	for i: int in range(lo, hi + 1):
		for j: int in range(lo, hi + 1):
			var cell: Vector3i = center
			cell[a1] += i
			cell[a2] += j
			cells.append(cell)
	return cells


# ================================================================ entrada

func _unhandled_input(event: InputEvent) -> void:
	# Solo llegan aquí los clics que la interfaz no consumió.
	if not input_enabled or camera == null:
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
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _move_pressing:
			_move_release()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and is_moving():
			cancel_move()


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
			set_tool(Tool.PROP_PLACE)
		KEY_5, KEY_KP_5:
			set_tool(Tool.PROP_ERASE)
		KEY_6, KEY_KP_6:
			set_tool(Tool.ENTITY_PLACE)
		KEY_7, KEY_KP_7:
			set_tool(Tool.ENTITY_ERASE)
		KEY_8, KEY_KP_8:
			set_tool(Tool.MOVE)
		KEY_R:
			if is_moving():
				_move_rot = (_move_rot + 1) % 4
			else:
				rotate_prop()
		KEY_ESCAPE:
			cancel_move()


func _start_drag() -> void:
	# Este clic no lo consumió la interfaz, así que el puntero está sobre el mapa aunque el
	# control "bajo el mouse" que recuerda el motor esté desactualizado.
	_click_on_map = true
	_update_hover()
	_click_on_map = false
	if tool == Tool.MOVE:
		_move_press()
		return
	# Clic sobre un aldeano con "colocar criatura": se edita su diálogo, no empieza un trazo.
	if tool == Tool.ENTITY_PLACE and _hover_npc:
		npc_edit_requested.emit(_hover_cell)
		return
	_dragging = true
	_lock_axis = -1
	begin_stroke()
	if (tool == Tool.PLACE or tool == Tool.ERASE) and _has_hover:
		_lock_axis = _hover_axis
		_lock_layer = _hover_layer
		_lock_plane = _hover_plane
	_apply_tool()


func _finish_drag() -> void:
	_dragging = false
	_lock_axis = -1
	end_stroke()


func _process(_delta: float) -> void:
	if camera == null:
		return
	_update_hover()
	if _dragging:
		if input_enabled:
			_apply_tool()
		else:
			_finish_drag()
	_refresh_visuals()
	_refresh_status()


# ================================================================ puntero

## Calcula qué celdas afectaría la herramienta con el mouse donde está ahora.
## La misma lista se usa para dibujar el cursor y para aplicar la herramienta.
func _update_hover() -> void:
	_targets = []
	_has_hover = false
	_prop_valid = false
	_hover_npc = false
	if not input_enabled:
		return
	var viewport: Viewport = get_viewport()
	if not _dragging and not _click_on_map and viewport.gui_get_hovered_control() != null:
		return
	var origin: Vector3 = camera.project_ray_origin(_mouse_pos)
	var dir: Vector3 = camera.project_ray_normal(_mouse_pos)
	match tool:
		Tool.PLACE:
			_hover_place(origin, dir)
		Tool.ERASE, Tool.PAINT:
			_hover_block(origin, dir)
		Tool.PROP_PLACE:
			_hover_prop_place(origin, dir)
		Tool.PROP_ERASE:
			_hover_pick(origin, dir, false)
		Tool.ENTITY_PLACE:
			_hover_entity_place(origin, dir)
		Tool.ENTITY_ERASE:
			_hover_pick(origin, dir, true)
		Tool.MOVE:
			_hover_move(origin, dir)


func _hover_place(origin: Vector3, dir: Vector3) -> void:
	var center: Vector3i
	var axis: int
	if _dragging and _lock_axis >= 0:
		axis = _lock_axis
		if not _locked_point_valid(origin, dir):
			return
		center = _locked_center(origin, dir)
	else:
		var hit: Dictionary = world.raycast(origin, dir)
		if hit["hit"]:
			var normal: Vector3i = hit["normal"]
			if normal == Vector3i.ZERO:
				return
			var cell: Vector3i = hit["cell"]
			center = cell + normal
			axis = _axis_of(normal)
			_hover_plane = float(center[axis]) if normal[axis] > 0 else float(center[axis] + 1)
		else:
			# No hay bloques en esa dirección: se usa el piso del mundo (y = 0).
			if dir.y > -1e-6:
				return
			var p: Vector3 = origin + dir * (-origin.y / dir.y)
			center = Vector3i(floori(p.x), 0, floori(p.z))
			axis = 1
			_hover_plane = 0.0
		_hover_axis = axis
		_hover_layer = center[axis]
	_hover_cell = center
	_has_hover = world.in_bounds(center)
	for cell: Vector3i in _footprint(center, axis):
		if not world.in_bounds(cell):
			continue
		var existing: int = world.get_block(cell)
		# No se pisan bloques sólidos; el agua sí se puede reemplazar.
		if Blocks.is_solid(existing) or existing == block_id:
			continue
		_targets.append(cell)


func _hover_block(origin: Vector3, dir: Vector3) -> void:
	var center: Vector3i
	var axis: int
	if tool == Tool.ERASE and _dragging and _lock_axis >= 0:
		# Arrastre de borrado: solo se borra la capa del primer clic.
		axis = _lock_axis
		if not _locked_point_valid(origin, dir):
			return
		center = _locked_center(origin, dir)
	else:
		var hit: Dictionary = world.raycast(origin, dir)
		if not hit["hit"]:
			return
		center = hit["cell"]
		var normal: Vector3i = hit["normal"]
		axis = _axis_of(normal)
		_hover_axis = axis
		_hover_layer = center[axis]
		_hover_plane = float(center[axis] + 1) if normal[axis] > 0 else float(center[axis])
	_hover_cell = center
	_has_hover = world.in_bounds(center)
	for cell: Vector3i in _footprint(center, axis):
		var existing: int = world.get_block(cell)
		if existing == Blocks.AIR:
			continue
		if tool == Tool.ERASE or existing != block_id:
			_targets.append(cell)


## Durante un arrastre fijado: ¿el rayo cruza el plano del primer clic delante de la cámara?
func _locked_point_valid(origin: Vector3, dir: Vector3) -> bool:
	if absf(dir[_lock_axis]) < 1e-6:
		return false
	var t: float = (_lock_plane - origin[_lock_axis]) / dir[_lock_axis]
	return t > 0.0 and t < 600.0


## Celda de la capa fijada que queda bajo el mouse.
func _locked_center(origin: Vector3, dir: Vector3) -> Vector3i:
	var t: float = (_lock_plane - origin[_lock_axis]) / dir[_lock_axis]
	var p: Vector3 = origin + dir * t
	var center := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	center[_lock_axis] = _lock_layer
	return center


func _hover_prop_place(origin: Vector3, dir: Vector3) -> void:
	var hit: Dictionary = world.raycast(origin, dir)
	if not hit["hit"]:
		return
	var cell: Vector3i = hit["cell"]
	var normal: Vector3i = hit["normal"]
	cell += normal
	_hover_cell = cell
	_has_hover = world.in_bounds(cell)
	if not _has_hover:
		return
	_targets.append(cell)
	# Durante un arrastre, cada celda recibe un solo prop.
	_prop_valid = can_place_prop(cell) and not (_dragging and _stroke_props.has(cell))


func _hover_entity_place(origin: Vector3, dir: Vector3) -> void:
	if entities == null:
		return
	var hit: Dictionary = world.raycast(origin, dir)
	var limit: float = 600.0
	if hit["hit"]:
		var dist: float = hit["distance"]
		limit = dist + 0.01
	# Primero se mira si el mouse está sobre una criatura existente.
	var picked: Dictionary = entities.pick(origin, dir, limit)
	if not picked.is_empty() and not _dragging:
		var picked_cell: Vector3i = picked["cell"]
		_hover_cell = picked_cell
		_has_hover = true
		_targets.append(picked_cell)
		_hover_npc = entities.entities[picked_cell]["type"] == CharacterLibrary.VILLAGER
		return
	if not hit["hit"]:
		return
	var cell: Vector3i = hit["cell"]
	var normal: Vector3i = hit["normal"]
	cell += normal
	_hover_cell = cell
	_has_hover = world.in_bounds(cell)
	if not _has_hover:
		return
	_targets.append(cell)
	_prop_valid = can_place_entity(cell) and not (_dragging and _stroke_entities.has(cell))


## Herramientas de borrar prop / borrar criatura: busca lo que hay bajo el mouse.
func _hover_pick(origin: Vector3, dir: Vector3, pick_entities: bool) -> void:
	var hit: Dictionary = world.raycast(origin, dir)
	var limit: float = 600.0
	if hit["hit"]:
		var dist: float = hit["distance"]
		limit = dist + 0.01
	var picked: Dictionary = {}
	if pick_entities:
		if entities != null:
			picked = entities.pick(origin, dir, limit)
	else:
		picked = props.pick(origin, dir, limit)
	if picked.is_empty():
		return
	var cell: Vector3i = picked["cell"]
	_hover_cell = cell
	_has_hover = true
	_targets.append(cell)


## Herramienta mover. Sin nada levantado, busca el prop o la criatura bajo el mouse (lo más
## cercano, con la misma prueba que las herramientas de borrar). Con algo levantado, marca
## la celda donde caería y si es válida.
func _hover_move(origin: Vector3, dir: Vector3) -> void:
	_move_hover_kind = MOVE_NONE
	var hit: Dictionary = world.raycast(origin, dir)
	if not is_moving():
		var limit: float = 600.0
		if hit["hit"]:
			var dist: float = hit["distance"]
			limit = dist + 0.01
		var picked_prop: Dictionary = props.pick(origin, dir, limit)
		var picked_entity: Dictionary = {}
		if entities != null:
			picked_entity = entities.pick(origin, dir, limit)
		var picked: Dictionary = picked_prop
		_move_hover_kind = MOVE_PROP
		if not picked_entity.is_empty():
			var entity_dist: float = picked_entity["distance"]
			var prop_dist: float = INF
			if not picked_prop.is_empty():
				prop_dist = picked_prop["distance"]
			if entity_dist <= prop_dist:
				picked = picked_entity
				_move_hover_kind = MOVE_ENTITY
		if picked.is_empty():
			_move_hover_kind = MOVE_NONE
			return
		var picked_cell: Vector3i = picked["cell"]
		_hover_cell = picked_cell
		_has_hover = true
		_targets.append(picked_cell)
		return
	if not hit["hit"]:
		return
	var cell: Vector3i = hit["cell"]
	var normal: Vector3i = hit["normal"]
	cell += normal
	_hover_cell = cell
	_has_hover = world.in_bounds(cell)
	if not _has_hover:
		return
	_targets.append(cell)
	_prop_valid = cell == _move_from or is_free_cell(cell)


## Botón apretado con la herramienta mover: levanta lo que hay bajo el mouse o, si ya se
## llevaba algo (modo clic y clic), lo suelta.
func _move_press() -> void:
	if is_moving():
		_move_drop()
		return
	if _targets.is_empty() or _move_hover_kind == MOVE_NONE:
		return
	_move_from = _targets[0]
	_move_kind = _move_hover_kind
	_move_data = entities.get_entity(_move_from) if _move_kind == MOVE_ENTITY else props.get_prop(_move_from)
	_move_rot = _move_data["rot"]
	_move_pressing = true
	_move_press_pos = _mouse_pos


## Botón soltado: si el mouse se movió a otra celda, se suelta ahí (arrastre). Si sigue
## sobre el objeto, queda levantado y el próximo clic lo suelta.
func _move_release() -> void:
	_move_pressing = false
	if not is_moving():
		return
	# Soltar casi en el mismo punto es un clic: el objeto queda levantado.
	if _mouse_pos.distance_to(_move_press_pos) < MOVE_CLICK_PIXELS:
		return
	_click_on_map = true
	_update_hover()
	_click_on_map = false
	if _targets.is_empty():
		cancel_move()
	elif _targets[0] != _move_from:
		_move_drop()


## Deja el objeto en la celda apuntada si es válida; si no, vuelve a su lugar.
func _move_drop() -> void:
	if not _targets.is_empty() and _prop_valid:
		move_object(_move_from, _targets[0], _move_rot)
	cancel_move()


func _apply_tool() -> void:
	if _targets.is_empty():
		return
	match tool:
		Tool.PLACE, Tool.PAINT:
			for cell: Vector3i in _targets:
				apply_block(cell, block_id)
		Tool.ERASE:
			for cell: Vector3i in _targets:
				apply_block(cell, Blocks.AIR)
		Tool.PROP_PLACE:
			if _prop_valid:
				apply_prop(_targets[0], PropLayer.make_prop(prop_id, prop_variant, prop_rot))
				# Variante al azar para la próxima colocación (la vista previa la muestra).
				prop_variant = props.library.random_variant(prop_id)
				_prop_valid = false
		Tool.PROP_ERASE:
			for cell: Vector3i in _targets:
				apply_prop(cell, {})
		Tool.ENTITY_PLACE:
			if _prop_valid:
				if entity_type == CharacterLibrary.VILLAGER:
					apply_entity(_targets[0], EntityLayer.make_default_npc(entity_variant, prop_rot))
				else:
					apply_entity(_targets[0], EntityLayer.make_entity(entity_type, entity_variant, prop_rot))
				entity_variant = randi() % CharacterLibrary.variant_count(entity_type)
				_prop_valid = false
		Tool.ENTITY_ERASE:
			for cell: Vector3i in _targets:
				apply_entity(cell, {})


# ================================================================ visuales

func _cursor_color() -> Color:
	match tool:
		Tool.PLACE:
			return Color(0.45, 1.0, 0.55)
		Tool.ERASE, Tool.PROP_ERASE, Tool.ENTITY_ERASE:
			return Color(1.0, 0.33, 0.28)
		Tool.PAINT:
			var c: Color = Blocks.COLORS[block_id].lightened(0.25)
			return Color(c.r, c.g, c.b)
		Tool.MOVE:
			if not is_moving():
				return Color(1.0, 0.85, 0.30)
			return Color(0.45, 0.8, 1.0) if _prop_valid else Color(1.0, 0.33, 0.28)
		Tool.ENTITY_PLACE:
			if _hover_npc:
				return Color(1.0, 0.85, 0.30)
			return Color(0.45, 0.8, 1.0) if _prop_valid else Color(1.0, 0.33, 0.28)
		_:
			return Color(0.45, 0.8, 1.0) if _prop_valid else Color(1.0, 0.33, 0.28)


func _refresh_visuals() -> void:
	var color: Color = _cursor_color()
	if _targets != _shown_targets or color != _shown_color:
		_shown_targets = _targets.duplicate()
		_shown_color = color
		if _targets.is_empty():
			_cursor.visible = false
		else:
			_cursor.mesh = _build_cursor_mesh(_targets)
			_fill_material.albedo_color = Color(color.r, color.g, color.b, 0.28)
			_line_material.albedo_color = color
			_cursor.visible = true
	# Vista previa: el prop o la criatura que se va a colocar, o el que se está moviendo.
	var ghost_prop: Dictionary = {}
	var ghost_entity: Dictionary = {}
	var ghost_rot: int = prop_rot
	if not _targets.is_empty():
		if tool == Tool.PROP_PLACE and _prop_valid:
			ghost_prop = PropLayer.make_prop(prop_id, prop_variant, prop_rot)
		elif tool == Tool.ENTITY_PLACE and _prop_valid and entities != null:
			ghost_entity = EntityLayer.make_entity(entity_type, entity_variant, prop_rot)
		elif tool == Tool.MOVE and is_moving():
			ghost_rot = _move_rot
			if _move_kind == MOVE_PROP:
				ghost_prop = _move_data
			else:
				ghost_entity = _move_data
	if not ghost_prop.is_empty():
		var ghost_id: int = ghost_prop["id"]
		var ghost_variant: int = ghost_prop["variant"]
		_ghost.mesh = props.library.get_mesh(ghost_id, ghost_variant)
		_ghost.transform = PropLayer.cell_transform(_targets[0], ghost_rot)
		_ghost.visible = true
	else:
		_ghost.visible = false
	if not ghost_entity.is_empty():
		var ghost_type: int = ghost_entity["type"]
		var ghost_look: int = ghost_entity["variant"]
		var key: int = ghost_type * 8 + ghost_look
		if key != _entity_ghost_key:
			_entity_ghost_key = key
			_entity_ghost.setup(entities.library.get_entity_parts(ghost_type, ghost_look))
			_entity_ghost.set_ghost(0.45)
		_entity_ghost.transform = PropLayer.cell_transform(_targets[0], ghost_rot)
		_entity_ghost.visible = true
	else:
		_entity_ghost.visible = false


## Malla del cursor: una caja translúcida con aristas por cada celda afectada.
func _build_cursor_mesh(cells: Array[Vector3i]) -> ArrayMesh:
	var tris := PackedVector3Array()
	var lines := PackedVector3Array()
	var g: float = 0.5 + CURSOR_GROW
	for cell: Vector3i in cells:
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
	var cell_text: String = "Celda: —"
	if _has_hover:
		cell_text = "Celda: (%d, %d, %d)" % [_hover_cell.x, _hover_cell.y, _hover_cell.z]
	var detail: String
	match tool:
		Tool.PROP_PLACE:
			detail = "%s · rotación %d°" % [props.library.prop_name(prop_id), prop_rot * 90]
		Tool.PROP_ERASE:
			detail = "clic sobre un prop"
		Tool.ENTITY_PLACE:
			if _hover_npc:
				detail = "clic para editar el diálogo del aldeano"
			else:
				detail = "%s · rotación %d°" % [CharacterLibrary.ENTITY_NAMES[entity_type], prop_rot * 90]
		Tool.ENTITY_ERASE:
			detail = "clic sobre una criatura"
		Tool.MOVE:
			if is_moving():
				detail = "suelta o haz clic donde quieras dejarlo · R gira (%d°) · Esc cancela" % (_move_rot * 90)
			else:
				detail = "arrastra un prop, un animal o un aldeano"
		Tool.ERASE:
			detail = "pincel %d" % brush
		_:
			detail = "%s · pincel %d" % [Blocks.block_name(block_id), brush]
	# Sobre una criatura con nombre, se muestra cómo se llama.
	if _has_hover and entities != null and entities.has_entity(_hover_cell):
		var hovered_name: String = entities.entities[_hover_cell]["name"]
		if not hovered_name.is_empty():
			detail += " · «%s»" % hovered_name
	var text: String = "%s   |   %s: %s" % [cell_text, TOOL_NAMES[tool], detail]
	if text != _last_status:
		_last_status = text
		status_changed.emit(text)
