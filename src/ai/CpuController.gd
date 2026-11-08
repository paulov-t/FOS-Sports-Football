class_name CpuController
extends Node
## Drives a CPU player through the same intent fields a human uses.
##
## This is deliberately a sandbox controller: the point is to give the collision
## model a live body to hit, not to pretend this is a finished defender AI. It
## never reads the keyboard or a gamepad, so it cannot steal the human's input.

enum Mode { CHASE, BRACE, STRAFE }

const MODE_NAMES := ["CHASE", "BRACE", "STRAFE"]

@export var player: PlayerEntity
@export var target: PlayerEntity
@export_enum("CHASE", "BRACE", "STRAFE") var mode: int = Mode.CHASE

var _strafe_sign: float = 1.0

func _ready() -> void:
	# Intent must be written before the player's own _physics_process runs.
	process_physics_priority = -10

func _physics_process(_delta: float) -> void:
	if player == null or target == null:
		return

	var to_target := target.global_position - player.global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var direction := to_target / distance if distance > 0.001 else Vector3.ZERO

	# A defender keeps his shoulders square to the man. The player's turn rate
	# still limits how fast that happens, so a sharp cut can catch him.
	player.face_intent = direction

	match mode:
		Mode.CHASE:
			player.move_intent = direction
			player.sprint_intent = distance > 3.0
		Mode.BRACE:
			player.move_intent = Vector3.ZERO
			player.sprint_intent = false
		Mode.STRAFE:
			var side := direction.cross(Vector3.UP) * _strafe_sign
			if distance > 6.0:
				player.move_intent = direction
			elif distance < 2.5:
				player.move_intent = -direction
			else:
				player.move_intent = side
			player.sprint_intent = false

func cycle_mode() -> void:
	mode = (mode + 1) % MODE_NAMES.size()

func mode_name() -> String:
	return MODE_NAMES[mode]
