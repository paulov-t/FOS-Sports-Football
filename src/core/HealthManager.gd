extends Node
## Health, fatigue, and injury bookkeeping. Autoloaded as `HealthManager`.
##
## The numbers here are continuous and physical. Output scales with what the
## body can currently produce — there is no random failure roll anywhere.

## Per-player states keyed by a stable player id.
var _states: Dictionary = {}

func get_state(player_id: String) -> HealthState:
	if not _states.has(player_id):
		_states[player_id] = HealthState.new()
	return _states[player_id]

func reset() -> void:
	_states.clear()

## Apply the physical cost of one frame of effort.
func exert(player_id: String, effort: float, dt: float) -> void:
	var s := get_state(player_id)
	s.stamina = maxf(s.stamina - effort * dt * 0.04, 0.0)
	s.hydration = maxf(s.hydration - effort * dt * 0.01, 0.0)
	s.soreness = minf(s.soreness + effort * dt * 0.004, 1.0)

## Recovery during time between plays.
func recover(player_id: String, dt: float, resting: bool) -> void:
	var s := get_state(player_id)
	var rate := 0.02 if resting else 0.005
	s.stamina = minf(s.stamina + rate * dt * s.hydration, 1.0)
	if resting:
		s.soreness = maxf(s.soreness - 0.002 * dt, 0.0)
