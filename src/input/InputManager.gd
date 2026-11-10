extends Node
## Tracks the active input device and exposes the right button glyphs.
## Autoloaded as `InputManager`.

signal device_changed(glyph_set: int, gamepad_count: int)

enum GlyphSet { KEYBOARD, XBOX, PLAYSTATION }

const GLYPHS := {
	GlyphSet.KEYBOARD: {
		"confirm": "Enter",
		"cancel": "Esc",
		"move": "WASD",
		"sprint": "Shift",
		"spin": "Q",
		"juke": "J / L",
		"hurdle": "Space",
		"dive": "X",
		"pass": "LMB",
		"tackle": "F",
	},
	GlyphSet.XBOX: {
		"confirm": "A",
		"cancel": "B",
		"move": "L-Stick",
		"sprint": "RT",
		"spin": "B",
		"pass": "X",
		"tackle": "A",
		"juke": "R-Stick",
		"hurdle": "Y",
		"dive": "X",
		"cover_ball": "RB",
	},
	GlyphSet.PLAYSTATION: {
		"confirm": "Cross",
		"cancel": "Circle",
		"move": "L-Stick",
		"sprint": "R2",
		"spin": "Circle",
		"pass": "Square",
		"tackle": "Cross",
		"juke": "R-Stick",
		"hurdle": "Triangle",
		"dive": "Square",
		"cover_ball": "R1",
	},
}

var current_device: int = -1
var glyph_set: GlyphSet = GlyphSet.KEYBOARD
var gamepad_count: int = 0

## Pads can be connected after launch (or unplugged mid-session), so poll.
const POLL_INTERVAL := 0.5
var _poll_accum: float = 0.0

func _ready() -> void:
	_refresh_gamepads()

func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum >= POLL_INTERVAL:
		_poll_accum = 0.0
		_refresh_gamepads()

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if current_device != event.device:
			current_device = event.device
			_detect_glyph_set()
	elif event is InputEventKey or event is InputEventMouseButton:
		if current_device != -1:
			current_device = -1
			glyph_set = GlyphSet.KEYBOARD
			device_changed.emit(glyph_set, gamepad_count)

func glyph(action: String) -> String:
	return GLYPHS[glyph_set].get(action, action)

func has_gamepad() -> bool:
	return gamepad_count > 0

func _refresh_gamepads() -> void:
	var pads := Input.get_connected_joypads()
	var changed := pads.size() != gamepad_count
	gamepad_count = pads.size()
	if gamepad_count > 0 and current_device == -1:
		current_device = pads[0]
		_detect_glyph_set()
	elif gamepad_count == 0:
		current_device = -1
		glyph_set = GlyphSet.KEYBOARD
	if changed:
		device_changed.emit(glyph_set, gamepad_count)

func _detect_glyph_set() -> void:
	var jname := Input.get_joy_name(current_device).to_lower()
	if jname.contains("sony") or jname.contains("playstation") \
			or jname.contains("dualshock") or jname.contains("dualsense"):
		glyph_set = GlyphSet.PLAYSTATION
	else:
		glyph_set = GlyphSet.XBOX
	device_changed.emit(glyph_set, gamepad_count)
