class_name Body
extends MeshInstance3D

const body_scene := preload("res://body.tscn")

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
var needs_recalibration: bool
var is_black_hole: bool
var should_be_deleted: bool

## Creates a new body with a given mass, radius, position, and velocity based on
## the scaled units. Initial values assume no gravitational influences
static func new_body(mass: float, radius: float, position: Vector3, \
		coord_velocity: Vector3) -> Body:
	var body := body_scene.instantiate()
	body.mass = mass
	body.rest_radius = radius
	var schwarz_radius = body.get_schwarz_radius()
	body.is_black_hole = radius <= schwarz_radius
	if body.is_black_hole:
		radius = schwarz_radius
		body.rest_radius = radius
	body.mesh = SphereMesh.new()
	body.set_display_radius(radius)
	body.position = position
	body.coord_velocity = coord_velocity
	if coord_velocity.length() > Global.max_speed:
		body.coord_velocity = coord_velocity.normalized() * Global.max_speed
	body.should_be_deleted = false
	body.reset()
	return body

## Returns the Schwarzschild radius of this body; the radius of a Schwarzschild
## black hole of this mass
func get_schwarz_radius() -> float:
	return 2.0 * Global.grav_const * mass / (Global.light_speed ** 2.0)

## Returns the speed required for a circular orbit in the rest frame of this
## body
func get_rest_orbit_speed(distance: float) -> float:
	return sqrt(Global.grav_const * mass / \
			(distance - get_schwarz_radius()))

## Sets the radius and height of the mesh to reflect the size of the radius. If
## is below a minimum display size, then it is set to that minimum size. The
## hitbox is unaffected by this.
func set_display_radius(radius: float) -> void:
	mesh.set_radius(radius)
	mesh.set_height(2.0 * radius)
	if radius < Global.MIN_DISPLAY_RADIUS:
		mesh.set_radius(Global.MIN_DISPLAY_RADIUS)
		mesh.set_height(2.0 * Global.MIN_DISPLAY_RADIUS)

## Adds the contribution to the gravitational field and potential by the other 
## body
func add_grav_field_and_potential(other) -> void:
	var field_and_potential = other.grav_field_and_potential_at(position)
	var field = field_and_potential[0]
	var potential = field_and_potential[1]
	_grav_field += field
	_grav_potential += potential

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
	if !coord_velocity.is_zero_approx():
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
	_calc_esc_velocity()
	_calc_infalling_vel()

## Resets the fields and potentials calculated for this body. This should be
## called when the body needs to recalibrate
func reset_fields_and_potentials() -> void:
	_grav_field = Vector3(0.0, 0.0, 0.0)
	_grav_potential = 0.0
	_escape_velocity = Vector3(0.0, 0.0, 0.0)

## Calculates a timestep for this and another body. In the simulation, this is
## done with pairs of bodies, and the pair with the lowest timestep sets the
## next timestep. This is done based on the speeds of the bodies in the
## simulation frame. If the sum is zero, then a default value is returned
## instead
func calc_timestep(other) -> float:
	var naive_speed_sum = coord_velocity.length() + other.coord_velocity.length()
	if is_zero_approx(naive_speed_sum):
		return 1e-9
	var distance = (other.position - position).length() * Global.MAX_SPACE_ERROR
	return distance / naive_speed_sum

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

## Adds the volume, mass, and momentum of another body, moves it to their center
## of mass, and marks the other body for deletion. Also turns the body into a
## black hole if the conditions are met. To be used during collisions
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
	var new_rest_radius: float
	var schwarz_radius := get_schwarz_radius()
	var other_schwarz_radius = other.get_schwarz_radius()
	var sum_schwarz_radius = schwarz_radius + other_schwarz_radius
	if is_black_hole || other.is_black_hole:
		new_rest_radius = sum_schwarz_radius
		is_black_hole = true
	else:
		new_rest_radius = (rest_radius**3.0 + other.rest_radius**3.0) ** \
				(1.0 / 3.0)
	mass = new_mass
	position = new_position
	coord_velocity = new_coord_velocity
	rest_radius = new_rest_radius
	if rest_radius < sum_schwarz_radius:
		rest_radius = sum_schwarz_radius
		is_black_hole = true
	set_display_radius(rest_radius)
	other.should_be_deleted = true

## Returns the relativistic mass of the body based on the infalling frame
func get_relativistic_mass() -> float:
	return mass / _infall_lorentz_recip

## Calculates the center of mass between this body and another one, based on
## their relativistic masses
func get_center_of_mass_with(other) -> Vector3:
	var self_rel_mass := get_relativistic_mass()
	var other_rel_mass = other.get_relativistic_mass()
	var total_rel_mass = self_rel_mass + other_rel_mass
	return (self_rel_mass * position + other_rel_mass * other.position) / \
			total_rel_mass

## Calculates the relativistic momentum in the coordinate frame
func get_coord_momentum() -> Vector3:
	return mass * coord_velocity / _coord_lorentz_recip

## Recalculates length contraction for the new velocity, and resets fields,
## potentials, related values, and flags
func reset() -> void:
	_calc_length_contraction()
	_grav_field = Vector3(0.0, 0.0, 0.0)
	_grav_potential = 0.0
	_escape_velocity = Vector3(0.0, 0.0, 0.0)
	_esc_lorentz_recip = 1.0
	_infalling_vel = coord_velocity
	_infall_lorentz_recip = _coord_lorentz_recip
	needs_recalibration = true

## Calculates the length contraction factors and saves the coordinate lorentz
## factor for gravitational field calculation
func _calc_length_contraction():
	_coord_lorentz_recip = Global.lorentz_fact_recip(coord_velocity)
	_length_scales = Vector3(1.0, 1.0, 1.0)
	var length_scales_par := _length_scales.project(coord_velocity)
	var length_scales_orth := _length_scales - length_scales_par
	_length_scales = length_scales_par * _coord_lorentz_recip + \
			length_scales_orth
	_length_scales.x = abs(_length_scales.x)
	_length_scales.y = abs(_length_scales.y)
	_length_scales.z = abs(_length_scales.z)

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
	if _infalling_vel.length() > Global.max_speed:
		_infalling_vel = _infalling_vel.normalized() * Global.max_speed
	var new_infall_lorentz_recip = Global.lorentz_fact_recip(_infalling_vel)
	needs_recalibration = \
			abs(1.0 - new_infall_lorentz_recip / _infall_lorentz_recip) >= 1e-9
	_infall_lorentz_recip = new_infall_lorentz_recip

## Returns information of the body in the form of a string
func _to_string() -> String:
	return ("Mass = %f\n" % mass) + \
			("Radius = %f\n" % rest_radius) + \
			("Position = <%f, %f, %f> (%f)\n" % [position.x, \
					position.y, position.z, position.length()]) + \
			("Coordinate Velocity = <%f, %f, %f> (%f)\n" % [coord_velocity.x, \
					coord_velocity.y, coord_velocity.z, coord_velocity.length()]) + \
			("Coordinate Lorentz Reciprocal = %f\n" % _coord_lorentz_recip) + \
			("Gravitational Field = <%f, %f, %f> (%f)\n" % [_grav_field.x, \
					_grav_field.y, _grav_field.z, _grav_field.length()]) + \
			("Gravitational Potential = %f\n" % _grav_potential) + \
			("Escape Velocity = <%f, %f, %f> (%f)\n" % [_escape_velocity.x, \
					_escape_velocity.y, _escape_velocity.z, _escape_velocity.length()]) + \
			("Escape Lorentz Reciprocal = %f\n" % _esc_lorentz_recip) + \
			("Infalling Velocity = <%f, %f, %f> (%f)\n" % [_infalling_vel.x, \
					_infalling_vel.y, _infalling_vel.z, _infalling_vel.length()]) + \
			("Infalling Lorentz Reciprocal = %f\n" % _infall_lorentz_recip)
