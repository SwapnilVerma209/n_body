extends MeshInstance3D

@export var mass: float
@export var rest_radius: float
@export var coord_velocity: Vector3
var _coord_lorentz_recip: float
var _length_scales: Vector3
var _grav_field: Vector3
var _grav_potential: float
var _escape_velocity: Vector3
var _esc_lorentz_recip: float
var _infalling_vel: Vector3
var _infall_lorentz_recip: float
var infall_lorentz_sig_change: bool

## Creates a new body with a given mass, radius, position, and velocity based on
## the scaled units. Initial values assume no gravitational influences
func _init(mass: float, radius: float, position: Vector3, coord_velocity: Vector3):
	self.mass = mass
	self.rest_radius = radius
	mesh.radius = radius
	mesh.height = 2.0 * radius
	self.position = position
	self.coord_velocity = coord_velocity
	_reset()

## Calculates and returns the gravitational field and potential caused by this
## body at other_postion. The values are expressed as those in the rest frame of
## an observer at other_position and at rest relative to the coordinate origin,
## based on the scaled units
func grav_field_and_potential_at(other_position: Vector3) -> Array:
	var vector_to_other := other_position - position
	var distance := vector_to_other.length()
	var field = (-Global.grav_const * mass / \
			(distance**3.0 * _esc_lorentz_recip) * vector_to_other) * \
			_infall_lorentz_recip
	var field_parallel = field.project(coord_velocity)
	var field_orthogonal = field - field_parallel
	field = field_parallel + (field_orthogonal / _coord_lorentz_recip)
	var potential = -field.length() * distance
	return [field, potential]

## Calibrates the body based on length contraction, escape velocity, and
## infalling velocity. To be called after all gravitational fields and potentials
## are added. After this, if infall_lorentz_sig_change is true, then the fields
## and potentials must be recalculated for all particles directly interacting
## with it
func calibrate() -> void:
	_calc_length_contraction()
	_calc_esc_velocity()
	_calc_infalling_vel()

## Move the body to its new position, and calculate its new velocity
func move(coord_timestep: float) -> void:
	var local_timestep := coord_timestep * _esc_lorentz_recip
	position += coord_velocity * local_timestep
	coord_velocity = Global.relativistic_vel_add(_grav_field * local_timestep, \
			coord_velocity)

## Calculates the radius in the direction of the given position
func get_radius_towards(other_position: Vector3) -> float:
	var vector_to_other := other_position - position
	var radius_vector := rest_radius * vector_to_other.normalized()
	radius_vector.x *= _length_scales.x
	radius_vector.y *= _length_scales.y
	radius_vector.z *= _length_scales.z
	return radius_vector.length()

## Returns true if this body is colliding with the other body, false otherwise
func is_colliding_with(other) -> bool:
	var vector_to_other = other.position - position
	var distance = vector_to_other.length()
	return distance <= get_radius_towards(other.position) + \
			other.get_radius_towards(position)

func absorb(other) -> void:
	var new_mass = mass + other.mass
	var new_position := get_center_of_mass_with(other)
	var new_coord_momentum = get_coord_momentum() + other.get_coord_momentum()
	var new_coord_momentum_mag = new_coord_momentum.length()
	var new_coord_speed = new_coord_momentum_mag / \
			sqrt(new_mass**2.0 + (new_coord_momentum_mag / Global.light_speed)**2.0)
	if new_coord_speed > Global.max_speed:
		new_coord_speed = Global.max_speed
	var new_coord_velocity = new_coord_speed * new_coord_momentum.normalized()
	var new_rest_radius = (rest_radius**3.0 + other.rest_radius**3.0) ** \
			(1.0 / 3.0)
	mass = new_mass
	position = new_position
	coord_velocity = new_coord_velocity
	rest_radius = new_rest_radius

func get_relativistic_mass() -> float:
	return mass / _infall_lorentz_recip

func get_center_of_mass_with(other) -> Vector3:
	var self_rel_mass := get_relativistic_mass()
	var other_rel_mass = other.get_relativistic_mass()
	var total_rel_mass = self_rel_mass + other_rel_mass
	return (self_rel_mass * position + other_rel_mass * other.position) / \
			total_rel_mass

func get_coord_momentum() -> Vector3:
	return mass * coord_velocity / _coord_lorentz_recip

func _reset() -> void:
	_calc_length_contraction()
	_grav_field = Vector3(0.0, 0.0, 0.0)
	_grav_potential = 0.0
	_escape_velocity = Vector3(0.0, 0.0, 0.0)
	_esc_lorentz_recip = 1.0
	_infalling_vel = coord_velocity
	_infall_lorentz_recip = _coord_lorentz_recip
	infall_lorentz_sig_change = true

## Calculates the length contraction factors and saves the coordinate lorentz
## factor for gravitational field calculation
func _calc_length_contraction():
	_coord_lorentz_recip = Global.lorentz_fact_recip(coord_velocity)
	_length_scales = coord_velocity.normalized() * _coord_lorentz_recip
	_length_scales.x = abs(_length_scales.x)
	_length_scales.y = abs(_length_scales.y)
	_length_scales.z = abs(_length_scales.z)

## Adds the contribution to the gravitational field and potential by the other 
## body
func _add_grav_field_and_potential(other) -> void:
	var field_and_potential = other.grav_field_and_potential_at(position)
	var field = field_and_potential[0]
	var potential = field_and_potential[1]
	_grav_field += field
	_grav_potential += potential

## Calculates the escape velocity. Set in opposite direction of net gravitational
## field by default. If there is no net gravitational field, it is set in either
## the direction of the body's instantaneous velocity or towards negative x if
## that is also zero. If the speed reaches or exceeds a max speed defined in the
## global file, then it is set to that speed, and the net gravitational field is
## set to zero. This is to prevent infinities at the event horizons of black
## holes.
func _calc_esc_velocity() -> void:
	var escape_speed := sqrt(-2.0 * _grav_potential)
	if _grav_field.is_zero_approx():
		if coord_velocity.is_zero_approx():
			_escape_velocity = escape_speed * Vector3(-1.0, 0.0, 0.0)
		else:
			_escape_velocity = escape_speed * coord_velocity.normalized()
	else:
		_escape_velocity = escape_speed * -_grav_field.normalized()
	if escape_speed >= Global.max_speed:
		_escape_velocity = Global.max_speed * _escape_velocity.normalized()
		_grav_field = Vector3(0.0, 0.0, 0.0)
	_esc_lorentz_recip = Global.lorentz_fact_recip(_escape_velocity)

## Calculates the velocity of the body in the frame of reference of an observer
## falling at the escape speed towards the body at the location. Saves this 
func _calc_infalling_vel() -> void:
	_infalling_vel = Global.relativistic_vel_add(_escape_velocity, \
			coord_velocity)
	var new_infall_lorentz_recip = Global.lorentz_fact_recip(_infalling_vel)
	infall_lorentz_sig_change = \
			abs(1.0 - new_infall_lorentz_recip / _infall_lorentz_recip) >= 1e-9
	_infall_lorentz_recip = new_infall_lorentz_recip
