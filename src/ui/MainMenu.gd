extends Control

const FIELD_SCENE := "res://src/core/GreyboxField.tscn"

@onready var arcade_toggle: CheckButton = $VBox/TuningRow/ArcadeToggle
@onready var tuning_label: Label = $VBox/TuningRow/TuningLabel

func _ready() -> void:
	$VBox/Play.pressed.connect(_on_play.bind(GameManager.Mode.PLAYER))
	$VBox/CoachMode.pressed.connect(_on_play.bind(GameManager.Mode.COACH))
	$VBox/SimGame.pressed.connect(_on_play.bind(GameManager.Mode.SIM))
	$VBox/Quit.pressed.connect(_on_quit)
	arcade_toggle.toggled.connect(_on_arcade_toggled)
	_refresh_tuning_label()

func _on_play(mode: int) -> void:
	GameManager.set_mode(mode)
	get_tree().change_scene_to_file(FIELD_SCENE)

func _on_arcade_toggled(pressed: bool) -> void:
	GameManager.arcade_tuning = pressed
	PhysicsManager.set_arcade(pressed)
	_refresh_tuning_label()

func _refresh_tuning_label() -> void:
	tuning_label.text = "Tuning: %s" % ("Arcade" if GameManager.arcade_tuning else "Simulation")

func _on_quit() -> void:
	get_tree().quit()
