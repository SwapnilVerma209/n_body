class_name Body
extends MeshInstance3D

static var body_scene := preload("res://body.tscn")
static var body_shader := preload("res://body.gdshader")

@export var label: String
@export var color: Vector3
@export var mass: float
@export var rest_radius: float
@export var coord_velocity: Vector3
var proper_time: float
var _coord_lorentz_recip: float
var _length_contract_matrix: Basis
var _newton_grav_field: Vector3
var _newton_grav_potential: float
var _escape_velocity: Vector3
var _esc_lorentz_recip: float
var _infalling_vel: Vector3
var _infall_lorentz_recip: float
var needs_recalibration: bool
var is_black_hole: bool
var should_be_deleted: bool

## Creates a new body with a given mass, radius, position, and velocity based on
## the scaled units. Initial values assume no gravitational influences
static func new_body(label: String, color: Vector3, mass: float, \
		radius: float, position: Vector3, coord_velocity: Vector3) -> Body:
	var body := body_scene.instantiate()
	body.label = label
	body.color = color
	body.mass = mass
	body.rest_radius = radius
	var schwarz_radius = body.get_schwarz_radius()
	body.is_black_hole = radius <= schwarz_radius
	if body.is_black_hole:
		radius = schwarz_radius
		body.rest_radius = radius
		body.color = Vector3(0.0, 0.0, 0.0)
	body.mesh = SphereMesh.new()
	body.mesh.radial_segments = 8
	body.mesh.rings = 4
	body.set_display_radius(radius)
	body.mesh.material = ShaderMaterial.new()
	body.mesh.material.shader = body_shader.duplicate()
	body.mesh.material.set_shader_parameter("color", color)
	body.position = position
	body.coord_velocity = coord_velocity
	if coord_velocity.length() > Global.max_speed:
		body.coord_velocity = coord_velocity.normalized() * Global.max_speed
	body.proper_time = 0.0
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
	if radius < Global.MIN_DISPLAY_RADIUS:
		mesh.set_radius(Global.MIN_DISPLAY_RADIUS)
		mesh.set_height(2.0 * Global.MIN_DISPLAY_RADIUS)
		return
	mesh.set_radius(radius)
	mesh.set_height(2.0 * radius)

## Adds the contribution to the gravitational field and potential by the other 
## body
func add_newton_grav_field_and_potential(other) -> void:
	var field_and_potential = other.newton_grav_field_and_potential_at(position)
	var field = field_and_potential[0]
	var potential = field_and_potential[1]
	_newton_grav_field += field
	_newton_grav_potential += potential

## Calculates and returns the gravitational field and potential caused by this
## body at other_postion. The values are expressed as those in the rest frame of
## an observer at other_position and at rest relative to the coordinate origin,
## based on the scaled units
func newton_grav_field_and_potential_at(other_position: Vector3) -> Array:
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
	_newton_grav_field = Vector3(0.0, 0.0, 0.0)
	_newton_grav_potential = 0.0
	_escape_velocity = Vector3(0.0, 0.0, 0.0)

## Calculates a timestep for this and another body. In the simulation, this is
## done with pairs of bodies, and the pair with the lowest timestep sets the
## next timestep. This is done based on the speeds of the bodies in the
## simulation frame. If the sum is zero, then a default value is returned
## instead
func calc_timestep(other) -> float:
	var distance = Global.max_space_error * (other.position - position).length()
	if distance < Global.max_space_error:
		distance = Global.max_space_error
	var speed = coord_velocity.length()
	var other_speed = other.coord_velocity.length()
	if other_speed > speed:
		speed = other_speed
	var accel_mag = _newton_grav_field.length()
	var other_accel_mag = other._newton_grav_field.length()
	if other_accel_mag > accel_mag:
		accel_mag = other_accel_mag
	var timestep: float
	if is_zero_approx(accel_mag):
		if is_zero_approx(speed):
			return Global.DEFAULT_TIMESTEP
		else:
			timestep = distance / speed
	else:
		timestep = (-speed + sqrt(speed**2.0 + 2.0*accel_mag*distance)) / \
				accel_mag
	if is_zero_approx(timestep):
		return Global.DEFAULT_TIMESTEP
	return timestep

## Move the body to its new position, and calculate its new velocity
func move(coord_timestep: float) -> void:
	var local_timestep := coord_timestep * _esc_lorentz_recip
	#print("Local timestep = %f" % local_timestep)
	#print("Old velocity:")
	#print(coord_velocity)
	position += coord_velocity * local_timestep
	coord_velocity = Global.relativistic_vel_add( \
			_newton_grav_field / (_esc_lorentz_recip**2.0) * coord_timestep, \
			coord_velocity)
	#print("Gravitational field:")
	#print(_newton_grav_field / (_esc_lorentz_recip**2.0))
	#print("New velocity:")
	#print(coord_velocity)
	#print()
	proper_time += local_timestep

## Calculates the radius in the direction of the given position
func get_radius_towards(other_position: Vector3) -> float:
	if coord_velocity.is_zero_approx():
		return rest_radius
	var direction := (other_position - position).normalized()
	var direction_par := direction.project(coord_velocity)
	if direction_par.is_zero_approx():
		return rest_radius
	var direction_orth := direction - direction_par
	if direction_orth.is_zero_approx():
		return rest_radius * _coord_lorentz_recip
	var rest_rad_vector := direction_par / _coord_lorentz_recip + direction_orth
	rest_rad_vector = rest_rad_vector.normalized()
	rest_rad_vector *= rest_radius
	var rest_rad_par := rest_rad_vector.project(coord_velocity)
	var radius_vector := rest_rad_vector - rest_rad_par + rest_rad_par * \
			_coord_lorentz_recip
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
	var new_label := label
	if mass < other.mass:
		new_label = other.label
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
		color = Vector3(0.0, 0.0, 0.0)
		mesh.material.set_shader_parameter("color", color)
	else:
		new_rest_radius = (rest_radius**3.0 + other.rest_radius**3.0) ** \
				(1.0 / 3.0)
	var new_color = (color + other.color) * 0.5
	label = new_label
	mass = new_mass
	position = new_position
	coord_velocity = new_coord_velocity
	rest_radius = new_rest_radius
	color = new_color
	if rest_radius < sum_schwarz_radius:
		rest_radius = sum_schwarz_radius
		is_black_hole = true
		color = Vector3(0.0, 0.0, 0.0)
		mesh.material.set_shader_parameter("color", color)
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
	_newton_grav_field = Vector3(0.0, 0.0, 0.0)
	_newton_grav_potential = 0.0
	_escape_velocity = Vector3(0.0, 0.0, 0.0)
	_esc_lorentz_recip = 1.0
	_infalling_vel = coord_velocity
	_infall_lorentz_recip = _coord_lorentz_recip
	needs_recalibration = true

## Calculates the length contraction factors and saves the coordinate lorentz
## factor for gravitational field calculation
func _calc_length_contraction() -> void:
	_coord_lorentz_recip = Global.lorentz_fact_recip(coord_velocity)
	_length_contract_matrix = Basis.IDENTITY
	if !coord_velocity.is_zero_approx():
		for i in 3:
			var basis_vector := _length_contract_matrix[i]
			var basis_vector_par := basis_vector.project(coord_velocity)
			var basis_vector_orth := basis_vector - basis_vector_par
			_length_contract_matrix[i] = basis_vector_par * _coord_lorentz_recip + \
					basis_vector_orth
	mesh.material.set_shader_parameter("length_contract_mat", \
			_length_contract_matrix)

## Calculates the escape velocity. Set in opposite direction of net gravitational
## field by default. If there is no net gravitational field, it is set in either
## the direction of the body's instantaneous velocity or towards negative x if
## that is also zero. If the speed reaches or exceeds a max speed defined in the
## global file, then it is set to that speed, and the net gravitational field is
## set to zero. This is to prevent infinities at the event horizons of black
## holes.
func _calc_esc_velocity() -> void:
	var escape_speed := sqrt(-2.0 * _newton_grav_potential)
	if _newton_grav_field.is_zero_approx():
		if coord_velocity.is_zero_approx():
			_escape_velocity = escape_speed * Vector3(-1.0, 0.0, 0.0)
		else:
			_escape_velocity = escape_speed * coord_velocity.normalized()
	else:
		_escape_velocity = escape_speed * -_newton_grav_field.normalized()
	if escape_speed >= Global.max_speed:
		_escape_velocity = Global.max_speed * _escape_velocity.normalized()
		_newton_grav_field = Vector3(0.0, 0.0, 0.0)
	_esc_lorentz_recip = Global.lorentz_fact_recip(_escape_velocity)

## Calculates the velocity of the body in the frame of reference of an observer
## falling at the escape speed towards the body at the location. Saves this 
func _calc_infalling_vel() -> void:
	_infalling_vel = Global.relativistic_vel_add(_escape_velocity, \
			coord_velocity)
	var new_infall_lorentz_recip = Global.lorentz_fact_recip(_infalling_vel)
	needs_recalibration = \
			abs(1.0 - new_infall_lorentz_recip / _infall_lorentz_recip) >= 1e-9
	_infall_lorentz_recip = new_infall_lorentz_recip

## Returns information of the body in the form of a string
func _to_string() -> String:
	return ("Label = %s\n" % label) + \
			("Mass = %f\n" % mass) + \
			("Radius = %f\n" % rest_radius) + \
			("Position = <%f, %f, %f> (%f)\n" % [position.x, \
					position.y, position.z, position.length()]) + \
			("Coordinate Velocity = <%f, %f, %f> (%f)\n" % [coord_velocity.x, \
					coord_velocity.y, coord_velocity.z, coord_velocity.length()]) + \
			("Coordinate Lorentz Reciprocal = %f\n" % _coord_lorentz_recip) + \
			("Newtonian Gravitational Field = <%f, %f, %f> (%f)\n" % \
					[_newton_grav_field.x, _newton_grav_field.y, \
					_newton_grav_field.z, _newton_grav_field.length()]) + \
			("Newtonian Gravitational Potential = %f\n" % _newton_grav_potential) + \
			("Escape Velocity = <%f, %f, %f> (%f)\n" % [_escape_velocity.x, \
					_escape_velocity.y, _escape_velocity.z, _escape_velocity.length()]) + \
			("Escape Lorentz Reciprocal = %f\n" % _esc_lorentz_recip) + \
			("Infalling Velocity = <%f, %f, %f> (%f)\n" % [_infalling_vel.x, \
					_infalling_vel.y, _infalling_vel.z, _infalling_vel.length()]) + \
			("Infalling Lorentz Reciprocal = %f\n" % _infall_lorentz_recip)
