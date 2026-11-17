extends SceneTree
## Medición de rendimiento (necesita ventana). Carga la escena principal con el tamaño
## pedido y mide tiempos de generación, cuadros por segundo y costo de las ediciones.
##   godot --path <proyecto> --script res://tests/perf_bench.gd -- --size=L --seed=2024
## Los cuadros por segundo se miden sin sincronía vertical.

const FRAMES: int = 150


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


## Devuelve [fps promedio, ms del peor cuadro] girando la cámara `turn` radianes por cuadro.
func _measure(camera: EditorCamera, turn: float) -> Array[float]:
	await _frames(20)
	var worst: int = 0
	var start: int = Time.get_ticks_usec()
	var last: int = start
	for i: int in FRAMES:
		if camera != null:
			camera.yaw += turn
			camera.update_view()
		await process_frame
		var now: int = Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
	var total: float = float(last - start) / 1000000.0
	return [float(FRAMES) / total, float(worst) / 1000.0]


func _render_stats() -> String:
	return "%d draw calls, %.2f M primitivas, %d objetos" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	]


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	get_root().add_child(main)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _frames(3)
	var worst_loading: int = 0
	var last: int = Time.get_ticks_usec()
	while main.call("is_busy"):
		await process_frame
		var now: int = Time.get_ticks_usec()
		worst_loading = maxi(worst_loading, now - last)
		last = now
	var world: VoxelWorld = main.get("world")
	var props: PropLayer = main.get("props")
	var entities: EntityLayer = main.get("entities")
	var camera: EditorCamera = main.get("camera")
	var play: PlayMode = main.get("play")
	var window: Vector2i = get_root().size
	print("[%s] ventana %d x %d" % [AppConfig.world_label(world.size_x, world.size_z), window.x, window.y])
	print("  listo en %d ms (peor cuadro durante la carga: %.1f ms)" % [
			main.get("last_load_msec"), float(worst_loading) / 1000.0])
	print("  %d chunks, %d props, %d criaturas, %d nodos de props" % [
			world.chunks.size(), props.props.size(), entities.entities.size(), props.get_child_count()])

	var result: Array[float] = await _measure(camera, 0.01)
	print("  editor, mapa entero, orbitando: %.0f fps (peor cuadro %.1f ms) · %s" % [
			result[0], result[1], _render_stats()])
	camera.distance = 30.0
	camera.update_view()
	result = await _measure(camera, 0.01)
	print("  editor, de cerca (distancia 30): %.0f fps (peor cuadro %.1f ms) · %s" % [
			result[0], result[1], _render_stats()])

	# Costo de una edición de un voxel (interior de un chunk) y de un prop.
	@warning_ignore("integer_division")
	var cell := Vector3i(world.size_x / 2 + 5, 20, world.size_z / 2 + 5)
	var t0: int = Time.get_ticks_usec()
	world.set_block(cell, Blocks.STONE)
	var dirty: int = world.dirty_count()
	world.remesh_dirty()
	print("  editar un voxel: %d chunk(s), %.2f ms" % [dirty, float(Time.get_ticks_usec() - t0) / 1000.0])
	world.set_block(cell, Blocks.AIR)
	world.remesh_dirty()
	var prop_cell := Vector3i(cell.x, world.column_height(cell.x, cell.z), cell.z)
	t0 = Time.get_ticks_usec()
	props.set_prop(prop_cell, PropLayer.make_prop(PropLibrary.OAK, 0, 0))
	props.rebuild_dirty()
	print("  colocar un prop: %.2f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	for i: int in 20:
		props.pick(camera.global_position, -camera.global_transform.basis.z, 600.0)
	print("  buscar un prop bajo el mouse: %.2f ms" % (float(Time.get_ticks_usec() - t0) / 20000.0))

	# Modo juego: costo de simulación por cuadro y cuadros por segundo.
	@warning_ignore("integer_division")
	var spawn: Vector3 = Player.find_spawn(world, props, world.size_x / 2, world.size_z / 2)
	main.call("start_play", spawn, false)
	await _frames(30)
	t0 = Time.get_ticks_usec()
	for i: int in 300:
		play.simulate(1.0 / 60.0, Vector3.ZERO, false, false)
	var per_step: float = float(Time.get_ticks_usec() - t0) / 300000.0
	print("  modo juego: simulación %.3f ms por cuadro (%d criaturas en el mapa, %d simuladas)" % [
			per_step, entities.entities.size(), play.get("simulated_count")])
	result = await _measure(null, 0.0)
	print("  modo juego: %.0f fps (peor cuadro %.1f ms) · %s" % [result[0], result[1], _render_stats()])
	quit(0)
