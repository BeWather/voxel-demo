extends RefCounted
## Quinta parte de la autoprueba: juntar cosas, mochila, dar de comer, corazones de amistad
## y sus efectos, seguidores, y guardado del progreso (mapa versión 3).
## La ejecuta tests/selftest.gd; también se puede correr sola con tests/selftest_friends_only.gd.

const STEP: float = 1.0 / 60.0

var checks: int = 0
var failures: int = 0
var _tree: SceneTree
var _library: CharacterLibrary = CharacterLibrary.new()


func run(tree: SceneTree) -> void:
	_tree = tree
	_test_gathering()
	_test_feeding()
	_test_followers()
	_test_persistence()
	_test_editor_and_progress()


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


func _set_bag(play: PlayMode, contents: Dictionary) -> void:
	for key: String in Items.KEYS:
		play.friends.backpack[key] = int(contents.get(key, 0))


## Lleva al jugador a un punto y deja pasar un paso para que se actualicen los carteles.
func _go(play: PlayMode, point: Vector3) -> void:
	play.player.body.teleport(point)
	play.simulate(STEP, Vector3.ZERO, false, false)


func _test_gathering() -> void:
	print("[juntar y mochila]")
	var world: VoxelWorld = _flat_world(Vector3i(32, 16, 32), 3)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	var flower := Vector3i(5, 4, 5)
	var mushroom := Vector3i(9, 4, 5)
	var grass := Vector3i(13, 4, 5)
	var oak := Vector3i(20, 4, 12)
	props.set_prop(flower, PropLayer.make_prop(PropLibrary.FLOWER_RED, 1, 2))
	props.set_prop(mushroom, PropLayer.make_prop(PropLibrary.MUSHROOM, 0, 0))
	props.set_prop(grass, PropLayer.make_prop(PropLibrary.TALL_GRASS, 2, 1))
	props.set_prop(oak, PropLayer.make_prop(PropLibrary.OAK, 0, 0))
	props.set_prop(Vector3i(26, 4, 26), PropLayer.make_prop(PropLibrary.ROCK, 0, 0))
	props.rebuild_dirty()
	var before: Dictionary = MapIO.serialize(world, props, 0, entities)
	var play: PlayMode = _new_play(world, props, entities)
	play.start(0, Vector3(5.5, 4.0, 6.4), false)
	play.rng.seed = 11
	var friends: PlayFriends = play.friends
	play.simulate(STEP, Vector3.ZERO, false, false)

	_check(friends.icons.size() == Items.COUNT and friends.icons[Items.APPLE].get_width() == 32,
			"hay un ícono para cada una de las %d cosas" % Items.COUNT)
	_check(play.prompt_text() == "E: juntar flor roja", "junto a una flor: «%s»" % play.prompt_text())
	play.interact()
	_check(friends.count(Items.FLOWER_RED) == 1 and friends.selected == Items.FLOWER_RED, "E la junta: entra a la mochila y queda elegida")
	_check(props.is_play_hidden(flower) and friends.is_regrowing(flower), "la flor deja de verse y queda por volver a crecer")
	_check(props.get_prop(flower) == PropLayer.make_prop(PropLibrary.FLOWER_RED, 1, 2)
			and MapIO.serialize(world, props, 0, entities) == before, "los props del mapa no cambian")
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(play.prompt_text().is_empty(), "ya no hay nada que juntar ahí")
	props.rebuild_dirty()

	# Vuelve a crecer al rato, de a poco.
	friends.fast_forward(59.0)
	_check(props.is_play_hidden(flower), "a los 59 s todavía no volvió")
	var waited: float = 59.0
	while props.is_play_hidden(flower) and waited < 95.0:
		friends.fast_forward(0.25)
		waited += 0.25
	_check(not props.is_play_hidden(flower) and not friends.is_regrowing(flower) and waited <= 90.5,
			"entre los 60 y los 90 s vuelve a crecer (a los %.1f s)" % waited)
	_check(props.get("_play_scale").has(flower), "y aparece chiquita, creciendo")
	for i: int in 120:
		play.simulate(STEP, Vector3.ZERO, false, false)
	_check(not props.get("_play_scale").has(flower), "en un par de segundos llega a su tamaño")
	_check(play.prompt_text() == "E: juntar flor roja", "y se puede juntar otra vez")

	# Hongo, pasto alto y la manzana del roble.
	_go(play, Vector3(9.5, 4.0, 6.3))
	play.interact()
	_go(play, Vector3(13.5, 4.0, 6.3))
	play.interact()
	_check(friends.count(Items.MUSHROOM) == 1 and friends.count(Items.GRASS) == 1, "también se juntan hongos y pasto alto")
	_go(play, Vector3(26.5, 4.0, 27.4))
	_check(play.prompt_text().is_empty(), "una roca no se junta")
	_check(friends.has_apple(oak), "el roble tiene una manzana")
	_go(play, Vector3(21.6, 4.0, 12.5))
	_check(play.prompt_text() == "E: juntar manzana", "debajo del roble: «%s»" % play.prompt_text())
	play.interact()
	_check(friends.count(Items.APPLE) == 1 and not friends.has_apple(oak) and props.has_prop(oak) and not props.is_play_hidden(oak),
			"E junta la manzana; el árbol sigue en su lugar")
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(play.prompt_text().is_empty(), "el roble queda sin manzana por un rato")
	friends.fast_forward(95.0)
	_check(friends.has_apple(oak), "y después le sale otra")

	# Tope de la mochila.
	_set_bag(play, {"flor_roja": Items.CAP})
	_go(play, Vector3(5.5, 4.0, 6.4))
	play.interact()
	_check(friends.count(Items.FLOWER_RED) == Items.CAP and not props.is_play_hidden(flower), "con %d de una cosa no entra más" % Items.CAP)
	_check(play.prompt_text().begins_with("Ya llevas"), "y avisa: «%s»" % play.prompt_text())

	# Teclas 1 a 6: el casillero elegido.
	var hud := BackpackHud.new()
	hud.setup(friends.icons)
	hud.refresh(friends.backpack)
	hud.select(3)
	_check(hud.selected() == 3 and hud.shown_count(0) == Items.CAP and hud.get_child_count() == Items.COUNT, "la fila de la mochila muestra las cantidades")
	hud.free()

	# Al salir, el mapa se ve y queda exactamente como estaba; la mochila se conserva.
	_go(play, Vector3(13.5, 4.0, 6.3))
	_set_bag(play, {"pasto": 2})
	friends.fast_forward(200.0)
	play.simulate(STEP, Vector3.ZERO, false, false)
	play.interact()
	_check(props.is_play_hidden(grass), "se junta algo justo antes de salir")
	play.stop()
	entities.reset_actors()
	var hidden: int = 0
	for cell: Vector3i in props.props:
		if props.is_play_hidden(cell):
			hidden += 1
	_check(hidden == 0 and props.get("_play_scale").is_empty(), "al volver al editor todo vuelve a verse")
	_check(MapIO.serialize(world, props, 0, entities) == before, "y el mapa es idéntico al de antes de jugar")
	_check(friends.count(Items.GRASS) == 3, "la mochila conserva lo juntado")
	for node: Node in [world, props, entities, play]:
		node.queue_free()


func _test_feeding() -> void:
	print("[dar de comer y corazones]")
	_check(Items.food_points(CharacterLibrary.SHEEP, Items.GRASS) == Items.FAVOURITE_POINTS
			and Items.food_points(CharacterLibrary.SHEEP, Items.FLOWER_YELLOW) == Items.LIKED_POINTS
			and Items.food_points(CharacterLibrary.SHEEP, Items.APPLE) == 0, "la oveja prefiere el pasto, acepta flor amarilla y no quiere manzana")
	var all_have_food: bool = true
	for type: int in CharacterLibrary.ENTITY_COUNT:
		if type != CharacterLibrary.VILLAGER and Items.favourite(type) < 0:
			all_have_food = false
	_check(all_have_food and Items.favourite(CharacterLibrary.VILLAGER) < 0, "todos los animales tienen una comida preferida; el aldeano no")
	_check(Items.hearts_for(0) == 0 and Items.hearts_for(3) == 0 and Items.hearts_for(4) == 1 and Items.hearts_for(8) == 2
			and Items.hearts_for(12) == 3 and Items.hearts_for(99) == 3, "cada 4 puntos es un corazón, hasta 3")

	var world: VoxelWorld = _flat_world(Vector3i(48, 16, 48), 3)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	var sheep_cell := Vector3i(10, 4, 10)
	entities.set_entity(sheep_cell, EntityLayer.make_entity(CharacterLibrary.SHEEP, 0, 0))
	var sheep: EntityActor = entities.get_actor(sheep_cell)
	var play: PlayMode = _new_play(world, props, entities)
	var friends: PlayFriends = play.friends
	var changes: Array[int] = [0]
	friends.progress_changed.connect(func() -> void: changes[0] += 1)
	play.start(0, Vector3(11.8, 4.0, 10.5), false)
	play.rng.seed = 4
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(friends.nearby_creature == sheep and play.prompt_text() == "F: acariciar", "junto a la oveja con la mochila vacía: «%s»" % play.prompt_text())
	var overhead: EntityOverhead = friends.overhead_of(sheep)
	_check(overhead != null and overhead.visible and overhead.shown_hearts() == 0 and overhead.shows_bubble(),
			"sobre la oveja se ven sus corazones (vacíos) y el globo con lo que quiere")

	# Acariciar: da poco y hay que esperar para repetir.
	_check(friends.feed() == PlayFriends.PETTED and sheep.friendship() == 1, "F con las manos vacías la acaricia (+1)")
	_check(friends.feed() == PlayFriends.WAIT and sheep.friendship() == 1, "enseguida otra vez no suma")
	for i: int in 400:
		play.simulate(STEP, Vector3.ZERO, false, false)
		sheep.body.teleport(sheep.home)
	_check(friends.feed() == PlayFriends.PETTED and sheep.friendship() == 2, "pasados unos segundos, sí")

	# Algo que no quiere: dice que no y no se gasta.
	_set_bag(play, {"manzana": 2})
	friends.selected = Items.APPLE
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(friends.food_for(sheep) < 0 and friends.feed() == PlayFriends.REJECTED and friends.count(Items.APPLE) == 2
			and sheep.friendship() == 2, "una manzana no la quiere: no se gasta ni suma")
	# Algo que acepta y su comida preferida.
	_set_bag(play, {"manzana": 2, "flor_amarilla": 1})
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(play.prompt_text() == "F: dar flor amarilla", "el cartel dice qué le va a dar: «%s»" % play.prompt_text())
	_check(friends.feed() == PlayFriends.FED_LIKED and friends.count(Items.FLOWER_YELLOW) == 0 and sheep.friendship() == 4
			and sheep.hearts() == 1, "una flor amarilla la acepta (+2): primer corazón")
	_set_bag(play, {"manzana": 2, "pasto": 3, "flor_amarilla": 4})
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(friends.food_for(sheep) == Items.GRASS and play.prompt_text() == "F: dar pasto", "si lleva su comida preferida, le da esa")
	_check(friends.feed() == PlayFriends.FED_FAVOURITE and friends.count(Items.GRASS) == 2 and sheep.friendship() == 8
			and sheep.hearts() == 2, "el pasto es su preferido (+4): segundo corazón")
	_check(changes[0] >= 4, "cada avance avisa que hay progreso para guardar (%d avisos)" % changes[0])

	# Al llegar a 2 corazones se ofrece ponerle nombre; mientras tanto el juego espera.
	_check(friends.naming_actor == sheep and play.is_dialog_open(), "al hacerse amigas se ofrece ponerle nombre")
	_check(not Items.suggested_name(CharacterLibrary.SHEEP, 0).is_empty(), "con un nombre sugerido (%s)" % Items.suggested_name(CharacterLibrary.SHEEP, 0))
	var held: Vector3 = play.player.body.pos
	for i: int in 30:
		play.simulate(STEP, Vector3.RIGHT, true, true)
	_check(play.player.body.pos.is_equal_approx(held), "con la ventana abierta el jugador no se mueve")
	friends.apply_name("  Nube  ")
	_check(sheep.data["name"] == "Nube" and sheep.display_name() == "Nube" and friends.naming_actor == null and not play.is_dialog_open(),
			"Aceptar le pone el nombre y sigue el juego")
	_check(entities.get_entity(sheep_cell)["name"] == "Nube" and entities.get_entity(sheep_cell)["friendship"] == 8,
			"el nombre y la amistad quedan en los datos de la criatura")
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(overhead.shown_hearts() == 2, "arriba se ven dos corazones")
	# "Más tarde" no pone nombre y no vuelve a preguntar por comida de más.
	_check(friends.feed() == PlayFriends.FED_FAVOURITE and sheep.hearts() == 3 and friends.naming_actor == null,
			"con tres corazones no vuelve a preguntar")
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(overhead.shown_hearts() == 3 and not overhead.shows_bubble(), "con tres corazones ya no pide comida")
	_check(friends.feed() == PlayFriends.FED_FAVOURITE and sheep.friendship() == Items.MAX_POINTS, "la amistad no pasa del máximo")

	# Un corazón alcanza para que una gallina deje de huir.
	var hen_cell := Vector3i(30, 4, 30)
	entities.set_entity(hen_cell, EntityLayer.make_entity(CharacterLibrary.CHICKEN, 0, 0))
	var hen: EntityActor = entities.get_actor(hen_cell)
	_go(play, Vector3(31.6, 4.0, 30.5))
	var fled: bool = false
	for i: int in 120:
		play.simulate(STEP, Vector3.ZERO, false, false)
		if hen.state == EntityActor.State.FLEE:
			fled = true
	_check(fled, "una gallina que no la conoce huye")
	hen.body.teleport(hen.home)
	hen.state = EntityActor.State.IDLE
	hen.add_friendship(Items.FAVOURITE_POINTS)
	fled = false
	for i: int in 400:
		play.simulate(STEP, Vector3.ZERO, false, false)
		play.player.body.teleport(hen.body.pos + Vector3(1.2, 0.0, 0.0))
		if hen.state == EntityActor.State.FLEE:
			fled = true
	_check(not fled and hen.hearts() == 1, "con un corazón ya no huye aunque la tenga al lado")

	# Unicornio y dragón: primero amigas, después se dejan montar. El poni no cambia.
	var uni_cell := Vector3i(20, 4, 38)
	var pony_cell := Vector3i(26, 4, 38)
	entities.set_entity(uni_cell, EntityLayer.make_entity(CharacterLibrary.UNICORN, 0, 0))
	entities.set_entity(pony_cell, EntityLayer.make_entity(CharacterLibrary.PONY, 0, 0))
	var unicorn: EntityActor = entities.get_actor(uni_cell)
	var pony: EntityActor = entities.get_actor(pony_cell)
	_set_bag(play, {})
	_go(play, Vector3(21.7, 4.0, 38.5))
	_check(play.prompt_text().begins_with(PlayMode.BEFRIEND_FIRST), "junto a un unicornio que no la conoce: «%s»" % play.prompt_text())
	play.interact()
	_check(not play.is_mounted(), "E no lo monta todavía")
	play.set("_notice_time", 0.0)
	_check(friends.overhead_of(unicorn) != null and friends.overhead_of(unicorn).shows_bubble(), "y el globo muestra qué quiere comer")
	_check(not play.mount(unicorn), "tampoco llamando a montar directamente")
	_set_bag(play, {"manzana": 2})
	unicorn.body.teleport(unicorn.home)
	_go(play, Vector3(21.7, 4.0, 38.5))
	friends.feed()
	unicorn.body.teleport(unicorn.home)
	_go(play, Vector3(21.7, 4.0, 38.5))
	friends.feed()
	_check(unicorn.hearts() == 2 and friends.naming_actor == unicorn, "dos manzanas después son amigas")
	friends.skip_name()
	_check(str(unicorn.data["name"]).is_empty() and not play.is_dialog_open(), "«Más tarde» sigue sin ponerle nombre")
	unicorn.body.teleport(unicorn.home)
	_go(play, Vector3(21.7, 4.0, 38.5))
	_check(play.prompt_text().begins_with("E: montar (unicornio)"), "ahora sí: «%s»" % play.prompt_text())
	play.interact()
	_check(play.is_mounted() and play.player.mount == unicorn, "E monta al unicornio amigo")
	play.interact()
	pony.body.teleport(pony.home)
	_go(play, Vector3(27.7, 4.0, 38.5))
	_check(pony.hearts() == 0 and play.prompt_text().begins_with("E: montar (poni)"), "el poni se monta sin ser amigas, como antes")
	play.interact()
	_check(play.is_mounted() and play.player.mount == pony, "E monta al poni")
	_check(not friends.can_mount(entities.get_actor(sheep_cell)) or not entities.get_actor(sheep_cell).is_rideable(), "la oveja sigue sin montarse")
	play.stop()
	entities.reset_actors()
	_check(sheep.friendship() == Items.MAX_POINTS and sheep.data["name"] == "Nube" and unicorn.hearts() == 2,
			"al volver al editor la amistad y el nombre se conservan")
	for node: Node in [world, props, entities, play]:
		node.queue_free()


func _test_followers() -> void:
	print("[seguidores]")
	# Piso a y = 4 con una pileta ancha y una isla de piedra en el medio.
	var world: VoxelWorld = _flat_world(Vector3i(96, 20, 64), 3)
	_fill(world, Vector3i(40, 2, 8), Vector3i(64, 3, 56), Blocks.WATER)
	_fill(world, Vector3i(51, 2, 30), Vector3i(53, 3, 32), Blocks.STONE)
	_fill(world, Vector3i(20, 4, 40), Vector3i(24, 6, 44), Blocks.STONE)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	var sheep_cell := Vector3i(10, 4, 10)
	entities.set_entity(sheep_cell, EntityLayer.make_entity(CharacterLibrary.SHEEP, 0, 0, "", [], 4))
	var sheep: EntityActor = entities.get_actor(sheep_cell)
	var play: PlayMode = _new_play(world, props, entities)
	var friends: PlayFriends = play.friends
	play.start(0, Vector3(11.8, 4.0, 10.5), false)
	play.rng.seed = 21
	play.simulate(STEP, Vector3.ZERO, false, false)

	_check(not friends.toggle_follow() and not sheep.is_following(), "con un corazón todavía no la sigue")
	_check(not play.prompt_text().contains("G:"), "y el cartel no ofrece la tecla G")
	sheep.add_friendship(4)
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(play.prompt_text().contains("G: que te siga"), "con dos corazones aparece «G: que te siga»")
	_check(friends.toggle_follow() and sheep.is_following() and entities.get_entity(sheep_cell)["follow"] == true, "G hace que la siga")
	play.simulate(STEP, Vector3.ZERO, false, false)
	_check(play.prompt_text().contains("G: que se quede"), "y ahora ofrece «G: que se quede»")

	# Caminando y corriendo, la oveja no se queda atrás.
	var inside: int = 0
	var worst: float = 0.0
	for i: int in 300:
		play.simulate(STEP, Vector3.BACK, false, i > 120)
		worst = maxf(worst, sheep.body.pos.distance_to(play.player.body.pos))
		if not sheep.body.overlapping(world, props).is_empty():
			inside += 1
	for i: int in 90:
		play.simulate(STEP, Vector3.ZERO, false, false)
	var gap: float = sheep.body.pos.distance_to(play.player.body.pos)
	_check(play.player.body.pos.z > 30.0 and gap < 3.2 and worst < 7.0 and inside == 0,
			"sigue al jugador al caminar y al correr (queda a %.1f; lo más lejos, %.1f)" % [gap, worst])
	_check(gap > 0.9, "sin pegarse encima")
	_check(sheep.home.distance_to(sheep.body.pos) < 0.5, "su lugar pasa a ser donde está")

	# No entra al agua: se queda en la orilla.
	_go(play, Vector3(38.5, 4.0, 30.5))
	sheep.body.teleport(Vector3(36.5, 4.0, 30.5))
	var wet: int = 0
	for i: int in 240:
		play.simulate(STEP, Vector3.RIGHT, true, false)
		if sheep.body.in_water or sheep.body.pos.y < 3.99:
			wet += 1
	_check(play.player.body.pos.x > 41.0 and wet == 0 and sheep.body.pos.x < 40.0, "si el jugador nada, la oveja se queda en la orilla")
	# Lejos de la orilla no hay dónde aparecer: espera.
	_go(play, Vector3(46.5, 3.4, 20.5))
	var waiting: Vector3 = sheep.body.pos
	for i: int in 60:
		play.simulate(STEP, Vector3.ZERO, true, false)
	_check(not friends.catch_up(sheep) and sheep.body.pos.x < 40.0 and waiting.x < 40.0 and not sheep.body.in_water,
			"nadando lejos de la orilla no hay dónde traerla: espera en tierra")
	# Al llegar a tierra (una isla en medio del agua), aparece en una celda válida cerca.
	_go(play, Vector3(52.5, 4.0, 31.5))
	for i: int in 330:
		play.simulate(STEP, Vector3.ZERO, false, false)
	var spot: Vector3 = sheep.body.pos
	_check(spot.distance_to(play.player.body.pos) < 6.0, "si quedó muy atrás, aparece cerca del jugador (a %.1f)" % spot.distance_to(play.player.body.pos))
	_check(Blocks.is_solid(world.get_block_xyz(floori(spot.x), floori(spot.y) - 1, floori(spot.z)))
			and world.get_block_xyz(floori(spot.x), floori(spot.y), floori(spot.z)) == Blocks.AIR
			and sheep.body.overlapping(world, props).is_empty() and not sheep.body.in_water,
			"en una celda con piso firme, fuera del agua y sin quedar dentro de un bloque %s" % str(spot))
	# Junto a un bloque macizo tampoco queda adentro.
	_go(play, Vector3(19.4, 4.0, 42.5))
	sheep.body.teleport(Vector3(80.5, 4.0, 50.5))
	var clean: bool = true
	for attempt: int in 12:
		sheep.body.teleport(Vector3(80.5, 4.0, 50.5))
		play.simulate(STEP, Vector3.ZERO, false, false)
		if not sheep.body.overlapping(world, props).is_empty() or sheep.body.pos.distance_to(play.player.body.pos) > 6.0:
			clean = false
	_check(clean, "doce veces junto a un bloque de piedra: nunca aparece dentro")

	# Después de volar en dragón, los seguidores alcanzan al jugador cuando aterriza.
	var dragon_cell := Vector3i(70, 4, 20)
	entities.set_entity(dragon_cell, EntityLayer.make_entity(CharacterLibrary.DRAGON, 0, 0, "", [], 8))
	var dragon: EntityActor = entities.get_actor(dragon_cell)
	sheep.body.teleport(Vector3(72.5, 4.0, 22.5))
	_go(play, Vector3(71.7, 4.0, 20.5))
	_check(play.mount(dragon), "monta al dragón amigo")
	for i: int in 240:
		play.simulate(STEP, Vector3(-1.0, 0.0, 0.6).normalized(), i < 60, true)
	var in_flight: float = sheep.body.pos.distance_to(play.player.body.pos)
	_check(dragon.flying and in_flight > PlayFriends.CATCH_UP_DISTANCE, "en vuelo la oveja queda atrás (a %.0f) y no aparece en el aire" % in_flight)
	for i: int in 300:
		play.simulate(STEP, Vector3.ZERO, false, false, true)
	_check(not dragon.flying and sheep.body.pos.distance_to(play.player.body.pos) < 6.5
			and sheep.body.overlapping(world, props).is_empty() and sheep.body.pos.y >= 3.99,
			"al aterrizar aparece cerca (a %.1f)" % sheep.body.pos.distance_to(play.player.body.pos))
	play.interact()

	# G otra vez: se queda.
	sheep.body.teleport(play.player.body.pos + Vector3(1.5, 0.0, 0.0))
	play.simulate(STEP, Vector3.ZERO, false, false)
	friends.nearby_creature = sheep
	_check(friends.toggle_follow() and not sheep.is_following(), "G otra vez: se queda")
	var stay: Vector3 = sheep.body.pos
	_go(play, stay + Vector3(14.0, 0.0, 0.0))
	for i: int in 200:
		play.simulate(STEP, Vector3.ZERO, false, false)
	_check(sheep.body.pos.distance_to(stay) < EntityActor.LEASH + 0.5, "y ya no va detrás del jugador")

	# Como mucho cuatro seguidores a la vez.
	var followers: int = 0
	for i: int in 5:
		var cell := Vector3i(8 + i * 2, 4, 56)
		entities.set_entity(cell, EntityLayer.make_entity(CharacterLibrary.PIG, 0, 0, "", [], 8))
		friends.nearby_creature = entities.get_actor(cell)
		if friends.toggle_follow():
			followers += 1
	_check(followers == PlayFriends.MAX_FOLLOWERS and friends.follower_count() == PlayFriends.MAX_FOLLOWERS,
			"el quinto amigo no se suma: como mucho %d seguidores" % PlayFriends.MAX_FOLLOWERS)
	_check(play.prompt_text().begins_with("Ya te siguen"), "y avisa: «%s»" % play.prompt_text())
	play.stop()
	entities.reset_actors()
	_check(sheep.position.is_equal_approx(Vector3(10.5, 4.0, 10.5)) and sheep.home.is_equal_approx(Vector3(10.5, 4.0, 10.5)),
			"al volver al editor cada criatura está en su celda")
	for node: Node in [world, props, entities, play]:
		node.queue_free()


func _test_persistence() -> void:
	print("[guardar el progreso: mapa versión 3]")
	var world: VoxelWorld = _flat_world(Vector3i(16, 16, 16), 3)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	entities.set_entity(Vector3i(3, 4, 3), EntityLayer.make_entity(CharacterLibrary.SHEEP, 0, 1, "Nube", [], 9, true))
	entities.set_entity(Vector3i(6, 4, 3), EntityLayer.make_entity(CharacterLibrary.DRAGON, 1, 2, "", [], 3, false))
	entities.set_entity(Vector3i(9, 4, 3), EntityLayer.make_entity(CharacterLibrary.VILLAGER, 1, 0, "Ramón", ["Hola."]))
	var bag: Dictionary = {"flor_roja": 2, "manzana": 20, "pasto": 7, "cosa_rara": 5}
	var data: Dictionary = MapIO.serialize(world, props, 5, entities, bag)
	_check(data["version"] == 3 and MapIO.VERSION == 3, "el mapa se guarda como versión 3")
	_check(data["backpack"]["manzana"] == 20 and data["backpack"]["pasto"] == 7 and data["backpack"]["hongo"] == 0
			and not data["backpack"].has("cosa_rara"), "con la mochila (solo las cosas conocidas)")
	MapIO.ensure_maps_dir()
	var path: String = MapIO.MAPS_DIR + "/_autoprueba_v3.json"
	_check(MapIO.save_file(path, world, props, 5, entities, bag).is_empty(), "guardar")
	var world2: VoxelWorld = _flat_world(Vector3i(16, 16, 16), 1)
	var props2: PropLayer = _new_props()
	var entities2: EntityLayer = _new_entities()
	var result: Dictionary = MapIO.load_file(path, world2, props2, entities2)
	DirAccess.remove_absolute(path)
	_check(result["ok"], "cargar (%s)" % str(result["error"]))
	var sheep: Dictionary = entities2.get_entity(Vector3i(3, 4, 3))
	_check(sheep["friendship"] == 9 and sheep["name"] == "Nube" and sheep["follow"] == true, "la oveja vuelve con sus corazones, su nombre y siguiendo")
	_check(entities2.get_entity(Vector3i(6, 4, 3))["friendship"] == 3 and entities2.get_entity(Vector3i(6, 4, 3))["follow"] == false,
			"el dragón, con sus puntos")
	_check(entities2.entities == entities.entities, "todas las criaturas coinciden")
	var loaded_bag: Dictionary = result["backpack"]
	_check(loaded_bag["manzana"] == 20 and loaded_bag["flor_roja"] == 2 and loaded_bag["pasto"] == 7 and loaded_bag.size() == Items.COUNT,
			"la mochila vuelve igual")
	_check(MapIO.serialize(world2, props2, 5, entities2, loaded_bag) == data, "volver a serializar da lo mismo")
	_check(entities2.get_actor(Vector3i(3, 4, 3)).is_following() and entities2.get_actor(Vector3i(3, 4, 3)).hearts() == 2,
			"y la criatura cargada se comporta como amiga")

	# Mapas de versiones anteriores: sin amistad, sin nombre de mascota y con la mochila vacía.
	result = MapIO.load_file("res://tests/fixtures/mapa_v2.json", world2, props2, entities2)
	_check(result["ok"] and entities2.entities.size() == 3, "un mapa de la versión 2 se carga (%s)" % str(result["error"]))
	var old_sheep: Dictionary = entities2.get_entity(Vector3i(6, 2, 6))
	_check(old_sheep["friendship"] == 0 and old_sheep["follow"] == false and old_sheep["name"] == "", "sus animales arrancan sin amistad")
	_check(entities2.get_entity(Vector3i(9, 2, 9))["name"] == "Marta" and entities2.get_entity(Vector3i(9, 2, 9))["lines"] == ["Hola."],
			"el aldeano conserva su nombre y su diálogo")
	var old_bag: Dictionary = result["backpack"]
	var total: int = 0
	for key: String in Items.KEYS:
		total += int(old_bag[key])
	_check(old_bag.size() == Items.COUNT and total == 0, "y la mochila está vacía")
	result = MapIO.load_file("res://tests/fixtures/mapa_v1.json", world2, props2, entities2)
	_check(result["ok"] and entities2.entities.is_empty() and result["backpack"]["manzana"] == 0, "un mapa de la versión 1 también se carga")
	var future: Dictionary = data.duplicate(true)
	future["version"] = 4
	result = MapIO.deserialize(future, world2, props2, entities2)
	_check(not result["ok"] and str(result["error"]).contains("4"), "una versión desconocida se rechaza: %s" % str(result["error"]))
	var odd: Dictionary = data.duplicate(true)
	odd["backpack"] = {"manzana": 999, "pasto": -3, "hongo": "muchos"}
	odd["entities"][0]["friendship"] = 500
	result = MapIO.deserialize(odd, world2, props2, entities2)
	_check(result["ok"] and result["backpack"]["manzana"] == Items.CAP and result["backpack"]["pasto"] == 0
			and result["backpack"]["hongo"] == 0, "cantidades raras en la mochila se acomodan")
	var capped: int = 0
	for cell: Vector3i in entities2.entities:
		capped = maxi(capped, entities2.entities[cell]["friendship"])
	_check(capped == Items.MAX_POINTS, "y la amistad no pasa del máximo")
	for node: Node in [world, props, entities, world2, props2, entities2]:
		node.queue_free()


func _test_editor_and_progress() -> void:
	print("[el progreso en el editor]")
	var world: VoxelWorld = _flat_world(Vector3i(32, 16, 32), 3)
	var props: PropLayer = _new_props()
	var entities: EntityLayer = _new_entities()
	var controller := EditorController.new()
	controller.setup(world, props, null, entities)
	var edits: Array[int] = [0]
	controller.edited.connect(func() -> void: edits[0] += 1)
	var home := Vector3i(5, 4, 5)
	var away := Vector3i(12, 4, 9)
	controller.apply_entity(home, EntityLayer.make_entity(CharacterLibrary.RABBIT, 0, 1))
	_check(edits[0] == 1 and controller.can_undo(), "colocar una criatura es una edición (un paso de deshacer)")
	controller.clear_history()

	# El progreso del juego cambia los datos de la criatura sin pasar por el historial.
	var play: PlayMode = _new_play(world, props, entities)
	play.start(0, Vector3(6.8, 4.0, 5.5), false)
	play.simulate(STEP, Vector3.ZERO, false, false)
	_set_bag(play, {"flor_amarilla": 3})
	play.simulate(STEP, Vector3.ZERO, false, false)
	play.friends.feed()
	entities.get_actor(home).body.teleport(Vector3(5.5, 4.0, 5.5))
	play.simulate(STEP, Vector3.ZERO, false, false)
	play.friends.feed()
	play.friends.apply_name("Canela")
	play.stop()
	entities.reset_actors()
	var friend: Dictionary = entities.get_entity(home)
	_check(friend["friendship"] == 8 and friend["name"] == "Canela", "jugando, el conejo llegó a dos corazones y tiene nombre")
	_check(not controller.can_undo() and not controller.can_redo() and edits[0] == 1, "eso no es un paso de deshacer ni una edición")

	# Mover conserva la amistad y el nombre.
	_check(controller.move_object(home, away, 3), "mover al conejo")
	var moved: Dictionary = entities.get_entity(away)
	_check(moved["friendship"] == 8 and moved["name"] == "Canela" and moved["rot"] == 3 and entities.get_actor(away).hearts() == 2,
			"conserva sus corazones y su nombre")
	# Si después gana amistad y se deshace el movimiento, vuelve a su lugar con la amistad de ahora.
	entities.get_actor(away).add_friendship(4)
	controller.undo()
	var back: Dictionary = entities.get_entity(home)
	_check(not entities.has_entity(away) and back["friendship"] == 12 and back["name"] == "Canela" and back["rot"] == 1,
			"deshacer el movimiento lo devuelve a su lugar sin perder el progreso posterior")
	controller.redo()
	_check(entities.get_entity(away)["friendship"] == 12 and entities.get_entity(away)["name"] == "Canela", "rehacer tampoco lo pierde")
	controller.undo()

	# Borrar pierde la amistad; deshacer el borrado la devuelve.
	controller.apply_entity(home, {})
	_check(not entities.has_entity(home), "borrar la criatura la quita con todo")
	controller.undo()
	back = entities.get_entity(home)
	_check(back["friendship"] == 12 and back["name"] == "Canela", "deshacer el borrado la devuelve con sus corazones y su nombre")
	# Borrar su bloque de apoyo y deshacer, lo mismo.
	controller.apply_block(home + Vector3i.DOWN, Blocks.AIR)
	controller.undo()
	_check(entities.get_entity(home)["friendship"] == 12 and entities.get_entity(home)["name"] == "Canela", "igual si se había caído por borrar su apoyo")
	# Una criatura nueva del mismo tipo no hereda nada.
	controller.apply_entity(Vector3i(20, 4, 20), EntityLayer.make_entity(CharacterLibrary.RABBIT, 0, 0))
	_check(entities.get_entity(Vector3i(20, 4, 20))["friendship"] == 0 and entities.get_entity(Vector3i(20, 4, 20))["name"] == "", "un conejo nuevo empieza sin amistad")
	controller.undo()
	controller.redo()
	_check(entities.get_entity(Vector3i(20, 4, 20))["friendship"] == 0, "también después de deshacer y rehacer")
	controller.free()
	for node: Node in [world, props, entities, play]:
		node.queue_free()
