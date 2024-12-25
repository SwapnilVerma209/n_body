extends MeshInstance3D

@export var mass: float
@export var radius: float
@export var velocity: Vector3
var _newton_grav_pot: float
var _newton_grav_field: Vector3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func newton_field_and_potential_at(other_position: Vector3) -> Array:
	var vector_to := other_position - position
	var distance := vector_to.length()
	var potential = - $Simulation.grav_const * mass / distance
	var field = potential / (distance**2) * vector_to
	return [field, potential]

func _get_newton_field_and_potential_from(other) -> void:
	var field_and_potential = other.newton_field_and_potential_at(position)
	var field = field_and_potential[0]
	var potential = field_and_potential[1]
	_newton_grav_field += field
	_newton_grav_pot += potential
