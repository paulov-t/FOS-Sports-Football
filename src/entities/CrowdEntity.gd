class_name CrowdEntity
extends Node3D
## Spawns a stadium-style crowd of bouncing spheres using a single MultiMesh.
## All bouncing happens in the vertex shader, so there is zero per-frame script cost.
##
## Usage: attach to a Node3D, press play. Tweak the exports in the Inspector.

@export_group("Layout")
@export var rows: int = 30
@export var columns: int = 80
## x = distance between spectators in a row, y = distance between rows
@export var spacing: Vector2 = Vector2(0.8, 1.0)
## How much each row is raised above the previous one (stand slope)
@export var row_rise: float = 0.45
## Random offset applied to each spectator so the grid doesn't look perfect
@export var position_jitter: float = 0.1

@export_group("Look")
@export var sphere_radius: float = 0.3
@export var seed_value: int = 12345

@export_group("Bounce")
@export var bounce_height: float = 0.25
@export var bounce_speed: float = 6.0
## 0 = standing still, 1 = full bounce. Can be changed at runtime.
@export_range(0.0, 1.0) var excitement: float = 1.0:
	set(value):
		excitement = value
		if _material:
			_material.set_shader_parameter("excitement", excitement)

var _material: ShaderMaterial

const SHADER_CODE := """
shader_type spatial;

uniform float bounce_height = 0.25;
uniform float bounce_speed = 6.0;
uniform float excitement : hint_range(0.0, 1.0) = 1.0;

varying vec3 tint;

void vertex() {
	// INSTANCE_CUSTOM: r = phase offset, g = speed variation
	float phase = INSTANCE_CUSTOM.r * 6.28318;
	float speed = bounce_speed * (0.8 + INSTANCE_CUSTOM.g * 0.4);

	// abs(sin()) gives a bouncing motion rather than a smooth wave
	float bounce = abs(sin(TIME * speed + phase));
	VERTEX.y += bounce * bounce_height * excitement;

	// With use_colors enabled, COLOR holds the per-instance colour
	tint = COLOR.rgb;
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.8;
}
"""


func _ready() -> void:
	_spawn_crowd()


func _spawn_crowd() -> void:
	# --- Mesh ---
	var mesh := SphereMesh.new()
	mesh.radius = sphere_radius
	mesh.height = sphere_radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6

	# --- Material (shader is embedded above) ---
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("bounce_height", bounce_height)
	_material.set_shader_parameter("bounce_speed", bounce_speed)
	_material.set_shader_parameter("excitement", excitement)
	mesh.material = _material

	# --- MultiMesh ---
	# Format flags must be set BEFORE instance_count.
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = rows * columns

	# Fixed seed so the crowd looks the same every run
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var index := 0
	for row in rows:
		for col in columns:
			var pos := Vector3(
				(col - columns * 0.5) * spacing.x + rng.randf_range(-position_jitter, position_jitter),
				row * row_rise + sphere_radius,
				row * spacing.y + rng.randf_range(-position_jitter, position_jitter)
			)
			multimesh.set_instance_transform(index, Transform3D(Basis(), pos))

			# Random shirt colour per spectator
			multimesh.set_instance_color(index, Color.from_hsv(
				rng.randf(),
				rng.randf_range(0.4, 0.8),
				rng.randf_range(0.6, 1.0)
			))

			# r = bounce phase offset, g = bounce speed variation
			multimesh.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), 0.0, 0.0))

			index += 1

	# --- Instance node ---
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = multimesh
	# The bounce happens in the shader, which the engine's culling doesn't know about,
	# so pad the bounds a little to avoid pop-out at screen edges.
	mmi.extra_cull_margin = bounce_height + 0.5
	add_child(mmi)
