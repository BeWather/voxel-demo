extends RefCounted
## Cuarta parte de la autoprueba: salir del agua, monturas, vuelo del dragón y la
## herramienta mover. La ejecuta tests/selftest.gd.

const STEP: float = 1.0 / 60.0

var checks: int = 0
var failures: int = 0
var _tree: SceneTree
var _library: CharacterLibrary = CharacterLibrary.new()


func run(tree: SceneTree) -> void:
	_tree = tree
	_test_water_exit()
	_test_riding()
	_test_dragon_flight()
	_test_move_tool()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		failures += 1
		print("  FALLA %s" % label)


func _flat_world(size: Vector3i, top: int) -> VoxelWorld:
	var world := VoxelWorld.new()
	_tree.get_root().add_child(world)
	world.clear(size)
	for z: int in size.z:
		for x: int in size.x:
			for y: int in top + 1:
				world.set_block_raw(x, y, z, Blocks.GRASS if y == top else Blocks.STONE)
	return world


func _fill(world: VoxelWorld, from: Vector3i, to: Vector3i, id: int) -> void:
	for y: int in range(from.y, to.y + 1):
		for z: int in range(from.z, to.z + 1):
			for x: int in range(from.x, to.x + 1):
				world.set_block_raw(x, y, z, id)


func _new_props() -> PropLayer:
	var props := PropLayer.new()
	props.library = PropLibrary.new("")
	_tree.get_root().add_child(props)
	return props


func _new_entities() -> EntityLayer:
	var entities := EntityLayer.new()
	entities.library = _library
	_tree.get_root().add_child(entities)
	return entities


func _new_play(world: VoxelWorld, props: PropLayer, entities: EntityLayer) -> PlayMode:
	var play := PlayMode.new()
	play.setup(world, props, entities, _library)
	_tree.get_root().add_child(play)
	return play


## Simula al jugador nadando hacia +X. Devuelve los segundos que tardó en quedar de pie
## sobre la orilla (a la altura `shore_y`, pasado x = `shore_x`), o -1 si no salió.
func _swim_out(player: Player, world: VoxelWorld, props: PropLayer, start: Vector3, shore_x: float,
		shore_y: float, jump: bool, seconds: float) -> float:
	player.place_at(start)
	# Primero se deja que se hunda o flote como corresponda.
	for i: int in 45:
		player.tick(STEP, world, props, Vector3.ZERO, jump, false)
	var steps: int = roundi(seconds / STEP)
	for i: int in steps:
		player.tick(STEP, world, props, Vector3.RIGHT, jump, false)
		if player.body.on_ground and player.body.pos.x > shore_x and is_equal_approx(player.body.pos.y, shore_y):
			return float(i + 1) * STEP
	return -1.0


func _test_water_exit() -> void:
	print("[salir del agua]")
	# Piso a y = 6. Tres piletas a lo largo de X, con la orilla en x = 10:
	#   z 2..5   agua de 1 de profundidad, orilla al ras del agua
	#   z 8..11  agua de 3 de profundidad, orilla al ras del agua
	#   z 14..17 agua de 3 de profundidad, orilla un bloque por encima del agua
	#   z 20..23 agua de 1 de profundidad, orilla un bloque por encima del agua
	var world: VoxelWorld = _flat_world(Vector3i(24, 16, 26), 5)
	_fill(world, Vector3i(4, 5, 2), Vector3i(9, 5, 5), Blocks.WATER)
	_fill(world, Vector3i(4, 3, 8), Vector3i(9, 5, 11), Blocks.WATER)
	_fill(world, Vector3i(4, 3, 14), Vector3i(9, 5, 17), Blocks.WATER)
	_fill(world, Vector3i(10, 6, 14), Vector3i(12, 6, 17), Blocks.GRASS)
	_fill(world, Vector3i(4, 5, 20), Vector3i(9, 5, 23), Blocks.WATER)
	_fill(world, Vector3i(10, 6, 20), Vector3i(12, 6, 23), Blocks.GRASS)
	var props: PropLayer = _new_props()
	var player := Player.new()
	_tree.get_root().add_child(player)

	var cases: Array[Dictionary] = [
		{"name": "agua de 1, orilla al ras", "z": 3.5, "bed": 5.0, "shore": 6.0},
		{"name": "agua de 3, orilla al ras", "z": 9.5, "bed": 3.0, "shore": 6.0},
		{"name": "agua de 3, orilla un bloque más alta", "z": 15.5, "bed": 3.0, "shore": 7.0},
		{"name": "agua de 1, orilla un bloque más alta", "z": 21.5, "bed": 5.0, "shore": 7.0},
	]
	for avatar: int in [0, 8]:
		var who: String = "niña" if CharacterLibrary.is_child_avatar(avatar) else "adulto"
		player.set_avatar(_library.get_avatar_parts(avatar), CharacterLibrary.avatar_body_height(avatar))
		for case: Dictionary in cases:
			var z: float = case["z"]
			var bed: float = case["bed"]
			var shore: float = case["shore"]
			var label: String = case["name"]
			# Antes: sin trepar, el impulso de nado no alcanza para subir a la orilla.
			player.mantle_enabled = false
			var old_time: float = _swim_out(player, world, props, Vector3(9.3, bed, z), 10.0, shore, true, 4.0)
			var old_top: float = bed
			player.place_at(Vector3(9.3, bed, z))
			for i: int in 240:
				player.tick(STEP, world, props, Vector3.RIGHT, true, false)
				old_top = maxf(old_top, player.body.pos.y)
			# Ahora: avanzar + Espacio saca del agua.
			player.mantle_enabled = true
			var new_time: float = _swim_out(player, world, props, Vector3(9.3, bed, z), 10.0, shore, true, 4.0)
			print("  %s, %s: antes llegaba a y = %.2f (orilla en %.0f); ahora sale en %.2f s" % [who, label, old_top, shore, new_time])
			_check(old_time < 0.0, "%s, %s: con el comportamiento anterior no salía" % [who, label])
			_check(new_time > 0.0 and new_time < 2.5, "%s, %s: avanzar + Espacio lo saca del agua" % [who, label])
			# Desde el medio de la pileta también, nadando hasta el borde.
			var far_time: float = _swim_out(player, world, props, Vector3(5.5, bed, z), 10.0, shore, true, 6.0)
			_check(far_time > 0.0, "%s, %s: también cruzando la pileta (%.2f s)" % [who, label, far_time])
		# En agua baja alcanza con avanzar, sin tocar Espacio.
		var walk_time: float = _swim_out(player, world, props, Vector3(8.5, 5.0, 3.5), 10.0, 6.0, false, 4.0)
		_check(walk_time > 0.0, "%s: en agua baja alcanza con caminar hacia la orilla (%.2f s)" % [who, walk_time])

	# El agua sigue siendo más lenta que caminar, y en tierra no se trepa nada.
	player.place_at(Vector3(4.6, 3.0, 9.5))
	for i: int in 60:
		player.tick(STEP, world, props, Vector3.ZERO, true, false)
	var x0: float = player.body.pos.x
	for i: int in 60:
		player.tick(STEP, world, props, Vector3.RIGHT, true, false)
	var swim_speed: float = player.body.pos.x - x0
	_check(swim_speed > 1.0 and swim_speed < Player.WALK_SPEED * 0.75, "nadar sigue siendo más lento que caminar (%.2f bloques/s)" % swim_speed)
	world.set_block_raw(10, 6, 12, Blocks.STONE)
	player.place_at(Vector3(8.5, 6.0, 12.5))
	for i: int in 120:
		player.tick(STEP, world, props, Vector3.RIGHT, true, false)
	_check(not player.is_mantling() and player.body.pos.x > 10.0,
			"en tierra firme no se trepa: hace falta el salto normal (y un bloque de 1 se salta)")
	for node: Node in [world, props, player]:
		node.queue_free()


func _test_riding() -> void:
	print("[montar]")
	# Piso a y = 4, una escalera que sube hacia +X, una pileta y un aldeano.
	var world: VoxelWorld = _flat_world(Vector3i(64, 24, 40), 3)
	for step: int in 5:
		_fill(world, Vector3i(30 + step * 3, 4, 2), Vector3i(63, 4 + step, 12), Blocks.GRASS)
	_fill(world, Vector3i(4, 2, 22), Vector3i(14, 3, 34), Blocks.WATER)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	var pony_cell := Vector3i(20, 4, 7)
	entities.set_entity(pony_cell, EntityLayer.make_entity(CharacterLibrary.PONY, 1, 1))
	entities.set_entity(Vector3i(20, 4, 20), EntityLayer.make_entity(CharacterLibrary.SHEEP, 0, 0))
	entities.set_entity(Vector3i(24, 4, 30), EntityLayer.make_entity(CharacterLibrary.VILLAGER, 0, 0, "Ramón", ["Hola."]))
	entities.set_entity(Vector3i(26, 4, 30), EntityLayer.make_entity(CharacterLibrary.UNICORN, 0, 0))
	var before: Dictionary = MapIO.serialize(world, props, 0, entities)
	var pony: EntityActor = entities.get_actor(pony_cell)
	var play: PlayMode = _new_play(world, props, entities)

	_check(pony.is_rideable() and entities.get_actor(Vector3i(26, 4, 30)).is_rideable()
			and not entities.get_actor(Vector3i(20, 4, 20)).is_rideable() and CharacterLibrary.is_rideable(CharacterLibrary.DRAGON)
			and CharacterLibrary.is_rideable(CharacterLibrary.COW) and not CharacterLibrary.is_rideable(CharacterLibrary.CHICKEN),
			"se montan el poni, el unicornio, el dragón y la vaca; los animales chicos no")
	for avatar: int in [0, 8]:
		var who: String = "niña" if CharacterLibrary.is_child_avatar(avatar) else "adulto"
		play.start(avatar, Vector3(21.8, 4.0, 7.5), false)
		play.rng.seed = 3
		play.simulate(STEP, Vector3.ZERO, false, false)
		_check(play.prompt_text().begins_with("E: montar"), "%s: cerca del poni aparece «%s»" % [who, play.prompt_text()])
		play.interact()
		_check(play.is_mounted() and pony.ridden and play.player.mount == pony, "%s: E lo monta" % who)
		play.simulate(STEP, Vector3.ZERO, false, false)
		# El jinete va sentado: la cadera apoya sobre el lomo, ni hundida ni flotando.
		var hip_y: float = play.player.position.y + CharacterLibrary.avatar_hip_height(avatar)
		var back_y: float = pony.body.pos.y + CharacterLibrary.seat_position(CharacterLibrary.PONY).y
		_check(hip_y >= back_y and hip_y <= back_y + 0.26 and play.player.rig.seated,
				"%s: va sentado sobre el lomo (cadera a %.2f, lomo a %.2f)" % [who, hip_y, back_y])
		_check(Vector2(play.player.position.x - pony.body.pos.x, play.player.position.z - pony.body.pos.z).length() < 0.4,
				"%s: centrado sobre la montura" % who)
		play.stop()
		entities.reset_actors()

	# Con el jugador encima, el poni no decide nada por su cuenta.
	play.start(0, Vector3(21.8, 4.0, 7.5), false)
	play.rng.seed = 3
	play.simulate(STEP, Vector3.ZERO, false, false)
	play.interact()
	var parked: Vector3 = pony.body.pos
	for i: int in 400:
		play.simulate(STEP, Vector3.ZERO, false, false)
	_check(pony.body.pos.is_equal_approx(parked) and pony.state == EntityActor.State.IDLE,
			"montado y sin tocar nada, el poni se queda quieto (su comportamiento está en pausa)")
	# Al paso y al galope va más rápido que el jugador a pie.
	var x0: float = pony.body.pos.x
	for i: int in 60:
		play.simulate(STEP, Vector3.LEFT, false, false)
	var walk: float = x0 - pony.body.pos.x
	x0 = pony.body.pos.x
	for i: int in 60:
		play.simulate(STEP, Vector3.LEFT, false, true)
	var gallop: float = x0 - pony.body.pos.x
	_check(walk > Player.WALK_SPEED and gallop > Player.RUN_SPEED and gallop > walk * 1.3,
			"al paso recorre %.1f bloques/s y al galope %.1f (a pie: %.1f y %.1f)" % [walk, gallop, Player.WALK_SPEED, Player.RUN_SPEED])
	# Sube sola una escalera de escalones de un bloque.
	var inside: int = 0
	for i: int in 700:
		play.simulate(STEP, Vector3.RIGHT, false, false)
		if not pony.body.overlapping(world, props).is_empty():
			inside += 1
	_check(pony.body.pos.y >= 8.99 and pony.body.pos.x > 44.0 and inside == 0,
			"sube los cinco escalones sin saltar (llegó a y = %.2f, x = %.1f)" % [pony.body.pos.y, pony.body.pos.x])
	_check(play.player.position.distance_to(pony.body.pos) < 2.2, "y el jinete sigue encima")
	# Espacio salta un bloque.
	pony.body.teleport(Vector3(27.5, 4.0, 7.5))
	world.set_block(Vector3i(24, 4, 7), Blocks.STONE)
	world.set_block(Vector3i(24, 5, 7), Blocks.AIR)
	var top_y: float = 0.0
	for i: int in 30:
		play.simulate(STEP, Vector3.ZERO, false, false)
	for i: int in 50:
		play.simulate(STEP, Vector3.ZERO, i < 5, false)
		top_y = maxf(top_y, pony.body.pos.y)
	_check(top_y > 5.2, "Espacio lo hace saltar más de un bloque (%.2f)" % (top_y - 4.0))
	world.set_block(Vector3i(24, 4, 7), Blocks.AIR)
	# No entra al agua ni sale del mapa.
	pony.body.teleport(Vector3(18.5, 4.0, 28.5))
	var wet: int = 0
	for i: int in 300:
		play.simulate(STEP, Vector3.LEFT, false, true)
		if pony.body.in_water or pony.body.pos.y < 3.99:
			wet += 1
	_check(wet == 0 and pony.body.pos.x > 15.0, "frena en la orilla: no entra al agua (x = %.2f)" % pony.body.pos.x)
	pony.body.teleport(Vector3(5.5, 4.0, 5.5))
	for i: int in 300:
		play.simulate(STEP, Vector3(-1.0, 0.0, -1.0).normalized(), false, true)
	_check(pony.body.pos.x >= 0.59 and pony.body.pos.z >= 0.59 and pony.body.pos.y >= 3.99 and play.player.respawn_count == 0,
			"en el borde del mapa frena en vez de caerse %s" % str(pony.body.pos))

	# Bajar: a una celda libre al lado, con piso firme.
	pony.body.teleport(Vector3(15.5, 4.0, 28.5))
	for i: int in 20:
		play.simulate(STEP, Vector3.ZERO, false, false)
	play.interact()
	var spot: Vector3 = play.player.body.pos
	_check(not play.is_mounted() and not pony.ridden and not play.player.rig.seated, "E otra vez lo baja")
	_check(Blocks.is_solid(world.get_block_xyz(floori(spot.x), floori(spot.y) - 1, floori(spot.z)))
			and world.get_block_xyz(floori(spot.x), floori(spot.y), floori(spot.z)) == Blocks.AIR
			and play.player.body.overlapping(world, props).is_empty(),
			"queda de pie en una celda libre con piso firme, no en el agua %s" % str(spot))
	_check(spot.distance_to(pony.body.pos) < 2.4 and spot.distance_to(pony.body.pos) > 0.6, "al lado de la montura (%.2f)" % spot.distance_to(pony.body.pos))
	_check(pony.home.is_equal_approx(pony.body.pos) and pony.home.distance_to(Vector3(20.5, 4.0, 7.5)) > 10.0,
			"el poni toma ese lugar como nuevo centro (no vuelve cruzando el mapa)")
	var left_at: Vector3 = pony.body.pos
	var farthest: float = 0.0
	var moved: bool = false
	for i: int in 1500:
		play.simulate(1.0 / 30.0, Vector3.ZERO, false, false)
		farthest = maxf(farthest, Vector2(pony.body.pos.x - left_at.x, pony.body.pos.z - left_at.z).length())
		if pony.state != EntityActor.State.IDLE:
			moved = true
	_check(moved and farthest > 0.5 and farthest <= EntityActor.LEASH + 0.3,
			"después retoma su paseo alrededor de ese lugar (se alejó %.2f)" % farthest)

	# Aldeano y montura cerca: el aviso es para el que está más cerca.
	play.player.body.teleport(Vector3(24.6, 4.0, 31.6))
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(play.prompt_text().begins_with("E: hablar"), "junto al aldeano: «%s»" % play.prompt_text())
	var unicorn: EntityActor = entities.get_actor(Vector3i(26, 4, 30))
	unicorn.body.teleport(Vector3(26.5, 4.0, 30.5))
	play.player.body.teleport(Vector3(26.4, 4.0, 31.7))
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(play.prompt_text().begins_with("E: montar"), "más cerca del unicornio: «%s»" % play.prompt_text())

	# Salir del juego montado: todo vuelve a su celda y el mapa no cambia.
	play.interact()
	_check(play.is_mounted(), "monta el unicornio")
	play.stop()
	entities.reset_actors()
	var displaced: int = 0
	for actor: EntityActor in entities.actors():
		if not actor.position.is_equal_approx(actor.home) or actor.ridden or actor.cell != Vector3i(floori(actor.home.x), floori(actor.home.y), floori(actor.home.z)):
			displaced += 1
	_check(displaced == 0 and not play.is_mounted(), "al salir del juego montado, cada criatura vuelve a su celda")
	world.set_block(Vector3i(24, 5, 7), Blocks.AIR)
	_check(MapIO.serialize(world, props, 0, entities) == before, "montar no modifica el mapa")
	for node: Node in [world, props, entities, play]:
		node.queue_free()


func _test_dragon_flight() -> void:
	print("[vuelo del dragón]")
	# Piso a y = 4, un muro alto de un bloque de espesor en x = 40, un árbol y una pileta.
	var world: VoxelWorld = _flat_world(Vector3i(64, 32, 48), 3)
	_fill(world, Vector3i(40, 4, 0), Vector3i(40, 31, 47), Blocks.STONE)
	_fill(world, Vector3i(4, 2, 30), Vector3i(11, 3, 44), Blocks.WATER)
	var props: PropLayer = _new_props()
	props.set_prop(Vector3i(26, 4, 12), PropLayer.make_prop(PropLibrary.OAK, 0, 0))
	var entities: EntityLayer = _new_entities()
	var cell := Vector3i(20, 4, 12)
	entities.set_entity(cell, EntityLayer.make_entity(CharacterLibrary.DRAGON, 1, 1))
	var dragon: EntityActor = entities.get_actor(cell)
	var play: PlayMode = _new_play(world, props, entities)
	play.start(0, Vector3(21.8, 4.0, 12.5), false)
	play.simulate(STEP, Vector3.ZERO, false, false)
	play.interact()
	_check(play.is_mounted() and dragon.can_fly() and not dragon.flying, "se monta el dragón; en el suelo camina")
	var x0: float = dragon.body.pos.x
	for i: int in 60:
		play.simulate(STEP, Vector3.LEFT, false, false)
	_check(not dragon.flying and x0 - dragon.body.pos.x > 2.0 and is_equal_approx(dragon.body.pos.y, 4.0),
			"camina por el suelo (%.1f bloques/s)" % (x0 - dragon.body.pos.x))

	# Espacio despega y sube; soltando todo planea a nivel; C baja; al tocar el suelo aterriza.
	for i: int in 90:
		play.simulate(STEP, Vector3.ZERO, true, false)
	var climbed: float = dragon.body.pos.y - 4.0
	_check(dragon.flying and climbed > 4.0, "Espacio despega y sube (%.1f bloques en 1,5 s)" % climbed)
	_check(dragon.rig.flight > 0.8, "las alas baten en vuelo")
	play.interact()
	_check(play.is_mounted() and play.prompt_text() == "Aterriza para bajar", "en el aire no se puede bajar: «%s»" % play.prompt_text())
	for i: int in 40:
		play.simulate(STEP, Vector3.ZERO, false, false)
	var level: float = dragon.body.pos.y
	for i: int in 120:
		play.simulate(STEP, Vector3.BACK, false, false)
	_check(absf(dragon.body.pos.y - level) < 0.05 and dragon.flying, "sin tocar nada planea a la misma altura")
	_check(play.player.position.y > dragon.body.pos.y + 0.8, "el jinete va encima también en vuelo")
	for i: int in 30:
		play.simulate(STEP, Vector3.ZERO, false, false, true)
	_check(dragon.body.pos.y < level - 1.0 and dragon.flying, "C baja")
	for i: int in 240:
		play.simulate(STEP, Vector3.ZERO, false, false, true)
	_check(not dragon.flying and dragon.body.on_ground and is_equal_approx(dragon.body.pos.y, 4.0), "al tocar el suelo aterriza")
	play.interact()
	_check(not play.is_mounted(), "ya en el suelo, E lo baja")
	play.player.body.teleport(dragon.body.pos + Vector3(1.4, 0.0, 0.0))
	play.simulate(STEP, Vector3.ZERO, false, false)
	play.interact()
	_check(play.is_mounted(), "y se puede volver a montar")

	# Techo de vuelo y borde del mapa.
	for i: int in 1500:
		play.simulate(STEP, Vector3(-1.0, 0.0, -1.0).normalized(), true, true)
	var ceiling: float = float(world.size_y) + EntityActor.FLY_CEILING_MARGIN
	_check(is_equal_approx(dragon.body.pos.y, ceiling), "no pasa del techo de vuelo (y = %.1f, límite %.0f)" % [dragon.body.pos.y, ceiling])
	_check(dragon.body.pos.x >= 0.59 and dragon.body.pos.z >= 0.59 and dragon.body.pos.x < 2.0 and dragon.flying
			and play.player.respawn_count == 0, "en el borde del mapa frena: no sale ni reaparece %s" % str(dragon.body.pos))

	# A toda velocidad contra un muro de un bloque de espesor: no lo atraviesa.
	dragon.body.teleport(Vector3(30.5, 12.0, 20.5))
	var inside: int = 0
	var fastest: float = 0.0
	for i: int in 400:
		play.simulate(1.0 / 20.0, Vector3.RIGHT, false, true)
		fastest = maxf(fastest, absf(dragon.body.vel.x))
		if not dragon.body.overlapping(world, props).is_empty():
			inside += 1
	_check(dragon.body.pos.x < 40.0 and inside == 0, "no atraviesa el terreno a velocidad de vuelo (frenó en x = %.2f)" % dragon.body.pos.x)
	# También choca con el tronco de un árbol.
	dragon.body.teleport(Vector3(22.5, 5.0, 12.5))
	for i: int in 200:
		play.simulate(STEP, Vector3.RIGHT, false, false)
	_check(dragon.body.pos.x < 26.3, "choca con el tronco de un árbol (x = %.2f)" % dragon.body.pos.x)

	# Sobre el agua no se hunde: queda al ras.
	dragon.body.teleport(Vector3(7.5, 9.0, 37.5))
	var sunk: int = 0
	for i: int in 300:
		play.simulate(STEP, Vector3.ZERO, false, false, true)
		if dragon.body.in_water or dragon.body.pos.y < 3.87:
			sunk += 1
	_check(sunk == 0 and dragon.body.pos.y < 4.1, "bajando sobre el agua queda al ras de la superficie (y = %.2f)" % dragon.body.pos.y)
	play.stop()
	entities.reset_actors()
	_check(dragon.position.is_equal_approx(dragon.home) and not dragon.flying and is_equal_approx(dragon.rig.flight, 0.0),
			"al salir del juego el dragón vuelve a su celda, en el suelo")
	for node: Node in [world, props, entities, play]:
		node.queue_free()


func _test_move_tool() -> void:
	print("[herramienta mover]")
	var world: VoxelWorld = _flat_world(Vector3i(32, 16, 32), 3)
	world.set_block_raw(12, 4, 12, Blocks.STONE)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	var controller := EditorController.new()
	controller.setup(world, props, null, entities)
	var pine := Vector3i(5, 4, 5)
	var npc := Vector3i(8, 4, 5)
	var pony := Vector3i(11, 4, 5)
	props.set_prop(pine, PropLayer.make_prop(PropLibrary.PINE, 2, 3))
	props.set_prop(Vector3i(20, 4, 20), PropLayer.make_prop(PropLibrary.ROCK, 1, 0))
	var npc_data: Dictionary = EntityLayer.make_entity(CharacterLibrary.VILLAGER, 2, 1, "Lucía", ["Uno.", "Dos."])
	entities.set_entity(npc, npc_data)
	entities.set_entity(pony, EntityLayer.make_entity(CharacterLibrary.PONY, 2, 0))
	var before: Dictionary = MapIO.serialize(world, props, 0, entities)
	_check(EditorController.TOOL_NAMES.size() == EditorController.TOOL_HINTS.size()
			and EditorController.TOOL_NAMES[EditorController.Tool.MOVE] == "Mover", "la herramienta Mover existe y todas tienen su explicación")

	# Prop.
	var pine_to := Vector3i(15, 4, 9)
	_check(controller.move_object(pine, pine_to), "mover un prop")
	_check(not props.has_prop(pine) and props.get_prop(pine_to) == PropLayer.make_prop(PropLibrary.PINE, 2, 3),
			"conserva tipo, variante y rotación")
	controller.undo()
	_check(MapIO.serialize(world, props, 0, entities) == before and not controller.can_undo(), "un solo deshacer lo devuelve")
	controller.redo()
	_check(props.has_prop(pine_to) and not props.has_prop(pine), "rehacer lo vuelve a mover")
	controller.undo()

	# Aldeano, con rotación nueva.
	var npc_to := Vector3i(9, 4, 14)
	_check(controller.move_object(npc, npc_to, 3), "mover un aldeano girándolo")
	var moved: Dictionary = entities.get_entity(npc_to)
	_check(not entities.has_entity(npc) and moved["name"] == "Lucía" and moved["lines"] == ["Uno.", "Dos."]
			and moved["variant"] == 2 and moved["rot"] == 3 and entities.get_actor(npc_to) != null,
			"conserva nombre, diálogo y aspecto, con la rotación nueva")
	controller.undo()
	_check(MapIO.serialize(world, props, 0, entities) == before and entities.get_entity(npc) == npc_data, "deshacer lo devuelve tal cual")

	# Animal.
	_check(controller.move_object(pony, Vector3i(12, 5, 12)) and entities.get_entity(Vector3i(12, 5, 12))["variant"] == 2,
			"mover un animal (a lo alto de un bloque), con su pelaje")
	controller.undo()

	# Destinos inválidos: no cambia nada ni queda un paso de deshacer.
	_check(not controller.move_object(pine, npc), "no se suelta sobre una criatura")
	_check(not controller.move_object(pony, Vector3i(20, 4, 20)), "ni sobre otro prop")
	_check(not controller.move_object(pine, Vector3i(6, 8, 6)), "ni en el aire")
	_check(not controller.move_object(pine, Vector3i(12, 4, 12)), "ni dentro de un bloque")
	_check(not controller.move_object(pine, Vector3i(40, 4, 5)), "ni fuera del mapa")
	_check(not controller.move_object(Vector3i(2, 4, 2), Vector3i(3, 4, 3)), "mover una celda vacía no hace nada")
	_check(not controller.move_object(pine, pine), "soltarlo donde estaba no cambia nada")
	_check(MapIO.serialize(world, props, 0, entities) == before and not controller.can_undo(), "tras los intentos inválidos todo sigue igual")
	# Girar en el lugar.
	_check(controller.move_object(pine, pine, 0) and props.get_prop(pine)["rot"] == 0, "soltarlo en su lugar con otra rotación lo gira")
	controller.undo()
	_check(MapIO.serialize(world, props, 0, entities) == before, "y se deshace")
	controller.free()
	for node: Node in [world, props, entities]:
		node.queue_free()
