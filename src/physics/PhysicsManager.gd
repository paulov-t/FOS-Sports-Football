extends Node
## Central tuning for the physics simulation. Autoloaded as `PhysicsManager`.
## Simulation vs arcade is expressed purely as parameter sets — never as
## scripted outcomes or probability tables.

class TuningSet:
	var name: String
	var time_scale: float
	var gravity_scale: float
	var friction_mult: float
	var restitution_mult: float
	var player_mass_mult: float
	var air_density: float

	func _init(p_name: String, ts: float, gs: float, fr: float, re: float, pm: float, ad: float) -> void:
		name = p_name
		time_scale = ts
		gravity_scale = gs
		friction_mult = fr
		restitution_mult = re
		player_mass_mult = pm
		air_density = ad

var simulation := TuningSet.new("Simulation", 1.0, 1.0, 1.0, 0.85, 1.0, 1.225)
var arcade := TuningSet.new("Arcade", 1.08, 0.85, 0.8, 1.05, 0.9, 1.0)

var active: TuningSet = simulation

func set_arcade(enabled: bool) -> void:
	active = arcade if enabled else simulation
	Engine.time_scale = active.time_scale

func gravity_vector() -> Vector3:
	return ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN) \
		* float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) \
		* active.gravity_scale
