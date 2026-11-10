extends Node3D
## Greybox sandbox: flat field, one player, chase cam.
## Purpose is to validate movement feel — weight, accel, cut severity, spin cost.

const HINT_CONTROLLER := "No controller detected. Plug one in — Xbox, PlayStation, and generic XInput pads all work."
const BALL_START_OFFSET := Vector3(0.0, -0.82, -1.0)

@onready var player: PlayerEntity = $Player
@onready var camera: Camera3D = $Camera3D
@onready var readout: Label = $HUD/Readout
@onready var hint: Label = $HUD/Hint
@onready var mesh: MeshInstance3D = $Player/Visual/MeshInstance3D
@onready var markings: FieldMarkings = $FieldMarkings

var _cam_offset := Vector3(0.0, 5.5, 9.0)
var _mat: StandardMaterial3D
var _last_cut := 0.0
var _last_cut_loss := 0.0
var _last_cut_age := 99.0
var _last_juke_age := 99.0
var _last_jump_age := 99.0
var _last_dive_age := 99.0

func _ready() -> void:
	var ball := BallEntity.new()
	ball.name = "Ball"
	ball.position = player.position + BALL_START_OFFSET
	add_child(ball)
	
	_generateCrowd()
	
	

	player.is_user_controlled = true
	player.measurables.compute()
	_fit_ground()
	_build_player_markers()
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.85, 0.87, 0.92)
	mesh.material_override = _mat
	player.cut_performed.connect(_on_cut)
	player.spin_started.connect(_on_spin)
	player.juke_performed.connect(_on_juke)
	player.hurdled.connect(_on_hurdled)
	player.dove.connect(_on_dove)
	InputManager.device_changed.connect(func(_g, _c): _refresh_hint())
	_refresh_hint()

func _generateCrowd() -> void:
	## NOTE: This should be an array but I dont know how arrays work in GD script
	var crowd1 := CrowdEntity.new();
	crowd1.position = Vector3(45, 4, 0);
	crowd1.rotate(Vector3.UP, deg_to_rad(90));
	add_child(crowd1)
	
	var crowd2 := CrowdEntity.new();
	crowd2.position = Vector3(-45, 4, 0);
	crowd2.rotate(Vector3.UP, deg_to_rad(-90));
	add_child(crowd2)
	
	var crowd3 := CrowdEntity.new();
	crowd3.position = Vector3(0, 4, 50);
	add_child(crowd3)
	
	var crowd4 := CrowdEntity.new();
	crowd4.position = Vector3(0, 4, -50);
	crowd4.rotate(Vector3.UP, deg_to_rad(-180));
	add_child(crowd4)


## Keep the visible turf, the collision slab and the painted lines in sync.
## FieldMarkings owns the dimensions so there is one source of truth.
func _fit_ground() -> void:
	var plane := $Ground/MeshInstance3D.mesh as PlaneMesh
	var shape := $Ground/CollisionShape3D.shape as BoxShape3D
	if plane != null:
		plane.size = Vector2(FieldMarkings.GROUND_WIDTH_M, FieldMarkings.GROUND_LENGTH_M)
	if shape != null:
		shape.size = Vector3(FieldMarkings.GROUND_WIDTH_M, 0.2, FieldMarkings.GROUND_LENGTH_M)

## The capsule is symmetric, so orientation is invisible without help. Two cues:
## a bright bar across the shoulders that turns with the body, and a chevron
## floating above the head pointing at the front. The chevron is above the head
## rather than on the ground because the chase cam looks down at a shallow angle
## and the player's own body hides the ground at their feet.
func _build_player_markers() -> void:
	var visual := player.get_node_or_null("Visual") as Node3D
	if visual == null:
		return

	var bar := MeshInstance3D.new()
	bar.name = "ShoulderBar"
	var box := BoxMesh.new()
	box.size = Vector3(1.15, 0.18, 0.30)
	bar.mesh = box
	bar.position = Vector3(0.0, 0.42, 0.0)
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.13, 0.17, 0.28)
	bar_mat.roughness = 0.75
	bar.material_override = bar_mat
	visual.add_child(bar)

	var marker := Node3D.new()
	marker.name = "FacingMarker"
	marker.position = Vector3(0.0, 1.45, 0.0)
	# Tip the chevron toward the chase cam so it is not squashed to a sliver by
	# the shallow view angle. It still points at the front of the player.
	marker.rotation.x = deg_to_rad(22.0)
	visual.add_child(marker)

	# Dark backing so the chevron stays readable against bright turf.
	var backing := MeshInstance3D.new()
	backing.name = "Backing"
	backing.mesh = _make_chevron_mesh()
	backing.scale = Vector3(1.16, 1.0, 1.16)
	backing.position = Vector3(0.0, -0.02, 0.0)
	var backing_mat := StandardMaterial3D.new()
	backing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backing_mat.albedo_color = Color(0.05, 0.07, 0.09)
	backing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	backing.material_override = backing_mat
	marker.add_child(backing)

	var arrow := MeshInstance3D.new()
	arrow.name = "Chevron"
	arrow.mesh = _make_chevron_mesh()
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = Color(1.0, 0.62, 0.15)
	arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arrow.material_override = arrow_mat
	marker.add_child(arrow)

## Chevron pointing along -Z, which is the node's forward direction.
func _make_chevron_mesh() -> ArrayMesh:
	var tip := Vector3(0.0, 0.0, -1.05)
	var notch := Vector3(0.0, 0.0, -0.25)
	var back_left := Vector3(-0.75, 0.0, 0.55)
	var back_right := Vector3(0.75, 0.0, 0.55)
	var verts := PackedVector3Array([
		tip, notch, back_left,
		tip, back_right, notch,
	])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
		markings.toggle_grid()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if player.global_position.y < -5.0:
		# Fell off the world: put them back on the field instead of falling forever.
		player.global_position = Vector3(0.0, 1.2, 36.576)
		player.velocity = Vector3.ZERO

	var focus := player.global_position
	var desired := focus + _cam_offset
	camera.global_position = camera.global_position.lerp(desired, clampf(delta * 6.0, 0.0, 1.0))
	camera.look_at(focus + Vector3.UP * 1.2, Vector3.UP)
	_last_cut_age += delta
	_last_juke_age += delta
	_last_jump_age += delta
	_last_dive_age += delta
	_update_state_visual()
	_update_readout()

func _update_state_visual() -> void:
	if player.dive_phase != PlayerEntity.DivePhase.NONE:
		_mat.albedo_color = Color(0.98, 0.45, 0.32)
	elif player.is_airborne:
		_mat.albedo_color = Color(0.72, 0.80, 1.00)
	elif player.is_landing:
		_mat.albedo_color = Color(0.95, 0.62, 0.30)
	elif player.is_spinning:
		_mat.albedo_color = Color(0.30, 0.80, 0.95)
	elif player.is_juking:
		_mat.albedo_color = Color(0.55, 0.95, 0.55)
	elif player.is_planting:
		_mat.albedo_color = Color(0.98, 0.82, 0.25)
	else:
		_mat.albedo_color = Color(0.85, 0.87, 0.92)

func _on_cut(angle_deg: float, speed_lost: float) -> void:
	_last_cut = angle_deg
	_last_cut_age = 0.0

func _on_spin(_direction: int) -> void:
	pass

func _on_juke(_direction: int) -> void:
	_last_juke_age = 0.0

func _on_hurdled(_clearance: float) -> void:
	_last_jump_age = 0.0

func _on_dove(_distance: float) -> void:
	_last_dive_age = 0.0

func _refresh_hint() -> void:
	hint.visible = not InputManager.has_gamepad()
	if hint.visible:
		hint.text = HINT_CONTROLLER
	else:
		hint.text = ""

func _device_line() -> String:
	if not InputManager.has_gamepad():
		return "input: keyboard + mouse"
	var pad_name := Input.get_joy_name(InputManager.current_device)
	var glyph_names: Array[String] = ["keyboard", "xbox", "playstation"]
	var set_name: String = glyph_names[InputManager.glyph_set]
	return "input: %s  (glyphs: %s)" % [pad_name, set_name]

func _update_readout() -> void:
	var m := player.measurables
	var h := HealthManager.get_state(player.player_id)

	var cut_line := "cut: —"
	if _last_cut_age < 1.2:
		cut_line = "cut: %.0f°   speed lost: %.1f mph" % [_last_cut, 0.0]

	var state := "grounded"
	if player.dive_phase != PlayerEntity.DivePhase.NONE:
		state = ["", "DIVING", "SLIDING", "GET UP"][player.dive_phase]
	elif player.is_airborne:
		state = "AIRBORNE"
	elif player.is_landing:
		state = "LANDING"
	elif player.is_spinning:
		state = "SPINNING"
	elif player.is_juking:
		state = "JUKING"
	elif player.is_planting:
		state = "PLANTING"

	var juke_line := "—"
	if _last_juke_age < 1.0:
		juke_line = "left" if player.last_juke_direction < 0 else "right"

	var jump_line := "jump: —   (vertical %.0f cm   ≈ %.2f m at a run)" % [
		m.vertical_jump_cm, (m.vertical_jump_cm / 100.0) * PlayerEntity.HURDLE_CLEARANCE_SCALE]
	if _last_jump_age < 5.0:
		jump_line = "jump: %.2f m clearance   %.2fs air   landing %.1f m/s" % [
			player.last_jump_clearance, player.last_air_time, player.last_landing_impact]

	var dive_line := "dive: —   (a dive buys reach, then takes your feet)"
	if player.dive_phase != PlayerEntity.DivePhase.NONE:
		dive_line = "dive: %.2f m so far   %s" % [player.dive_distance, state]
	elif _last_dive_age < 5.0:
		dive_line = "dive: %.2f m covered   (%.1f yd)" % [
			player.last_dive_distance, player.last_dive_distance * 1.09361]

	readout.text = "\n".join([
		"FOS Sports Football — greybox",
		"move %s    sprint %s    spin %s    juke %s    hurdle %s    dive %s" % [
			InputManager.glyph("move"),
			InputManager.glyph("sprint"),
			InputManager.glyph("spin"),
			InputManager.glyph("juke"),
			InputManager.glyph("hurdle"),
			InputManager.glyph("dive"),
		],
		"",
		"40: %.2fs   10-split: %.2fs   3-cone: %.2fs" % [m.forty_yard_s, m.ten_yard_split_s, m.three_cone_s],
		"wt: %.0fkg  top speed: %.2f m/s (%.1f mph)" % [m.mass_kg, m.top_speed_mps, m.top_speed_mps * 2.23694],
		"accel: %.2f m/s²   turn: %.0f°/s   reach: %.2fm" % [m.accel_mps2, m.turn_rate_deg, m.reach_m],
		"",
		"speed: %.1f mph   stamina: %.0f%%   traction: %.2f" % [player.speed_mph(), h.stamina * 100.0, EnvironmentManager.traction],
		"state: %-9s %s   cuts: %d   juke: %s" % [state, cut_line, player.cuts_this_play, juke_line],
		jump_line,
		dive_line,
		"spot: %d-yard line   yard grid (F1): %s" % [
			FieldMarkings.yard_line_at(player.global_position.z),
			"on" if markings.is_grid_visible() else "off",
		],
		_device_line(),
		"",
		"try: sprint straight, then slam a hard left at full speed.",
		"try: sprint, then flick the right stick — you slide sideways but keep your drive.",
		"try: sprint, then spin — you keep momentum but lose your steer.",
		"try: sprint, then jump — your line is decided the moment your feet leave the turf.",
	])
