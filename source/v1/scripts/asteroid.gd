extends Node3D
class_name HoldRock
## One hazard type for the slice. Growth hook: hazard_type for later variants.
## Asteroids are moved toward the camera by main.gd (the world rushes, the ship stays near z = 0).

@export var hazard_type: String = "rock"
@export var spin_speed := Vector3(0.5, 0.9, 0.3)
var radius := 1.0 ## collision radius in metres (slightly forgiving vs. the mesh)

func _ready() -> void:
	add_to_group("asteroid")

func _process(delta: float) -> void:
	rotate_x(spin_speed.x * delta)
	rotate_y(spin_speed.y * delta)
	rotate_z(spin_speed.z * delta)
