class_name AppConfig
extends RefCounted
## Constantes y cálculos generales de la aplicación: tamaños de mapa y escala de la interfaz.

## Tamaños de mapa disponibles al crear uno nuevo (lado en celdas).
const SIZE_KEYS: Array[String] = ["S", "M", "L"]
const SIZE_SIDES: Array[int] = [64, 128, 256]
const DEFAULT_SIZE: String = "S"
## Los mapas de hasta este lado se generan de una sola vez; los más grandes, por partes.
const INSTANT_SIDE: int = 64

## Alto de ventana para el que la interfaz se dibuja a escala 1.
const UI_REFERENCE_HEIGHT: float = 1080.0
const UI_SCALE_STEP: float = 0.25
const UI_SCALE_MAX: float = 3.0


static func is_size_key(key: String) -> bool:
	return SIZE_KEYS.has(key.to_upper())


## Lado del mapa para una clave de tamaño (S si la clave no existe).
static func side_for(key: String) -> int:
	var index: int = SIZE_KEYS.find(key.to_upper())
	return SIZE_SIDES[index] if index >= 0 else SIZE_SIDES[0]


## Clave de tamaño para un lado, o "" si no es uno de los tamaños estándar.
static func key_for_side(side: int) -> String:
	var index: int = SIZE_SIDES.find(side)
	return SIZE_KEYS[index] if index >= 0 else ""


## Texto para mostrar un tamaño: "M — 128 × 128".
static func size_label(key: String) -> String:
	var side: int = side_for(key)
	return "%s — %d × %d" % [key.to_upper(), side, side]


## Texto para el tamaño de un mundo cualquiera: "L (256 × 256)" o "100 × 80".
static func world_label(size_x: int, size_z: int) -> String:
	var key: String = key_for_side(size_x) if size_x == size_z else ""
	if key.is_empty():
		return "%d × %d" % [size_x, size_z]
	return "%s (%d × %d)" % [key, size_x, size_z]


## Escala de la interfaz según el alto de la ventana: 1 hasta 1080 px y, de ahí en más,
## proporcional al alto en pasos de 0,25 (1,25 a 1440 px; 2 a 2160 px). Nunca menos de 1,
## para que el texto no se achique en ventanas chicas.
static func ui_scale_for_height(height: int) -> float:
	var steps: float = roundf(float(height) / UI_REFERENCE_HEIGHT / UI_SCALE_STEP)
	return clampf(steps * UI_SCALE_STEP, 1.0, UI_SCALE_MAX)
