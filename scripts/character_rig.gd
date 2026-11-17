class_name CharacterRig
extends Node3D
## Esqueleto simple para un personaje mini-voxel: cada parte cuelga de un pivote y se
## anima por código (balanceo de patas y brazos, respiración, giro de cabeza, cola, alas).

const SWING_MAX: float = 0.75
const REFERENCE_SPEED: float = 3.0

## Giro de cabeza deseado (radianes, relativo al cuerpo).
var head_yaw: float = 0.0
## Pose sentada (jinete): piernas hacia adelante y abiertas, sin balanceo.
var seated: bool = false
## Vuelo (0 a 1): las alas grandes baten con amplitud completa, a `flap_rate` ciclos.
var flight: float = 0.0
var flap_rate: float = 6.0

var _pivots: Array[Node3D] = []
var _meshes: Array[MeshInstance3D] = []
var _roles: Array[String] = []
var _sides: Array[float] = []
var _rest: Array[Vector3] = []
var _phase: float = 0.0
var _time: float = 0.0
var _amount: float = 0.0


## Arma (o rearma) el esqueleto a partir de las partes de CharacterLibrary.
func setup(parts: Array[Dictionary]) -> void:
	for pivot: Node3D in _pivots:
		remove_child(pivot)
		pivot.queue_free()
	_pivots.clear()
	_meshes.clear()
	_roles.clear()
	_sides.clear()
	_rest.clear()
	for part: Dictionary in parts:
		var pivot := Node3D.new()
		var rest: Vector3 = part["pivot"]
		pivot.position = rest
		var instance := MeshInstance3D.new()
		instance.mesh = part["mesh"]
		pivot.add_child(instance)
		add_child(pivot)
		var role: String = part["role"]
		var side: float = part["side"]
		_pivots.append(pivot)
		_meshes.append(instance)
		_roles.append(role)
		_sides.append(side)
		_rest.append(rest)
	reset_pose()


func part_count() -> int:
	return _pivots.size()


## Vuelve a la pose de reposo.
func reset_pose() -> void:
	_phase = 0.0
	_time = 0.0
	_amount = 0.0
	head_yaw = 0.0
	seated = false
	flight = 0.0
	for i: int in _pivots.size():
		_pivots[i].position = _rest[i]
		_pivots[i].rotation = Vector3.ZERO


## Transparencia de todo el modelo (0 = opaco). Se usa para la vista previa del editor.
func set_ghost(alpha: float) -> void:
	for instance: MeshInstance3D in _meshes:
		instance.transparency = alpha
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Avanza la animación. `speed` es la velocidad horizontal en bloques por segundo.
func animate(delta: float, speed: float) -> void:
	_time += delta
	var target: float = clampf(speed / REFERENCE_SPEED, 0.0, 1.0)
	_amount = lerpf(_amount, target, clampf(delta * 10.0, 0.0, 1.0))
	if speed > 0.05:
		_phase += delta * (5.0 + speed * 2.2)
	var swing: float = sin(_phase) * _amount * SWING_MAX
	var bob: float = sin(_time * 2.2) * 0.012 * (1.0 - _amount)
	for i: int in _pivots.size():
		var pivot: Node3D = _pivots[i]
		match _roles[i]:
			"leg":
				if seated:
					pivot.rotation = Vector3(-1.35, 0.0, _sides[i] * 0.32)
				else:
					pivot.rotation = Vector3(swing * _sides[i], 0.0, 0.0)
			"arm":
				pivot.rotation.x = -0.65 if seated else swing * _sides[i] * 0.9
				pivot.position.y = _rest[i].y + bob
			"head":
				pivot.rotation.y = lerp_angle(pivot.rotation.y, head_yaw, clampf(delta * 6.0, 0.0, 1.0))
				pivot.position.y = _rest[i].y + bob
			"tail":
				pivot.rotation.y = sin(_time * (3.0 + 6.0 * _amount)) * 0.3
				pivot.position.y = _rest[i].y + bob
			"wing_back":
				# Alas de hada: aletean siempre, más rápido al moverse.
				pivot.rotation.y = _sides[i] * (0.45 + 0.35 * sin(_time * (7.0 + 6.0 * _amount)))
				pivot.position.y = _rest[i].y + bob
			"wing_big":
				# Alas de dragón: suben y bajan despacio aunque esté quieto.
				var idle_flap: float = 0.10 + 0.22 * sin(_time * 2.4) + 0.2 * _amount * sin(_phase)
				var flying_flap: float = 0.15 + 0.75 * sin(_time * flap_rate)
				pivot.rotation.z = _sides[i] * lerpf(idle_flap, flying_flap, flight)
				pivot.position.y = _rest[i].y + bob
			"wing":
				pivot.rotation.z = -_sides[i] * absf(sin(_phase * 1.5)) * _amount * 0.9
				pivot.position.y = _rest[i].y + bob
			_:
				pivot.position.y = _rest[i].y + bob
