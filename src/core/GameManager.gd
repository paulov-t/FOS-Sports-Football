extends Node
## Global game state. Autoloaded as `GameManager`.
## NOTE: no `class_name` here — the autoload singleton name is the handle.

enum Mode { PLAYER, COACH, SIM }

var mode: Mode = Mode.PLAYER
var sim_speed: float = 1.0
## Arcade vs simulation is a tuning set, never scripted logic.
var arcade_tuning: bool = false

func set_mode(new_mode: Mode) -> void:
	mode = new_mode
