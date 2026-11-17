class_name PlayFriends
extends Node3D
## Juntar cosas y hacerse amiga de los animales, en modo juego.
##
## - Juntar: flores, hongos y pasto alto del mapa, y manzanas que cuelgan de los robles.
##   Lo juntado desaparece de la vista y vuelve a crecer al rato. Nada de esto cambia los
##   props del mapa: es estado del juego y se descarta al volver al editor.
## - Mochila: cuántas hay de cada cosa (se guarda con el mapa).
## - Amistad: dar de comer o acariciar suma puntos; los corazones, el nombre y "seguir" son
##   datos de la criatura y también se guardan con el mapa.

## Cambió algo que se guarda con el mapa (mochila, amistad, nombre, seguir).
signal progress_changed

const CREATURE_DISTANCE: float = 2.6
const GATHER_DISTANCE: float = 1.7
const APPLE_DISTANCE: float = 2.4
const REGROW_MIN_SECONDS: float = 60.0
const REGROW_MAX_SECONDS: float = 90.0
const GROW_SECONDS: float = 1.2
const GROW_START_SCALE: float = 0.15
const PET_COOLDOWN: float = 6.0
const OVERHEAD_DISTANCE: float = 9.0
const MAX_FOLLOWERS: int = 4
## Un seguidor que queda más lejos que esto aparece en una celda cercana al jugador.
const CATCH_UP_DISTANCE: float = 18.0
## ...y también uno que pasa BEHIND_SECONDS seguidos a más de BEHIND_DISTANCE sin poder llegar.
const BEHIND_DISTANCE: float = 6.0
const BEHIND_SECONDS: float = 4.0
const APPLE_SCALE: float = 1.35
const MAX_NAME_LENGTH: int = 16
## Resultados de feed().
const FED_FAVOURITE: String = "favorita"
const FED_LIKED: String = "aceptada"
const REJECTED: String = "rechazada"
const PETTED: String = "caricia"
const WAIT: String = "espera"
const NOBODY: String = "nadie"

var play: PlayMode
## Mochila: {clave de cosa: cantidad}. Es el mismo diccionario que guarda el mapa.
var backpack: Dictionary = Items.empty_backpack()
var selected: int = 0
var icons: Array[ImageTexture] = []
## Criatura (no aldeano) más cercana al jugador, dentro de CREATURE_DISTANCE.
var nearby_creature: EntityActor
## Lo que se puede juntar ahora: {"cell", "item", "apple"} o vacío.
var nearby_gather: Dictionary = {}
## Criatura a la que se le está poniendo nombre (el juego espera).
var naming_actor: EntityActor

var _regrow: Dictionary[Vector3i, float] = {}
var _growing: Dictionary[Vector3i, float] = {}
var _apple_index: Dictionary[Vector3i, int] = {}
var _apple_wait: Dictionary[Vector3i, float] = {}
var _apples: MultiMeshInstance3D
var _apple_mesh: ArrayMesh
var _overheads: Dictionary[int, EntityOverhead] = {}
var _pet_wait: Dictionary[int, float] = {}
var _behind_time: Dictionary[int, float] = {}
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _heart_material: StandardMaterial3D


func setup(p_play: PlayMode) -> void:
	play = p_play


# ================================================================ entrar y salir

func start() -> void:
	if icons.is_empty():
		icons = Items.build_icons(play.props.library)
		EntityOverhead.prepare(icons)
	selected = clampi(selected, 0, Items.COUNT - 1)
	nearby_creature = null
	nearby_gather = {}
	naming_actor = null
	_regrow.clear()
	_growing.clear()
	_pet_wait.clear()
	_behind_time.clear()
	_build_apples()


## Al salir, lo juntado vuelve a verse y se van los carteles: el mapa queda como estaba.
func stop() -> void:
	play.props.clear_play_state()
	_regrow.clear()
	_growing.clear()
	_apple_wait.clear()
	_apple_index.clear()
	if _apples != null:
		_apples.queue_free()
		_apples = null
	for id: int in _overheads:
		if is_instance_valid(_overheads[id]):
			_overheads[id].queue_free()
	_overheads.clear()
	nearby_creature = null
	nearby_gather = {}
	if naming_actor != null:
		_close_naming()


# ================================================================ por cuadro

func tick(delta: float) -> void:
	var player_pos: Vector3 = play.player.body.pos
	_tick_regrow(delta)
	for id: int in _pet_wait.keys():
		_pet_wait[id] -= delta
		if _pet_wait[id] <= 0.0:
			_pet_wait.erase(id)
	var mount: EntityActor = play.player.mount
	var in_the_air: bool = mount != null and mount.flying
	nearby_creature = null
	var nearest: float = CREATURE_DISTANCE
	for actor: EntityActor in play.entities.actors():
		var dist: float = actor.body.pos.distance_to(player_pos)
		_refresh_overhead(actor, dist)
		if actor.is_npc() or actor.ridden:
			continue
		if dist < nearest and mount == null:
			nearest = dist
			nearby_creature = actor
		# Un seguidor que quedó muy atrás (o del otro lado del agua) aparece cerca.
		if actor.is_following() and not in_the_air:
			var flat: float = Vector2(actor.body.pos.x - player_pos.x, actor.body.pos.z - player_pos.z).length()
			var id: int = actor.get_instance_id()
			# También si lleva un rato sin poder acercarse (hay agua o un borde alto en el medio).
			var behind: float = _behind_time.get(id, 0.0) + delta if flat > BEHIND_DISTANCE else 0.0
			_behind_time[id] = behind
			if flat > CATCH_UP_DISTANCE or absf(actor.body.pos.y - player_pos.y) > 8.0 or behind > BEHIND_SECONDS:
				if catch_up(actor):
					_behind_time[id] = 0.0
	nearby_gather = {} if mount != null else _find_gatherable(player_pos)


func _tick_regrow(delta: float) -> void:
	for cell: Vector3i in _regrow.keys():
		_regrow[cell] -= delta
		if _regrow[cell] <= 0.0:
			_regrow.erase(cell)
			_growing[cell] = 0.0
			play.props.set_play_scale(cell, GROW_START_SCALE)
			play.props.set_play_hidden(cell, false)
	for cell: Vector3i in _growing.keys():
		_growing[cell] += delta / GROW_SECONDS
		if _growing[cell] >= 1.0:
			_growing.erase(cell)
			play.props.set_play_scale(cell, 1.0)
		else:
			play.props.set_play_scale(cell, lerpf(GROW_START_SCALE, 1.0, _growing[cell]))
	for cell: Vector3i in _apple_wait.keys():
		_apple_wait[cell] -= delta
		if _apple_wait[cell] <= 0.0:
			_apple_wait.erase(cell)
			_show_apple(cell, true)


# ================================================================ juntar

## ¿Falta que vuelva a crecer lo que había en esta celda?
func is_regrowing(cell: Vector3i) -> bool:
	return _regrow.has(cell) or _apple_wait.has(cell)


## Adelanta los relojes de todo lo que está por volver a crecer (para las pruebas).
func fast_forward(seconds: float) -> void:
	_tick_regrow(seconds)


func count(item: int) -> int:
	return backpack.get(Items.KEYS[item], 0)


func has_apple(oak_cell: Vector3i) -> bool:
	return _apple_index.has(oak_cell) and not _apple_wait.has(oak_cell)


## Busca lo más cercano que se pueda juntar: un prop juntable o la manzana de un roble.
func _find_gatherable(player_pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	var base := Vector3i(floori(player_pos.x), floori(player_pos.y + 0.05), floori(player_pos.z))
	var prop_cells: Dictionary[Vector3i, Dictionary] = play.props.props
	for dy: int in range(-1, 2):
		for dz: int in range(-2, 3):
			for dx: int in range(-2, 3):
				var cell: Vector3i = base + Vector3i(dx, dy, dz)
				if not prop_cells.has(cell):
					continue
				var id: int = prop_cells[cell]["id"]
				var flat: float = Vector2(cell.x + 0.5 - player_pos.x, cell.z + 0.5 - player_pos.z).length()
				var item: int = Items.item_for_prop(id)
				if item >= 0:
					if flat < GATHER_DISTANCE and flat < best_dist and not play.props.is_play_hidden(cell):
						best_dist = flat
						best = {"cell": cell, "item": item, "apple": false}
				elif id == PropLibrary.OAK and has_apple(cell) and flat < APPLE_DISTANCE and flat < best_dist:
					best_dist = flat
					best = {"cell": cell, "item": Items.APPLE, "apple": true}
	return best


## Junta lo que hay al alcance. Devuelve true si entró algo en la mochila.
func gather() -> bool:
	if nearby_gather.is_empty():
		return false
	var item: int = nearby_gather["item"]
	var cell: Vector3i = nearby_gather["cell"]
	if count(item) >= Items.CAP:
		play.show_notice("Ya llevas %d de %s" % [Items.CAP, Items.NAMES[item]])
		return false
	var wait: float = play.rng.randf_range(REGROW_MIN_SECONDS, REGROW_MAX_SECONDS)
	if nearby_gather["apple"]:
		_apple_wait[cell] = wait
		_show_apple(cell, false)
	else:
		play.props.set_play_hidden(cell, true)
		_regrow[cell] = wait
		_growing.erase(cell)
	backpack[Items.KEYS[item]] = count(item) + 1
	selected = item
	nearby_gather = {}
	progress_changed.emit()
	return true


# ---------------------------------------------------------------- manzanas

## Una manzana colgando de cada roble del mapa (un solo MultiMesh).
func _build_apples() -> void:
	_apple_index.clear()
	_apple_wait.clear()
	if _apples != null:
		_apples.queue_free()
		_apples = null
	for cell: Vector3i in play.props.props:
		if play.props.props[cell]["id"] == PropLibrary.OAK:
			_apple_index[cell] = _apple_index.size()
	if _apple_index.is_empty():
		return
	if _apple_mesh == null:
		_apple_mesh = PropLibrary.mesh_from_voxels(Items.apple_voxels(), play.library.material)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _apple_mesh
	mm.instance_count = _apple_index.size()
	_apples = MultiMeshInstance3D.new()
	_apples.multimesh = mm
	add_child(_apples)
	for cell: Vector3i in _apple_index:
		_show_apple(cell, true)


## Lugar de la manzana de un roble: colgando a un costado, por debajo de la copa.
static func apple_position(oak_cell: Vector3i) -> Vector3:
	var turn: float = ChunkMesher.cell_hash(oak_cell.x, oak_cell.y, oak_cell.z) * TAU
	return Vector3(oak_cell.x + 0.5 + cos(turn) * 0.8, oak_cell.y + 1.05, oak_cell.z + 0.5 + sin(turn) * 0.8)


func _show_apple(oak_cell: Vector3i, shown: bool) -> void:
	if _apples == null or not _apple_index.has(oak_cell):
		return
	var size: float = APPLE_SCALE if shown else 0.0
	var xform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), apple_position(oak_cell))
	_apples.multimesh.set_instance_transform(_apple_index[oak_cell], xform)


# ================================================================ amistad

## Comida que le daría el jugador a esta criatura: su preferida si la lleva, si no otra
## que acepte; -1 si no lleva nada que quiera.
func food_for(actor: EntityActor) -> int:
	var favourite: int = Items.favourite(actor.type)
	if favourite >= 0 and count(favourite) > 0:
		return favourite
	for item: int in Items.COUNT:
		if count(item) > 0 and Items.food_points(actor.type, item) > 0:
			return item
	return -1


## Tecla F: da de comer a la criatura cercana (o la acaricia si no hay nada que quiera).
## Devuelve qué pasó (una de las constantes de arriba).
func feed() -> String:
	var actor: EntityActor = nearby_creature
	if actor == null:
		return NOBODY
	var item: int = food_for(actor)
	if item >= 0:
		var points: int = Items.food_points(actor.type, item)
		backpack[Items.KEYS[item]] = count(item) - 1
		selected = item
		_add_points(actor, points, 4 if points >= Items.FAVOURITE_POINTS else 2)
		return FED_FAVOURITE if points >= Items.FAVOURITE_POINTS else FED_LIKED
	if count(selected) > 0:
		# Lleva algo en la mano, pero no es lo que quiere: dice que no y no se gasta.
		actor.shake_head()
		return REJECTED
	var id: int = actor.get_instance_id()
	if _pet_wait.has(id):
		return WAIT
	_pet_wait[id] = PET_COOLDOWN
	_add_points(actor, Items.PET_POINTS, 1)
	return PETTED


func _add_points(actor: EntityActor, points: int, hearts_shown: int) -> void:
	var before: int = actor.hearts()
	actor.add_friendship(points)
	burst(actor.body.pos + Vector3(0.0, actor.body.height + 0.2, 0.0), hearts_shown)
	if before < Items.HEARTS_FRIEND and actor.hearts() >= Items.HEARTS_FRIEND and str(actor.data["name"]).is_empty():
		offer_name(actor)
	progress_changed.emit()


## Unicornio y dragón solo se dejan montar por una amiga (2 corazones).
func can_mount(actor: EntityActor) -> bool:
	if actor.type == CharacterLibrary.UNICORN or actor.type == CharacterLibrary.DRAGON:
		return actor.hearts() >= Items.HEARTS_FRIEND
	return true


func follower_count() -> int:
	var total: int = 0
	for actor: EntityActor in play.entities.actors():
		if actor.is_following():
			total += 1
	return total


## Tecla G: le pide a la criatura amiga cercana que la siga, o que se quede.
## Devuelve true si cambió.
func toggle_follow() -> bool:
	var actor: EntityActor = nearby_creature
	if actor == null or actor.hearts() < Items.HEARTS_FRIEND:
		return false
	if not actor.is_following() and follower_count() >= MAX_FOLLOWERS:
		play.show_notice("Ya te siguen %d amigos" % MAX_FOLLOWERS)
		return false
	actor.set_following(not actor.is_following())
	progress_changed.emit()
	return true


## Trae a un seguidor a una celda libre cerca del jugador: con piso firme, sin agua y con
## lugar para su cuerpo. Si no hay ninguna (por ejemplo, el jugador nada lejos de la orilla),
## se queda donde está. Devuelve true si lo movió.
func catch_up(actor: EntityActor) -> bool:
	var player_pos: Vector3 = play.player.body.pos
	var world: VoxelWorld = play.world
	var base_y: int = floori(player_pos.y + 0.05)
	var probe := GridBody.new(actor.body.half, actor.body.height)
	var start: float = play.rng.randf_range(0.0, TAU)
	for radius: float in [2.0, 3.0, 4.0, 5.0]:
		for step: int in 8:
			var angle: float = start + float(step) * TAU / 8.0
			var x: int = floori(player_pos.x + cos(angle) * radius)
			var z: int = floori(player_pos.z + sin(angle) * radius)
			if x < 0 or z < 0 or x >= world.size_x or z >= world.size_z:
				continue
			for dy: int in [0, 1, -1, 2, -2]:
				var y: int = base_y + dy
				if not Blocks.is_solid(world.get_block_xyz(x, y - 1, z)) or world.get_block_xyz(x, y, z) != Blocks.AIR:
					continue
				probe.pos = Vector3(x + 0.5, y, z + 0.5)
				if probe.overlapping(world, play.props).is_empty():
					actor.body.teleport(probe.pos)
					actor.home = probe.pos
					actor.position = probe.pos
					return true
	return false


# ---------------------------------------------------------------- nombre

## Al hacerse amigas, se ofrece ponerle nombre. El juego espera hasta que se responda.
func offer_name(actor: EntityActor) -> void:
	naming_actor = actor
	var suggestion: String = Items.suggested_name(actor.type, play.rng.randi_range(0, 99))
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	if _name_dialog == null:
		_build_name_dialog()
	_name_dialog.title = "¡Nueva amiga!"
	_name_edit.text = suggestion
	if play.captures_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_name_dialog.popup_centered(Vector2i(380, 150))
	_name_edit.grab_focus()
	_name_edit.select_all()


func suggested_name_for(actor: EntityActor) -> String:
	return Items.suggested_name(actor.type, 0)


## Pone el nombre elegido (vacío = sin nombre) y sigue el juego.
func apply_name(text: String) -> void:
	if naming_actor != null:
		naming_actor.data["name"] = text.strip_edges().left(MAX_NAME_LENGTH)
		progress_changed.emit()
	_close_naming()


## "Más tarde": sigue el juego sin ponerle nombre.
func skip_name() -> void:
	_close_naming()


func _close_naming() -> void:
	naming_actor = null
	if _name_dialog != null and _name_dialog.visible:
		_name_dialog.hide()
	if play.active and play.captures_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_name_dialog() -> void:
	_name_dialog = ConfirmationDialog.new()
	_name_dialog.ok_button_text = "Aceptar"
	_name_dialog.cancel_button_text = "Más tarde"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "¿Cómo se va a llamar?"
	box.add_child(label)
	_name_edit = LineEdit.new()
	_name_edit.max_length = MAX_NAME_LENGTH
	_name_edit.custom_minimum_size = Vector2(320, 0)
	_name_edit.text_submitted.connect(func(text: String) -> void: apply_name(text))
	box.add_child(_name_edit)
	_name_dialog.add_child(box)
	_name_dialog.confirmed.connect(func() -> void: apply_name(_name_edit.text))
	_name_dialog.canceled.connect(skip_name)
	play.hud_root().add_child(_name_dialog)


# ================================================================ carteles y corazones

## Corazones, globo de comida y nombre sobre las criaturas cercanas.
func _refresh_overhead(actor: EntityActor, dist: float) -> void:
	var id: int = actor.get_instance_id()
	var near: bool = dist < OVERHEAD_DISTANCE and not actor.ridden and not actor.is_npc()
	if not near:
		if _overheads.has(id) and is_instance_valid(_overheads[id]):
			_overheads[id].visible = false
		return
	var overhead: EntityOverhead
	if _overheads.has(id) and is_instance_valid(_overheads[id]):
		overhead = _overheads[id]
	else:
		overhead = EntityOverhead.new()
		overhead.position = Vector3(0.0, actor.body.height + 0.45, 0.0)
		actor.add_child(overhead)
		_overheads[id] = overhead
	overhead.visible = true
	# El globo muestra su comida preferida mientras todavía falte amistad.
	var wanted: int = Items.favourite(actor.type) if actor.hearts() < Items.HEARTS_BEST else -1
	overhead.refresh(actor.hearts(), wanted, str(actor.data["name"]))


func overhead_of(actor: EntityActor) -> EntityOverhead:
	return _overheads.get(actor.get_instance_id())


## Lluvia de corazones sobre un punto.
func burst(at: Vector3, amount: int) -> void:
	if not is_inside_tree():
		return
	if _heart_material == null:
		_heart_material = StandardMaterial3D.new()
		_heart_material.albedo_texture = ImageTexture.create_from_image(Items.heart_image(true, 4))
		_heart_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_heart_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_heart_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_heart_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.3)
	quad.material = _heart_material
	var particles := CPUParticles3D.new()
	particles.mesh = quad
	particles.amount = maxi(amount * 3, 3)
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.lifetime = 1.1
	particles.direction = Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = 1.4
	particles.initial_velocity_max = 2.6
	particles.gravity = Vector3(0.0, -1.5, 0.0)
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.3
	particles.position = at
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(2.0).timeout.connect(particles.queue_free)
