class_name PlayerEntity
extends CharacterBody3D
## A single football player.
##
## Movement is generated from measurables plus the current physical state of the
## body and the field. There is no hidden "win the rep" check anywhere in this
## class.
##
## Cutting and spinning are NOT animations with success rolls. They are two ways
## the same force budget gets spent:
##
##   Cut   - you must kill forward momentum before the new direction can take
##           over. Sharp angle at high speed = more speed lost. A well-timed
##           plant trades less speed because the planted foot can push harder
##           laterally.
##   Spin  - you keep most of your momentum but give up your ability to
##           accelerate laterally while rotating. Good for escaping leverage
##           when a defender is committed; bad if you spin into open space.

signal cut_performed(angle_deg: float, speed_lost: float)
signal spin_started(direction: int)
signal juke_performed(direction: int)
signal hurdled(clearance_m: float)
signal landed(impact_mps: float, speed_lost: float)
signal dove(distance_m: float)

const CUT_ANGLE_DEG := 32.0
const PLANT_TIME := 0.17
const PLANT_COOLDOWN := 0.12
const SPIN_DURATION := 0.42
const SPIN_COOLDOWN := 0.85
const SPIN_SPEED_COST := 0.12
const SPIN_LATERAL_LOCK := 0.15

## Juke: a push off the outside foot. Unlike a cut it does NOT kill your drive -
## it adds sideways momentum on top of the speed you already carry, and the turf
## scrubs that extra away over about half a second. You stay committed for a beat,
## so a juke into traffic is a real mistake.
const JUKE_COOLDOWN := 0.55
const JUKE_DURATION := 0.28
const JUKE_MIN_SPEED_FRAC := 0.35
const JUKE_BASE_MPS := 3.55
const JUKE_DECAY_MPS2 := 7.0
const JUKE_FORWARD_COST := 0.94
const JUKE_STEER_LOCK := 0.35

## Body roll, purely presentational, but it is the cue a defender will read later.
const MAX_LEAN := 0.30
const LEAN_RESPONSE := 9.0

## Hurdle: a leap you commit your whole body to. The vertical impulse comes from
## the vertical jump measurement, but a running hurdle only converts part of that
## standing power into height - the rest goes into keeping your speed. Once the
## feet leave the turf nothing may be planted or cut, so the whole jump is a
## commitment measured in metres travelled, not in a dice roll.
const HURDLE_CLEARANCE_SCALE := 0.53   ## share of standing vertical usable at a run
const HURDLE_DRIVE_COST := 0.97        ## the plant costs a little drive
const HURDLE_AIR_STEER := 0.20         ## fraction of ground acceleration available airborne
const HURDLE_LANDING_STEER := 0.45
const HURDLE_LANDING_BASE := 0.10      ## seconds of absorption, minimum
const HURDLE_LANDING_PER_MPS := 0.030  ## extra absorption per m/s of impact
const HURDLE_LANDING_SPEED_COST := 0.035  ## drive lost per m/s of impact
const HURDLE_COOLDOWN := 0.30
const AIR_PITCH := 0.34                ## radians the body tilts forward in flight

## Dive: leave your feet and go horizontal. The launch buys reach - you cover
## more ground than running for the same beat - and the price is that you are not
## a runner again until you are back on your feet. Nothing about it is a roll:
## the slide is turf friction acting on the momentum you actually carried in.
const DIVE_PUSH_MPS := 1.2             ## extra forward speed the push adds
const DIVE_MIN_LAUNCH := 4.0           ## a dive from a standstill is still a lunge
const DIVE_LIFT_MPS := 2.1             ## a real hop, not a shuffle: ~0.22 m of rise
const DIVE_SLIDE_FRICTION := 11.0      ## pads digging into turf
const DIVE_SLIDE_MAX_TIME := 0.20
const DIVE_SLIDE_END_SPEED := 2.5
const DIVE_GETUP_TIME := 0.45
const DIVE_GETUP_FRICTION := 30.0      ## hands plant, feet come back under you
const DIVE_COOLDOWN := 0.20
const DIVE_PITCH_RAD := 1.50           ## ~86 degrees: body flat, not head-first
const DIVE_PITCH_RATE := 12.0          ## once the body is on the ground
const DIVE_AIR_PITCH_RATE := 6.5       ## in flight: rotate across the whole hop
const DIVE_GETUP_PITCH_RATE := 7.0     ## stand up over the recovery, not instantly
const DIVE_LAND_BLEND := 0.12          ## seconds to settle the mesh onto the turf

## Slide (QB): feet-first, protective. Same button as the dive.
const SLIDE_PUSH_MPS := 0.6
const SLIDE_LIFT_MPS := 0.9
const SLIDE_SLIDE_FRICTION := 16.0
const SLIDE_SLIDE_MAX_TIME := 0.16
const SLIDE_SLIDE_END_SPEED := 1.8
const SLIDE_GETUP_TIME := 0.28
const SLIDE_GETUP_FRICTION := 36.0
const SLIDE_COOLDOWN := 0.16
const SLIDE_PITCH_RAD := 1.35
const SLIDE_PITCH_RATE := 18.0
const SLIDE_AIR_PITCH_RATE := 11.0
const SLIDE_MIN_SPEED := 2.0
const SLIDE_MIN_LAUNCH := 3.2

@export var measurables: PlayerMeasurables
@export var player_id: String = ""
@export var is_user_controlled: bool = false
@export_range(0.0, 1.0) var effort: float = 1.0
@export var sprint_mult: float = 1.22

var facing: Vector3 = Vector3.FORWARD

# --- runtime state (readable by other systems, e.g. tackling) ---
var is_spinning: bool = false
var spin_charge: float = 1.0        ## 1 = fully effective, decays toward 0 while spinning
var is_planting: bool = false
var plant_charge: float = 1.0       ## how well the foot is set during a cut
var is_juking: bool = false
var last_juke_direction: int = 0    ## -1 left, +1 right
var is_airborne: bool = false
var is_landing: bool = false
var lean: float = 0.0               ## -1 = rolled left, +1 = rolled right
var air_pitch: float = 0.0          ## 0 = upright, 1 = fully tucked
var last_jump_clearance: float = 0.0
var last_air_time: float = 0.0
var last_landing_impact: float = 0.0
var last_cut_angle: float = 0.0
var cuts_this_play: int = 0

## Dive phases. The body is on the ground for all of them; only AIR has it off.
enum DivePhase { NONE, AIR, SLIDE, GETUP }
enum DiveType { NONE, DIVE, SLIDE }
var dive_phase: int = DivePhase.NONE
var dive_type: int = DiveType.NONE
var dive_distance: float = 0.0
var last_dive_distance: float = 0.0

var _spin_timer: float = 0.0
var _spin_cooldown: float = 0.0
var _spin_sign: float = 1.0
var _plant_timer: float = 0.0
var _plant_cooldown: float = 0.0
var _juke_vel: Vector3 = Vector3.ZERO   ## momentum from the push, scrubbed by turf
var _juke_timer: float = 0.0
var _juke_cooldown: float = 0.0
var _landing_timer: float = 0.0
var _hurdle_cooldown: float = 0.0
var _air_time: float = 0.0
var _dive_pitch: float = 0.0
var _dive_ground_blend: float = 0.0
var _dive_timer: float = 0.0
var _dive_air_timer: float = 0.0
var _dive_cooldown: float = 0.0
var _dive_start_pos: Vector3 = Vector3.ZERO
var _shape_node: CollisionShape3D
var _stand_shape: Shape3D
var _dive_shape: CapsuleShape3D
var _dive_drop: float = 0.605
var _stand_half: float = 0.925
var _prev_move_dir: Vector3 = Vector3.ZERO
@onready var _visual: Node3D = get_node_or_null("Visual") as Node3D

func _ready() -> void:
	if measurables == null:
		measurables = PlayerMeasurables.new()
	measurables.compute()
	if player_id == "":
		player_id = str(get_instance_id())

	# Standing body is a tall capsule. Diving swaps in a short horizontal one so
	# the body is genuinely low to the turf instead of standing upright through
	# the dive. The origin never moves, so getting up cannot pop the body.
	_shape_node = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _shape_node != null:
		_stand_shape = _shape_node.shape
		var r := 0.32
		var h := 1.85
		if _stand_shape is CapsuleShape3D:
			r = (_stand_shape as CapsuleShape3D).radius
			h = (_stand_shape as CapsuleShape3D).height
		_dive_shape = CapsuleShape3D.new()
		_dive_shape.radius = r
		_dive_shape.height = maxf(h * 0.84, r * 2.0)
		_dive_drop = h * 0.5 - r
		_stand_half = h * 0.5

func _physics_process(delta: float) -> void:
	var health := HealthManager.get_state(player_id) as HealthState
	var traction := EnvironmentManager.traction
	var max_speed: float = measurables.top_speed_mps * health.top_speed_modifier()
	if is_user_controlled and Input.is_action_pressed("sprint"):
		max_speed *= sprint_mult

	# The juke burst is momentum the feet did not have to earn this frame, so it
	# rides on top of the force budget instead of being clamped by it. Invariant:
	# velocity.xz == self-powered velocity + _juke_vel, at all times.
	var wish := _read_input() if is_user_controlled else Vector3.ZERO
	if _juke_timer > 0.0:
		wish *= JUKE_STEER_LOCK
	if _landing_timer > 0.0:
		wish *= HURDLE_LANDING_STEER
	if dive_phase != DivePhase.NONE:
		wish = Vector3.ZERO  # on the ground or in the air: nothing to steer with

	_tick_timers(delta)
	_handle_spin_input(delta, _self_velocity(), wish)
	_handle_juke_input()
	_handle_hurdle_input()
	_handle_dive_input()

	# Derive the force budget AFTER the timers and the move inputs, so a juke that
	# just fired is already subtracted out of the budget it was paid from.
	var burst := _juke_vel
	var current := _self_velocity()
	var speed := current.length()

	# ---- Dive: all of your momentum, none of your control -----------------
	if dive_phase != DivePhase.NONE:
		current = _resolve_dive(current, delta)
	# ---- Spin: momentum is preserved, steering is not --------------------
	elif is_spinning:
		var spin_rate := (PI * 1.15) / SPIN_DURATION * _spin_sign
		current = current.rotated(Vector3.UP, spin_rate * delta)
		# Friction on a single planted foot is worse than two.
		current *= 1.0 - (0.35 * delta / SPIN_DURATION)
		spin_charge = maxf(spin_charge - delta / SPIN_DURATION, 0.0)
		# Spinning costs you your lateral push.
		var drift := wish * max_speed * SPIN_LATERAL_LOCK * delta * 2.0
		current += drift
		current = current.limit_length(max_speed)
	else:
		current = _resolve_movement(current, speed, wish, max_speed, health, traction, delta)

	velocity.x = current.x + burst.x
	velocity.z = current.z + burst.z

	var was_on_floor := is_on_floor()
	if not was_on_floor:
		velocity += PhysicsManager.gravity_vector() * delta
	# Capture the downward speed before the solver can zero it on contact.
	var fall_speed := maxf(-velocity.y, 0.0)

	move_and_slide()

	_update_air_state(was_on_floor, fall_speed, delta)
	_update_dive(delta)

	# Lean the body into travel. Turn rate comes from agility (3-cone/shuttle).
	# Facing chases the feet, not the juke slide: a juke is supposed to keep your
	# shoulders square while your feet go sideways, which is what a defender has
	# to read.
	var travel := Vector3(velocity.x, 0.0, velocity.z)
	var steer := _self_velocity()
	if steer.length() > 0.15:
		var turn := deg_to_rad(measurables.turn_rate_deg * (0.6 if is_spinning else 1.0))
		facing = facing.slerp(steer.normalized(), clampf(turn * delta, 0.0, 1.0))

	_update_lean(travel, max_speed, delta)

	# Point the visual body where the player is actually facing. This is purely
	# presentational - the capsule is radially symmetric, so the greybox adds a
	# shoulder bar and a floating chevron to make the front readable.
	if _visual != null:
		_visual.rotation.y = atan2(-facing.x, -facing.z)
		_visual.rotation.z = -lean * MAX_LEAN
		# Two things can tip the body: a hurdle's forward lean, or a dive that
		# puts it flat. They never stack - the larger pose wins.
		var hurdle_pitch := air_pitch * AIR_PITCH
		var dive_angle := _dive_pitch * (SLIDE_PITCH_RAD if dive_type == DiveType.SLIDE else DIVE_PITCH_RAD)
		var tilt := -maxf(hurdle_pitch, dive_angle)
		if dive_type == DiveType.SLIDE:
			tilt = maxf(-hurdle_pitch, _dive_pitch * 0.65)
		_visual.rotation.x = tilt
		# In flight the mesh rides with the body so the hop is actually visible.
		# It settles onto the turf only once the body starts coming down - pinning
		# it to the ground the whole time made the dive look like a bow.
		var rising := dive_phase == DivePhase.AIR and velocity.y > 0.0
		_dive_ground_blend = move_toward(_dive_ground_blend, 0.0 if rising else 1.0,
			delta / DIVE_LAND_BLEND)
		_visual.position = Vector3(0.0, _dive_visual_drop(dive_angle) * _dive_ground_blend, 0.0)
		# Tuck: the mesh compresses toward its own centre, so the feet come up.
		var tuck := 1.0 if dive_phase != DivePhase.NONE else lerpf(1.0, 0.90, air_pitch)
		_visual.scale = Vector3(1.0, tuck, 1.0)

	# Physical cost of the effort actually exerted this frame.
	var load := travel.length() / maxf(measurables.top_speed_mps, 0.1) * effort
	HealthManager.exert(player_id, load, delta)

## Velocity the feet are actually driving, i.e. everything except the decaying
## sideways push from a juke.
func _self_velocity() -> Vector3:
	return Vector3(velocity.x - _juke_vel.x, 0.0, velocity.z - _juke_vel.z)

## Core force budget. Splits the desired velocity into the component along the
## player's momentum and the component lateral to it, then limits each by what
## the body and the turf can actually deliver.
func _resolve_movement(
	current: Vector3,
	speed: float,
	wish: Vector3,
	max_speed: float,
	health: HealthState,
	traction: float,
	delta: float
) -> Vector3:
	if not is_on_floor():
		# Nothing to plant against. You can nudge your line in the air; you cannot
		# cut, brake or accelerate. Whatever momentum you jumped with is what you
		# land with, minus the air you spent.
		if wish == Vector3.ZERO:
			return current
		return current.move_toward(wish * max_speed, measurables.accel_mps2 * HURDLE_AIR_STEER * delta)

	if wish == Vector3.ZERO:
		var decel := measurables.decel_mps2 * traction
		return current.move_toward(Vector3.ZERO, decel * delta)

	var agility := clampf(measurables.turn_rate_deg / 200.0, 0.8, 1.25)
	var vdir := current.normalized() if speed > 0.15 else wish

	# --- Cut detection: a real change of direction while carrying speed ---
	var angle := rad_to_deg(vdir.angle_to(wish)) if speed > 0.15 else 0.0
	if _plant_timer <= 0.0 and _plant_cooldown <= 0.0 \
			and angle >= CUT_ANGLE_DEG and speed > measurables.top_speed_mps * 0.30:
		_begin_cut(angle, agility, traction)

	# --- Longitudinal: pushing forward / braking ---
	var accel_long := measurables.accel_mps2 * health.accel_modifier() * traction
	var target_long := wish.dot(vdir) * max_speed
	var new_speed := maxf(move_toward(speed, target_long, accel_long * delta), 0.0)

	# --- Lateral: this is what makes a cut feel like a cut ---
	var lat_dir := wish - vdir * wish.dot(vdir)
	var lat_desired := lat_dir * max_speed
	var accel_lat := measurables.accel_mps2 * 0.55 * agility * traction
	if is_planting:
		# A set foot can push harder sideways than it can accelerate forward.
		accel_lat *= 1.0 + 0.9 * plant_charge * agility
		plant_charge = maxf(plant_charge - delta / PLANT_TIME, 0.0)

	var lateral := current - vdir * speed
	lateral += lat_desired.limit_length(accel_lat * delta)
	# A hard plant scrubs the lateral drift you were carrying.
	if is_planting:
		lateral *= 1.0 - clampf(0.9 * delta / PLANT_TIME, 0.0, 0.9)

	var result := vdir * new_speed + lateral
	if result.length() > max_speed:
		result = result.normalized() * max_speed
	return result

func _begin_cut(angle: float, agility: float, traction: float) -> void:
	# Momentum you cannot keep. Steeper angle and worse footing cost more.
	var loss := sin(deg_to_rad(angle)) * (1.35 - 0.45 * agility) / maxf(traction, 0.4)
	loss = clampf(loss, 0.0, 0.55)
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	velocity.x *= 1.0 - loss
	velocity.z *= 1.0 - loss

	_plant_timer = PLANT_TIME
	_plant_cooldown = PLANT_TIME + PLANT_COOLDOWN
	plant_charge = clampf(agility * (1.0 - angle / 180.0) + 0.25, 0.2, 1.0)
	is_planting = true
	last_cut_angle = angle
	cuts_this_play += 1
	cut_performed.emit(angle, speed - Vector3(velocity.x, 0.0, velocity.z).length())

func _handle_spin_input(delta: float, current: Vector3, wish: Vector3) -> void:
	if _spin_cooldown > 0.0 or is_spinning or not is_on_floor():
		return
	if dive_phase != DivePhase.NONE:
		return
	if not Input.is_action_just_pressed("spin"):
		return
	var speed := current.length()
	if speed < measurables.top_speed_mps * 0.20:
		return  # you cannot spin out of a standstill

	# Spin away from the way the stick is going, which is how defenders get
	# their leverage broken. No stick input = spin right.
	_spin_sign = 1.0
	if wish != Vector3.ZERO and current.dot(wish) > 0.0:
		_spin_sign = -1.0

	is_spinning = true
	_spin_timer = SPIN_DURATION
	spin_charge = 1.0
	_scale_drive(1.0 - SPIN_SPEED_COST)
	spin_started.emit(int(_spin_sign))

## Apply a multiplicative cost to everything the body is carrying. Callers that
## re-cost velocity must route through this so the juke burst stays in sync.
func _scale_drive(f: float) -> void:
	velocity.x *= f
	velocity.z *= f
	_juke_vel *= f

func _tick_timers(delta: float) -> void:
	if _plant_cooldown > 0.0:
		_plant_cooldown -= delta
	if _plant_timer > 0.0:
		_plant_timer -= delta
		if _plant_timer <= 0.0:
			is_planting = false
	if _juke_cooldown > 0.0:
		_juke_cooldown -= delta
	if _hurdle_cooldown > 0.0:
		_hurdle_cooldown -= delta
	if _dive_cooldown > 0.0:
		_dive_cooldown -= delta
	if _landing_timer > 0.0:
		_landing_timer -= delta
		if _landing_timer <= 0.0:
			is_landing = false
	if _juke_timer > 0.0:
		_juke_timer -= delta
		if _juke_timer <= 0.0:
			is_juking = false
	if _juke_vel.length_squared() > 0.0001:
		if is_on_floor():
			# Turf friction eats the push. Nothing outlives ~0.5 s.
			var before := _juke_vel
			var decay := JUKE_DECAY_MPS2 * EnvironmentManager.traction
			_juke_vel = _juke_vel.move_toward(Vector3.ZERO, decay * delta)
			# Scrub the same amount off the real velocity so the two stay in sync.
			velocity.x -= before.x - _juke_vel.x
			velocity.z -= before.z - _juke_vel.z
	else:
		_juke_vel = Vector3.ZERO
	if is_spinning:
		_spin_timer -= delta
		if _spin_timer <= 0.0:
			is_spinning = false
			spin_charge = 0.0
			_spin_cooldown = SPIN_COOLDOWN
	elif _spin_cooldown > 0.0:
		_spin_cooldown -= delta

func _handle_juke_input() -> void:
	if not is_user_controlled or is_spinning:
		return
	# The stick is screen-relative but the push is body-relative, so translate.
	# Facing the camera would otherwise flip your jukes left for right.
	var body_right := facing.cross(Vector3.UP)
	if body_right.length_squared() < 0.0001:
		return
	var screen_right := _input_right()
	var side := 1.0 if screen_right.dot(body_right.normalized()) >= 0.0 else -1.0
	if Input.is_action_just_pressed("juke_right"):
		perform_juke(int(side))
	elif Input.is_action_just_pressed("juke_left"):
		perform_juke(int(-side))

## Push off the outside foot. Public because AI, coach mode and sim must all use
## the same move the player does. Returns false when the body could not do it.
func perform_juke(direction: int) -> bool:
	if direction == 0 or is_spinning or is_juking or is_landing:
		return false
	if _juke_cooldown > 0.0 or not is_on_floor() or dive_phase != DivePhase.NONE:
		return false

	var carried := Vector3(velocity.x - _juke_vel.x, 0.0, velocity.z - _juke_vel.z)
	if carried.length() < measurables.top_speed_mps * JUKE_MIN_SPEED_FRAC:
		return false  # you cannot juke out of a standstill

	var agility := clampf(measurables.turn_rate_deg / 200.0, 0.8, 1.25)
	var right := facing.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()

	# Weight transfer costs a little drive before the push lands. The push is added
	# to _juke_vel first so velocity and the burst never disagree about who owns
	# the sideways momentum - callers may invoke this outside _physics_process.
	_juke_vel += right * float(direction) * JUKE_BASE_MPS * agility
	velocity.x = carried.x * JUKE_FORWARD_COST + _juke_vel.x
	velocity.z = carried.z * JUKE_FORWARD_COST + _juke_vel.z

	is_juking = true
	_juke_timer = JUKE_DURATION
	_juke_cooldown = JUKE_COOLDOWN
	last_juke_direction = direction
	juke_performed.emit(direction)
	return true

func _handle_hurdle_input() -> void:
	if not is_user_controlled:
		return
	if Input.is_action_just_pressed("hurdle"):
		perform_hurdle()

## Leave the turf. Returns false if the body is not in a position to jump.
##
## There is no "hurdle over defender" check here and there never will be: the
## leap is a real impulse, so clearing a diving arm is decided by your clearance
## versus his height and by where the two of you actually are when he arrives.
func perform_hurdle() -> bool:
	if not is_on_floor() or is_spinning or is_landing or dive_phase != DivePhase.NONE:
		return false
	if _hurdle_cooldown > 0.0:
		return false

	var g := absf(PhysicsManager.gravity_vector().y)
	var clearance := (measurables.vertical_jump_cm / 100.0) * HURDLE_CLEARANCE_SCALE
	velocity.y = sqrt(2.0 * maxf(g, 0.1) * clearance)
	_scale_drive(HURDLE_DRIVE_COST)

	_hurdle_cooldown = HURDLE_COOLDOWN
	_plant_timer = 0.0
	is_planting = false
	air_pitch = 0.0
	last_jump_clearance = clearance
	last_air_time = 0.0
	_air_time = 0.0
	hurdled.emit(clearance)
	return true

## Tracks flight and turns touch-down into a real cost. The impact is whatever
## downward speed the body actually carried into the turf, so a hop landing on
## the run is cheap and a long jump landing flat-footed is not.
func _update_air_state(was_on_floor: bool, fall_speed: float, delta: float) -> void:
	var on_floor := is_on_floor()
	is_airborne = not on_floor
	if on_floor:
		if not was_on_floor:
			last_air_time = _air_time
			_air_time = 0.0
			# A dive's touchdown is not a landing: the slide already prices it.
			if fall_speed > 0.8 and dive_phase == DivePhase.NONE:
				_land(fall_speed)
		air_pitch = lerpf(air_pitch, 0.0, clampf(delta * 14.0, 0.0, 1.0))
	else:
		_air_time += delta
		air_pitch = lerpf(air_pitch, 1.0, clampf(delta * 12.0, 0.0, 1.0))

func _land(impact: float) -> void:
	last_landing_impact = impact
	var cost := clampf(impact * HURDLE_LANDING_SPEED_COST, 0.0, 0.30)
	_scale_drive(1.0 - cost)
	_landing_timer = clampf(
		HURDLE_LANDING_BASE + impact * HURDLE_LANDING_PER_MPS,
		HURDLE_LANDING_BASE, 0.35)
	is_landing = true
	landed.emit(impact, cost)

func _handle_dive_input() -> void:
	if not is_user_controlled:
		return
	if Input.is_action_just_pressed("dive"):
		var sprinting := Input.is_action_pressed("sprint")
		var base := Vector3(velocity.x, 0.0, velocity.z)
		var going := base.length() >= SLIDE_MIN_SPEED
		if sprinting and going:
			print("-> DIVE (head-first)")
			perform_dive()
		elif going:
			print("-> SLIDE (give-up)")
			perform_slide()
		else:
			print("-> DIVE (stand)")
			perform_dive()

## Leave your feet. Public for the same reason the juke is: a defender's dive
## tackle has to be the identical move, not a separate animation.
##
## The launch buys reach - you cover more ground than running for the same beat -
## and the price is that you are not a runner again until you are standing up.
func perform_dive() -> bool:
	if not is_on_floor() or is_spinning or is_landing:
		return false
	if dive_phase != DivePhase.NONE or _dive_cooldown > 0.0:
		return false

	var base := Vector3(velocity.x, 0.0, velocity.z)
	var speed := base.length()
	var dir := base.normalized() if speed > 0.5 else facing
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD

	# The juke burst is folded into the drive: from here on it is turf friction,
	# not the juke decay, that scrubs the momentum.
	_juke_vel = Vector3.ZERO
	var launch := maxf(speed + DIVE_PUSH_MPS, DIVE_MIN_LAUNCH)
	velocity.x = dir.x * launch
	velocity.z = dir.z * launch
	velocity.y = DIVE_LIFT_MPS

	_plant_timer = 0.0
	is_planting = false
	air_pitch = 0.0
	_dive_pitch = 0.0
	_dive_ground_blend = 0.0
	_dive_timer = 0.0
	_dive_air_timer = 0.0
	_dive_start_pos = global_position
	dive_phase = DivePhase.AIR
	dive_type = DiveType.DIVE
	_set_dive_shape(true)
	return true

func perform_slide() -> bool:
	if not is_on_floor() or is_spinning or is_landing:
		return false
	if dive_phase != DivePhase.NONE or _dive_cooldown > 0.0:
		return false
	var base := Vector3(velocity.x, 0.0, velocity.z)
	var speed := base.length()
	if speed < SLIDE_MIN_SPEED:
		return false
	var dir := base.normalized()
	if dir.length_squared() < 0.0001:
		dir = facing
	_juke_vel = Vector3.ZERO
	var launch := maxf(speed + SLIDE_PUSH_MPS, SLIDE_MIN_LAUNCH)
	velocity.x = dir.x * launch
	velocity.z = dir.z * launch
	velocity.y = SLIDE_LIFT_MPS
	_plant_timer = 0.0
	is_planting = false
	air_pitch = 0.0
	_dive_pitch = 0.0
	_dive_ground_blend = 0.0
	_dive_timer = 0.0
	_dive_air_timer = 0.0
	_dive_start_pos = global_position
	dive_phase = DivePhase.AIR
	dive_type = DiveType.SLIDE
	_set_dive_shape(true)
	return true

## Swap the tall standing capsule for a short horizontal one. The body origin is
## left exactly where it is, so standing back up can never pop it out of the turf.
func _set_dive_shape(active: bool) -> void:
	if _shape_node == null or _stand_shape == null:
		return
	if active and _dive_shape != null:
		_shape_node.shape = _dive_shape
		_shape_node.position = Vector3(0.0, -_dive_drop, 0.0)
		_update_dive_shape_yaw()
	else:
		_shape_node.shape = _stand_shape
		_shape_node.position = Vector3.ZERO
		_shape_node.rotation = Vector3.ZERO

func _update_dive_shape_yaw() -> void:
	if _shape_node == null:
		return
	# Lie along the direction of travel, not along world Z.
	_shape_node.rotation = Vector3(PI * 0.5, atan2(-facing.x, -facing.z), 0.0)

## How far the visual mesh has to drop for the tipped capsule's lowest point to
## stay on the turf. Zero standing, -(half height - radius) when flat.
func _dive_visual_drop(angle: float) -> float:
	if _dive_shape == null:
		return 0.0
	return _stand_half * cos(angle) + _dive_shape.radius * sin(angle) - _stand_half

func _update_dive(delta: float) -> void:
	if dive_phase == DivePhase.NONE:
		dive_distance = 0.0
		return

	dive_distance = Vector2(global_position.x - _dive_start_pos.x, global_position.z - _dive_start_pos.z).length()
	_dive_timer += delta

	var slide_max := DIVE_SLIDE_MAX_TIME
	var slide_end := DIVE_SLIDE_END_SPEED
	var getup_time := DIVE_GETUP_TIME
	var air_rate := DIVE_AIR_PITCH_RATE
	var pitch_rate := DIVE_PITCH_RATE
	var getup_rate := DIVE_GETUP_PITCH_RATE
	var target_pitch_rad := DIVE_PITCH_RAD
	if dive_type == DiveType.SLIDE:
		slide_max = SLIDE_SLIDE_MAX_TIME
		slide_end = SLIDE_SLIDE_END_SPEED
		getup_time = SLIDE_GETUP_TIME
		air_rate = SLIDE_AIR_PITCH_RATE
		pitch_rate = SLIDE_PITCH_RATE
		getup_rate = SLIDE_PITCH_RATE
		target_pitch_rad = SLIDE_PITCH_RAD

	match dive_phase:
		DivePhase.AIR:
			_dive_air_timer += delta
			if is_on_floor() and _dive_air_timer > 0.04:
				dive_phase = DivePhase.SLIDE
				_dive_timer = 0.0
		DivePhase.SLIDE:
			_update_dive_shape_yaw()
			if _dive_timer > slide_max or _self_velocity().length() < slide_end:
				dive_phase = DivePhase.GETUP
				_dive_timer = 0.0
		DivePhase.GETUP:
			target_pitch_rad = 0.0
			if _dive_timer >= getup_time:
				_finish_dive()

	var rate := pitch_rate
	var target_norm := 1.0
	if dive_phase == DivePhase.GETUP:
		rate = getup_rate
		target_norm = 0.0
	elif dive_phase == DivePhase.AIR:
		rate = air_rate
		target_norm = target_pitch_rad / DIVE_PITCH_RAD
	else:
		target_norm = target_pitch_rad / DIVE_PITCH_RAD
	_dive_pitch = lerpf(_dive_pitch, target_norm, clampf(delta * rate, 0.0, 1.0))

func _finish_dive() -> void:
	var was_slide := dive_type == DiveType.SLIDE
	_set_dive_shape(false)
	dive_phase = DivePhase.NONE
	dive_type = DiveType.NONE
	_dive_cooldown = SLIDE_COOLDOWN if was_slide else DIVE_COOLDOWN
	_dive_pitch = 0.0
	last_dive_distance = dive_distance
	dove.emit(last_dive_distance)

func _resolve_dive(current: Vector3, delta: float) -> Vector3:
	if dive_phase == DivePhase.AIR:
		return current
	var friction := DIVE_GETUP_FRICTION if dive_phase == DivePhase.GETUP else DIVE_SLIDE_FRICTION
	if dive_type == DiveType.SLIDE:
		friction = SLIDE_GETUP_FRICTION if dive_phase == DivePhase.GETUP else SLIDE_SLIDE_FRICTION
	return current.move_toward(Vector3.ZERO, friction * EnvironmentManager.traction * delta)

## Roll the body toward the direction the feet are actually sliding.
func _update_lean(travel: Vector3, max_speed: float, delta: float) -> void:
	var right := facing.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		return
	var lateral := travel.dot(right.normalized())
	var ratio := clampf(lateral / maxf(max_speed, 1.0), -1.0, 1.0)
	# Square-root curve so a 20-25 degree juke still reads as a lean instead of
	# vanishing into rounding error on a greybox capsule.
	var target := signf(ratio) * sqrt(absf(ratio))
	lean = lerpf(lean, target, clampf(delta * LEAN_RESPONSE, 0.0, 1.0))

func _read_input() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	# Input is screen-relative, not world-relative: "right" must mean right on
	# screen no matter which way the body or the camera happens to be pointing.
	var dir := _input_right() * v.x + _input_forward() * (-v.y)
	return dir.limit_length(1.0)

## Ground-projected camera basis. Falls back to world axes when there is no
## camera (headless tests, sim-only runs).
func _input_right() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.RIGHT
	var r := cam.global_transform.basis.x
	r.y = 0.0
	return r.normalized() if r.length_squared() > 0.0001 else Vector3.RIGHT

func _input_forward() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.FORWARD
	var f := -cam.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD

## Speed readout in mph, used by the debug HUD.
func speed_mph() -> float:
	return Vector3(velocity.x, 0.0, velocity.z).length() * 2.23694
