extends Node
## Weather, field surface, and atmosphere. Autoloaded as `EnvironmentManager`.
## Everything here feeds real physics values: traction, grip, drag, ball flight.

enum Surface { NATURAL_GRASS, TURF, WET, MUD, SNOW, ICE }
enum Precipitation { NONE, RAIN, SNOW }

const SURFACE_TRACTION := {
	Surface.NATURAL_GRASS: 0.95,
	Surface.TURF: 0.98,
	Surface.WET: 0.82,
	Surface.MUD: 0.68,
	Surface.SNOW: 0.62,
	Surface.ICE: 0.45,
}

var temperature_c: float = 15.0
var humidity: float = 0.5
var wind: Vector3 = Vector3.ZERO
var precipitation: Precipitation = Precipitation.NONE
var visibility: float = 1.0
var altitude_m: float = 0.0

var surface: Surface = Surface.NATURAL_GRASS
var wetness: float = 0.0

## Multiplier applied to grip/friction in the physics step.
var traction: float = 0.95
## Multiplier applied to ball drag (thin air at altitude flies further).
var air_density: float = 1.225
## Wear added per play to the surface, making it progressively slicker.
var surface_wear: float = 0.0

func _ready() -> void:
	recalculate()

func recalculate() -> void:
	traction = SURFACE_TRACTION[surface]
	# Wetness and wear both reduce grip continuously, not in discrete steps.
	traction *= clampf(1.0 - wetness * 0.35 - surface_wear * 0.4, 0.25, 1.0)
	# Snow/ice hurt footing even when "dry".
	if surface == Surface.SNOW:
		traction *= 0.95
	if surface == Surface.ICE:
		traction *= 0.9

	# Air density from altitude and temperature (ideal-gas, sea level baseline).
	var temp_k := temperature_c + 273.15
	var pressure_ratio := exp(-altitude_m / 8434.5)
	air_density = 1.225 * pressure_ratio * (288.15 / temp_k)
	air_density *= (1.0 - humidity * 0.01)

	match precipitation:
		Precipitation.RAIN:
			wetness = minf(wetness + 0.08, 1.0)
		Precipitation.SNOW:
			wetness = minf(wetness + 0.04, 1.0)
		Precipitation.NONE:
			wetness = maxf(wetness - 0.02, 0.0)

	visibility = clampf(1.0 - wetness * 0.1, 0.6, 1.0)

func wear_surface(amount: float) -> void:
	surface_wear = clampf(surface_wear + amount, 0.0, 1.0)
	recalculate()

## Debug helper for the sandbox: step through the surfaces in order. This does
## not change precipitation or wear, so each surface's base traction stays a
## clean variable while we tune collisions.
func cycle_surface() -> void:
	match surface:
		Surface.NATURAL_GRASS: surface = Surface.TURF
		Surface.TURF: surface = Surface.WET
		Surface.WET: surface = Surface.MUD
		Surface.MUD: surface = Surface.SNOW
		Surface.SNOW: surface = Surface.ICE
		_: surface = Surface.NATURAL_GRASS
	recalculate()

func surface_name() -> String:
	return Surface.keys()[surface]
