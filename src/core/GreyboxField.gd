extends Node3D
## Greybox sandbox: flat field, a human player, a CPU body, chase cam.
## Purpose is to validate movement feel and player-vs-player contact physics.

const HINT_CONTROLLER := "No controller detected. Plug one in — Xbox, PlayStation, and generic XInput pads all work."
const BALL_START_OFFSET := Vector3(0.0, -0.82, -1.0)
const PLAYER_SPAWN := Vector3(0.0, 0.93, 36.576)
const CPU_SPAWN := Vector3(0.0, 0.93, 28.0)
const AUTO_RESET_CONTACT_TIME := 3.0
const CONTACT_RESET_DISTANCE := 1.0
const HUMAN_BASE := Color(0.85, 0.87, 0.92)
const CPU_BASE := Color(0.80, 0.25, 0.25)
const HUMAN_CHEVRON := Color(1.0, 0.62, 0.15)
const CPU_CHEVRON := Color(0.95, 0.25, 0.25)

@onready var player: PlayerEntity = $Player
@onready var camera: Camera3D = $Camera3D
@onready var readout: Label = $HUD/Readout
@onready var hint: Label = $HUD/Hint
@onready var mesh: MeshInstance3D = $Player/Visual/MeshInstance3D
@onready var markings: FieldMarkings = $FieldMarkings

var cpu: PlayerEntity
var cpu_controller: CpuController
var collision_manager: PlayerCollisionManager

var _cam_offset := Vector3(0.0, 5.5, 9.0)
var _mat: StandardMaterial3D
var _cpu_mat: StandardMaterial3D
var _cpu_mesh: MeshInstance3D
var _last_cut := 0.0
var _last_cut_loss := 0.0
var _last_cut_age := 99.0
var _last_juke_age := 99.0
var _last_jump_age := 99.0
var _last_dive_age := 99.0
var _last_hit_age := 99.0
var _last_hit: Dictionary = {}
var _contact_time := 0.0

func _ready() -> void:
	var ball := BallEntity.new()
	ball.name = "Ball"
	ball.position = player.position + BALL_START_OFFSET
	add_child(ball)
	
	_generateCrowd()
	
	

	player.is_user_controlled = true
	player.measurables.compute()
	# Players collide with the world (layer 1) but not with each other (layer 2).
	# PlayerCollisionManager owns body-to-body contact so momentum can transfer.
	player.collision_layer = 2
	player.collision_mask = 1
	player.add_to_group("players")

	_spawn_cpu()
	_fit_ground()
	_build_player_markers(player, HUMAN_CHEVRON, Color(0.13, 0.17, 0.28))
	_build_player_markers(cpu, CPU_CHEVRON, Color(0.28, 0.10, 0.10))

	_mat = _make_material(HUMAN_BASE)
	mesh.material_override = _mat
	_cpu_mesh = cpu.get_node_or_null("Visual/MeshInstance3D") as MeshInstance3D
	_cpu_mat = _make_material(CPU_BASE)
	if _cpu_mesh != null:
		_cpu_mesh.material_override = _cpu_mat

	_setup_cpu_controller()
	_setup_collision_manager()

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

func _spawn_cpu() -> void:
	# The CPU is a real PlayerEntity, not a special case. Duplicating the node
	# keeps its movement, dive and visual code identical to the human's.
	cpu = player.duplicate() as PlayerEntity
	cpu.name = "CpuPlayer"
	cpu.player_id = "cpu"
	cpu.is_user_controlled = false
	cpu.measurables = _make_cpu_measurables()
	cpu.position = CPU_SPAWN
	cpu.collision_layer = 2
	cpu.collision_mask = 1
	add_child(cpu)
	cpu.add_to_group("players")
	cpu.reset_body(CPU_SPAWN, Vector3.BACK)

func _make_cpu_measurables() -> PlayerMeasurables:
	# A heavier, stronger, slightly slower body than the human WR. The point is
	# to make mass and strength differences obvious while tuning collisions.
	var m := PlayerMeasurables.new()
	m.position = PlayerPosition.PlayerPosition.MLB
	m.height_cm = 188.0
	m.weight_kg = 108.0
	m.wingspan_cm = 196.0
	m.arm_length_cm = 88.0
	m.hand_size_cm = 24.0
	m.forty_yard_s = 4.65
	m.ten_yard_split_s = 1.60
	m.twenty_yard_shuttle_s = 4.30
	m.three_cone_s = 7.10
	m.short_shuttle_s = 4.30
	m.vertical_jump_cm = 80.0
	m.broad_jump_cm = 290.0
	m.bench_press_reps = 25
	m.compute()
	return m

func _setup_cpu_controller() -> void:
	cpu_controller = CpuController.new()
	cpu_controller.name = "CpuController"
	cpu_controller.player = cpu
	cpu_controller.target = player
	add_child(cpu_controller)

func _setup_collision_manager() -> void:
	collision_manager = PlayerCollisionManager.new()
	collision_manager.name = "PlayerCollisionManager"
	collision_manager.register(player)
	collision_manager.register(cpu)
	add_child(collision_manager)
	collision_manager.impact_resolved.connect(_on_impact_resolved)

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
## floating above the head pointing at the front.
func _build_player_markers(p: PlayerEntity, chevron_color: Color, bar_color: Color) -> void:
	var visual := p.get_node_or_null("Visual") as Node3D
	if visual == null:
		return

	var bar := MeshInstance3D.new()
	bar.name = "ShoulderBar"
	var box := BoxMesh.new()
	box.size = Vector3(1.15, 0.18, 0.30)
	bar.mesh = box
	bar.position = Vector3(0.0, 0.42, 0.0)
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = bar_color
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
	arrow_mat.albedo_color = chevron_color
	arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arrow.material_override = arrow_mat
	marker.add_child(arrow)

func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat

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
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			markings.toggle_grid()
			get_viewport().set_input_as_handled()
		KEY_F2:
			if cpu_controller != null:
				cpu_controller.cycle_mode()
			get_viewport().set_input_as_handled()
		KEY_F3:
			_reset_positions()
			get_viewport().set_input_as_handled()
		KEY_F4:
			EnvironmentManager.cycle_surface()
			get_viewport().set_input_as_handled()
		KEY_F5:
			_toggle_cpu_hold()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if player.global_position.y < -5.0:
		# Fell off the world: put them back on the field instead of falling forever.
		player.reset_body(PLAYER_SPAWN, Vector3.FORWARD)
	if cpu.global_position.y < -5.0:
		cpu.reset_body(CPU_SPAWN, Vector3.BACK)

	_update_contact_reset(delta)

	var focus := player.global_position
	var desired := focus + _cam_offset
	camera.global_position = camera.global_position.lerp(desired, clampf(delta * 6.0, 0.0, 1.0))
	camera.look_at(focus + Vector3.UP * 1.2, Vector3.UP)
	_last_cut_age += delta
	_last_juke_age += delta
	_last_jump_age += delta
	_last_dive_age += delta
	_last_hit_age += delta
	_update_state_visual()
	_update_readout()

func _reset_positions() -> void:
	player.reset_body(PLAYER_SPAWN, Vector3.FORWARD)
	cpu.reset_body(CPU_SPAWN, Vector3.BACK)
	_contact_time = 0.0
	_last_hit_age = 99.0
	_last_hit = {}
	if collision_manager != null:
		collision_manager.reset()
	# Give the player a beat to set up after a reset. Without this the CPU
	# immediately re-acquires and the reset is useless for testing.
	if cpu_controller != null:
		cpu_controller.release_hold()
		cpu_controller.hold_for(3.0)

## F5: reset the CPU to its spawn and hold it indefinitely. Press F5 again to
## release it. This keeps the human player where they are.
func _toggle_cpu_hold() -> void:
	if cpu_controller == null:
		return
	if cpu_controller.is_held():
		cpu_controller.release_hold()
	else:
		_reset_cpu_only()
		cpu_controller.toggle_hold()

func _reset_cpu_only() -> void:
	if cpu == null:
		return
	cpu.reset_body(CPU_SPAWN, Vector3.BACK)
	_contact_time = 0.0
	_last_hit_age = 99.0
	_last_hit = {}
	if collision_manager != null:
		collision_manager.reset()

## Safety net for testing: if a hit turns into a sustained lean for a few
## seconds, reset the CPU and hold it briefly. If the players separate first,
## the timer clears and the CPU keeps playing normally.
func _update_contact_reset(delta: float) -> void:
	if cpu == null or cpu_controller == null:
		return
	if cpu_controller.is_held() or _last_hit_age > 6.0:
		_contact_time = 0.0
		return
	var flat := Vector3(
		player.global_position.x - cpu.global_position.x,
		0.0,
		player.global_position.z - cpu.global_position.z).length()
	if flat > CONTACT_RESET_DISTANCE:
		_contact_time = 0.0
		return
	_contact_time += delta
	if _contact_time >= AUTO_RESET_CONTACT_TIME:
		_reset_cpu_only()
		cpu_controller.hold_for(2.0)

func _update_state_visual() -> void:
	_apply_state_color(player, _mat, HUMAN_BASE)
	if cpu != null and _cpu_mat != null:
		_apply_state_color(cpu, _cpu_mat, CPU_BASE)

func _apply_state_color(p: PlayerEntity, mat: StandardMaterial3D, base: Color) -> void:
	if p.dive_phase != PlayerEntity.DivePhase.NONE:
		mat.albedo_color = Color(0.98, 0.45, 0.32)
	elif p.is_airborne:
		mat.albedo_color = Color(0.72, 0.80, 1.00)
	elif p.stagger_timer > 0.0:
		mat.albedo_color = Color(1.0, 0.32, 0.32)
	elif p.is_landing:
		mat.albedo_color = Color(0.95, 0.62, 0.30)
	elif p.is_spinning:
		mat.albedo_color = Color(0.30, 0.80, 0.95)
	elif p.is_juking:
		mat.albedo_color = Color(0.55, 0.95, 0.55)
	elif p.is_planting:
		mat.albedo_color = Color(0.98, 0.82, 0.25)
	else:
		mat.albedo_color = base

func _on_cut(angle_deg: float, speed_lost: float) -> void:
	_last_cut = angle_deg
	_last_cut_loss = speed_lost
	_last_cut_age = 0.0

func _on_spin(_direction: int) -> void:
	pass

func _on_juke(_direction: int) -> void:
	_last_juke_age = 0.0

func _on_hurdled(_clearance: float) -> void:
	_last_jump_age = 0.0

func _on_dove(_distance: float) -> void:
	_last_dive_age = 0.0

func _on_impact_resolved(info: Dictionary) -> void:
	_last_hit = info
	_last_hit_age = 0.0

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
		cut_line = "cut: %.0f°   speed lost: %.1f mph" % [_last_cut, _last_cut_loss * 2.23694]

	var state := player.state_name()

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

	var cpu_line := "cpu: —"
	var mode_line := "cpu mode: —"
	if cpu != null and cpu_controller != null:
		var cm := cpu.measurables
		if cpu_controller.is_held():
			var hold_left := cpu_controller.hold_remaining()
			if hold_left > 0.0:
				mode_line = "cpu mode: HOLD %.1fs   (F5: release)" % hold_left
			else:
				mode_line = "cpu mode: HOLD   (F5: release)"
		else:
			mode_line = "cpu mode: %-6s   (F2: mode   F5: hold)" % cpu_controller.mode_name()
		cpu_line = "cpu: wt %.0fkg   speed %.1f mph   state %-9s   footing %.2f" % [
			cm.mass_kg, cpu.speed_mph(), cpu.state_name(), cpu.footing_factor()]

	var hit_line := "collision: —"
	if _last_hit_age < 2.5 and not _last_hit.is_empty():
		var a_is_you := String(_last_hit.get("a_id", "")) == player.player_id
		var dv_you := float(_last_hit.get("dv_a" if a_is_you else "dv_b", 0.0))
		var dv_cpu := float(_last_hit.get("dv_b" if a_is_you else "dv_a", 0.0))
		var m_you := float(_last_hit.get("m_eff_a" if a_is_you else "m_eff_b", 0.0))
		var m_cpu := float(_last_hit.get("m_eff_b" if a_is_you else "m_eff_a", 0.0))
		hit_line = "collision: closing %.1f m/s   impulse %.0f N·s   Δv you %.1f / cpu %.1f" % [
			float(_last_hit.get("closing", 0.0)),
			float(_last_hit.get("impulse", 0.0)),
			dv_you,
			dv_cpu,
		]
		hit_line += "   (effective mass %.0f / %.0f kg)" % [m_you, m_cpu]

	var collisions := collision_manager.impact_count if collision_manager != null else 0

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
		"speed: %.1f mph   stamina: %.0f%%   traction: %.2f   surface: %s (F4)" % [
			player.speed_mph(), h.stamina * 100.0, EnvironmentManager.traction, EnvironmentManager.surface_name()],
		"state: %-9s %s   cuts: %d   juke: %s" % [state, cut_line, player.cuts_this_play, juke_line],
		jump_line,
		dive_line,
		"",
		mode_line,
		cpu_line,
		hit_line,
		"collisions: %d   spot: %d-yard line   grid (F1): %s" % [
			collisions, FieldMarkings.yard_line_at(player.global_position.z),
			"on" if markings.is_grid_visible() else "off"],
		"F3: reset both (3s hold)   F5: hold/release CPU   F2: CPU mode   F4: surface",
		_device_line(),
		"",
		"try: let the CPU brace, then run straight through it. A planted 108 kg body costs you.",
		"try: chase the CPU and hit it from the side. Angle and facing change the result.",
		"try: dive at the CPU. No feet planted means you trade leverage for reach.",
	])
