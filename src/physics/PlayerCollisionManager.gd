class_name PlayerCollisionManager
extends Node
## Deterministic player-vs-player contact.
##
## Players are CharacterBody3D nodes, so Godot's kinematic solver only knows how
## to stop them against static geometry. This node runs after every player has
## moved and exchanges momentum using mass, closing speed, contact angle,
## strength, footing and the surface's traction. There is no tackle roll and no
## hidden win/lose check.
##
## The players are kept off each other's collision masks, so this solver owns all
## body-to-body contact. That is what makes momentum transfer possible instead of
## both bodies simply stopping.

signal impact_resolved(info: Dictionary)

@export var restitution: float = 0.08
@export var min_closing_speed: float = 0.75
@export var separation_bias: float = 0.75
@export var impulse_scale: float = 1.0
@export var max_delta_v: float = 9.0
## After a real hit, do not fire another impulse for this long. Sustained
## leaning is handled by positional separation, not by a new collision every
## physics frame.
@export var impact_cooldown: float = 0.22

var players: Array[PlayerEntity] = []
var last_impact: Dictionary = {}
var impact_count: int = 0
var _last_impact_time: Dictionary = {}

func _ready() -> void:
	# Players run at priority 0; resolve after they have moved.
	process_physics_priority = 10

func register(p: PlayerEntity) -> void:
	if p != null and not players.has(p):
		players.append(p)

func reset() -> void:
	last_impact.clear()
	_last_impact_time.clear()
	impact_count = 0

func _physics_process(_delta: float) -> void:
	for i in range(players.size()):
		for j in range(i + 1, players.size()):
			_resolve_pair(players[i], players[j])

func _resolve_pair(a: PlayerEntity, b: PlayerEntity) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return

	var pa := a.collision_center()
	var pb := b.collision_center()
	var offset := pb - pa
	offset.y = 0.0
	var distance := offset.length()
	var radius_sum := a.collision_radius() + b.collision_radius()
	if distance >= radius_sum:
		return
	if a.collision_bottom() > b.collision_top() or b.collision_bottom() > a.collision_top():
		return

	var normal := offset / distance if distance > 0.001 else Vector3.RIGHT
	var penetration := radius_sum - distance

	var mass_a := maxf(a.measurables.mass_kg, 1.0)
	var mass_b := maxf(b.measurables.mass_kg, 1.0)
	var inv_a := 1.0 / mass_a
	var inv_b := 1.0 / mass_b
	var inv_sum := inv_a + inv_b
	if inv_sum <= 0.0:
		return

	# Separate first so the next frame starts from a valid pose. The bias leaves
	# a little overlap, which keeps contact continuous instead of popping.
	var correction := normal * penetration * separation_bias
	a.global_position -= correction * (inv_a / inv_sum)
	b.global_position += correction * (inv_b / inv_sum)

	# Still separate on every frame, but do not count a new hit until the pair
	# has had time to recover. Without this, leaning on a body re-fires a tiny
	# impulse every physics frame.
	var pair_key := "%s|%s" % [a.player_id, b.player_id]
	var now := Time.get_ticks_msec()
	if _last_impact_time.has(pair_key) \
			and now - int(_last_impact_time[pair_key]) < int(impact_cooldown * 1000.0):
		return

	var va := Vector3(a.velocity.x, 0.0, a.velocity.z)
	var vb := Vector3(b.velocity.x, 0.0, b.velocity.z)
	var closing := (va - vb).dot(normal)
	if closing <= min_closing_speed:
		return

	# Standard impulse along the contact normal using real masses.
	var j := (1.0 + restitution) * closing / inv_sum * impulse_scale

	# Strength, footing and facing redistribute the result. A braced, strong
	# body keeps more of its velocity; a light, airborne or slipping body gives
	# more. Traction is already folded into effective_collision_mass().
	var m_eff_a := a.effective_collision_mass(normal)
	var m_eff_b := b.effective_collision_mass(-normal)
	var advantage := clampf(m_eff_a / maxf(m_eff_b, 0.1), 0.5, 2.0)
	var asym := sqrt(advantage)

	var dv_a := -normal * (j * inv_a) / asym
	var dv_b := normal * (j * inv_b) * asym
	if dv_a.length() > max_delta_v:
		dv_a = dv_a.normalized() * max_delta_v
	if dv_b.length() > max_delta_v:
		dv_b = dv_b.normalized() * max_delta_v

	a.apply_impact(dv_a, b)
	b.apply_impact(dv_b, a)

	_last_impact_time[pair_key] = now
	impact_count += 1
	last_impact = {
		"a": a,
		"b": b,
		"a_id": a.player_id,
		"b_id": b.player_id,
		"closing": closing,
		"impulse": j,
		"dv_a": dv_a.length(),
		"dv_b": dv_b.length(),
		"m_eff_a": m_eff_a,
		"m_eff_b": m_eff_b,
		"normal": normal,
		"time": now,
	}
	impact_resolved.emit(last_impact)
