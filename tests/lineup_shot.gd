extends SceneTree
## Captura de revisión: personajes en fila sobre un piso plano, para revisar a ojo
## proporciones, apoyo de los pies y uniones entre partes.
##   godot --path <proyecto> --script res://tests/lineup_shot.gd -- --out=<png absoluto>
## Opciones:
##   --set=todo        todas las criaturas (con sus variantes) y todos los avatares (por defecto).
##   --set=criaturas   un adulto y una niña junto al poni, el unicornio, el dragón y una oveja.
##   --set=avatares    los doce avatares.
##   --walk            en pose de caminar.

func _initialize() -> void:
	_run()


func _run() -> void:
	var out_path: String = ""
	var walking: bool = false
	var which: String = "todo"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--set="):
			which = arg.trim_prefix("--set=")
		elif arg == "--walk":
			walking = true

	var root_node := Node3D.new()
	get_root().add_child(root_node)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.76, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.90, 1.0)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root_node.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.shadow_enabled = true
	root_node.add_child(sun)

	var world := VoxelWorld.new()
	world.clear(Vector3i(64, 16, 32))
	root_node.add_child(world)
	for z: int in 32:
		for x: int in 64:
			world.set_block_raw(x, 0, z, Blocks.GRASS)
	world.mark_all_dirty()
	world.remesh_dirty()

	var library := CharacterLibrary.new()
	var rigs: Array[CharacterRig] = []
	# Cada fila es una lista de partes; se reparten a lo ancho con `spacing` bloques.
	var rows: Array[Array] = []
	var spacing: float = 2.0
	match which:
		"criaturas":
			spacing = 2.6
			rows.append([
				library.get_avatar_parts(CharacterLibrary.FIRST_ADULT_AVATAR),
				library.get_avatar_parts(0),
				library.get_entity_parts(CharacterLibrary.PONY, 0),
				library.get_entity_parts(CharacterLibrary.UNICORN, 0),
				library.get_entity_parts(CharacterLibrary.DRAGON, 0),
				library.get_entity_parts(CharacterLibrary.SHEEP, 0),
			])
		"avatares":
			var avatars: Array = []
			for index: int in CharacterLibrary.AVATAR_COUNT:
				avatars.append(library.get_avatar_parts(index))
			rows.append(avatars)
		_:
			var front: Array = []
			for type: int in CharacterLibrary.ENTITY_COUNT:
				for variant: int in CharacterLibrary.variant_count(type):
					front.append(library.get_entity_parts(type, variant))
			rows.append(front)
			var back: Array = []
			for index: int in CharacterLibrary.AVATAR_COUNT:
				back.append(library.get_avatar_parts(index))
			rows.append(back)

	var widest: float = 0.0
	for r: int in rows.size():
		var row: Array = rows[r]
		var width: float = float(row.size() - 1) * spacing
		widest = maxf(widest, width)
		for i: int in row.size():
			var parts: Array[Dictionary] = []
			parts.assign(row[i])
			var rig := CharacterRig.new()
			root_node.add_child(rig)
			rig.setup(parts)
			rig.position = Vector3(32.0 - width * 0.5 + float(i) * spacing, 1.0, 14.0 - float(r) * 3.5)
			rig.rotation.y = 0.6
			rigs.append(rig)

	# La cámara se aleja lo necesario para que entre la fila más ancha.
	var cam := Camera3D.new()
	cam.fov = 40.0
	root_node.add_child(cam)
	var window: Vector2 = Vector2(get_root().size)
	var half_width: float = widest * 0.5 + 1.2
	var distance: float = 0.72 * half_width / (tan(deg_to_rad(20.0)) * window.x / window.y)
	var target := Vector3(32.0, 1.6, 14.0 - float(rows.size() - 1) * 1.75)
	var cam_pos: Vector3 = target + Vector3(0.0, distance * 0.22, distance)
	cam.transform = Transform3D(Basis.looking_at(target - cam_pos, Vector3.UP), cam_pos)
	cam.current = true

	for i: int in 40:
		await process_frame
		for rig: CharacterRig in rigs:
			rig.animate(0.03, 2.5 if walking else 0.0)
	await RenderingServer.frame_post_draw
	if not out_path.is_empty():
		get_root().get_texture().get_image().save_png(out_path)
		print("Captura guardada en %s" % out_path)
	quit(0)
