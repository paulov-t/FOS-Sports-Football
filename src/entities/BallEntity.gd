class_name BallEntity
extends RigidBody3D
## Physics-driven football. Can be held/attached to a player or move freely as
## a projectile under gravity and collision.

signal caught(player: PlayerEntity)
signal dropped()
signal carried(player: PlayerEntity)
signal loose()

@export var ballShape: BallShapeType.BallShape = BallShapeType.BallShape.USFootball
@export var mass_kg: float = 0.43  # regulation football ~14-15 oz
@export var linear_dampening: float = 0.01
@export var angular_dampening: float = 0.02
@export var bounce: float = 0.9
@export var friction: float = 0.8

var carrier: PlayerEntity = null
var is_attached: bool = false

var _attach_offset: Vector3 = Vector3(0.0, 0.9, 0.4)  # in carrier's local space
var _attach_remote: RemoteTransform3D

func _ready() -> void:
	mass = mass_kg
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = linear_dampening
	angular_damp = angular_dampening

	# Generate the Ball Shape
	match ballShape:
		BallShapeType.BallShape.USFootball:
			# Ensure collision shape exists
			if get_node_or_null("CollisionShape3D") == null:
				var col := CollisionShape3D.new()
				var shape := CapsuleShape3D.new()
				shape.radius = 0.11
				shape.height = 0.22
				col.shape = shape
				add_child(col)
			
			# Ensure mesh exists
			if get_node_or_null("MeshInstance3D") == null:
				var mesh_inst := MeshInstance3D.new()
				var mesh := CapsuleMesh.new()
				mesh.radius = 0.11
				mesh.height = 0.22
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.6, 0.35, 0.1, 1)
				mesh.material = mat
				mesh_inst.mesh = mesh
				add_child(mesh_inst)
		BallShapeType.BallShape.Sphere:
			# Ensure collision shape exists
			if get_node_or_null("CollisionShape3D") == null:
				var col := CollisionShape3D.new()
				var shape := SphereShape3D.new()
				shape.radius = 0.11
				col.shape = shape
				add_child(col)
			
			# Ensure mesh exists
			if get_node_or_null("MeshInstance3D") == null:
				var mesh_inst := MeshInstance3D.new()
				var mesh := SphereMesh.new()
				mesh.radius = 0.11
				mesh.height = 0.22
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.6, 0.35, 0.1, 1)
				mesh.material = mat
				mesh_inst.mesh = mesh
				add_child(mesh_inst)
	
	# Set up physics layers
	collision_layer = 4  # layer 3 is ball per project settings
	collision_mask = 1 | 2 | 4 | 8  # world, players, ball, environment


func attach_to(player: PlayerEntity, offset: Vector3 = Vector3.ZERO) -> void:
	if carrier != null or player == null:
		return
	
	carrier = player
	is_attached = true
	freeze = true
	sleeping = true
	gravity_scale = 0.0
	set_deferred("axis_lock_linear_x", true)
	set_deferred("axis_lock_linear_y", true)
	set_deferred("axis_lock_linear_z", true)
	set_deferred("axis_lock_angular_x", true)
	set_deferred("axis_lock_angular_y", true)
	set_deferred("axis_lock_angular_z", true)
	
	if offset != Vector3.ZERO:
		_attach_offset = offset
	
	# Attach to player
	if _attach_remote == null:
		_attach_remote = RemoteTransform3D.new()
		add_child(_attach_remote)
	_attach_remote.remote_path = player.get_path()
	_attach_remote.position = _attach_offset
	_attach_remote.rotation = Vector3.ZERO
	
	carried.emit(player)


func detach(force_velocity: Vector3 = Vector3.ZERO) -> void:
	if not is_attached or carrier == null:
		return
	
	if _attach_remote != null:
		_attach_remote.remote_path = NodePath("")
		_attach_remote.position = Vector3.ZERO
	
	carrier = null
	is_attached = false
	
	# Re-enable physics
	freeze = false
	sleeping = false
	gravity_scale = 1.0
	axis_lock_linear_x = false
	axis_lock_linear_y = false
	axis_lock_linear_z = false
	axis_lock_angular_x = false
	axis_lock_angular_y = false
	axis_lock_angular_z = false
	
	if force_velocity != Vector3.ZERO:
		linear_velocity = force_velocity
	else:
		# Inherit velocity from carrier
		linear_velocity = carrier.velocity if carrier != null else Vector3.ZERO
	
	dropped.emit()
	loose.emit()


func is_carried() -> bool:
	return is_attached and carrier != null


func get_carrier() -> PlayerEntity:
	return carrier


func throw(direction: Vector3, speed: float = 15.0, loft: float = 0.3) -> void:
	if is_attached:
		detach()
	
	var throw_velocity := direction.normalized() * speed
	throw_velocity.y += speed * loft
	linear_velocity = throw_velocity
	angular_velocity = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))


func hand_off(to_player: PlayerEntity) -> void:
	if is_attached and carrier != null and to_player != null:
		detach()
		attach_to(to_player)
