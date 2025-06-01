class_name Body
extends MeshInstance3D

static var body_scene := preload("res://body.tscn")
static var body_shader := preload("res://body.gdshader")

@export var mass: float
@export var charge: float
@export var rest_radius: float
@export var coord_velocity: Vector3
var em_field_mass: float
var coord_net_force: Vector3
var coord_acceleration: Vector3
var proper_time: float
var _coord_lorentz_recip: float
var _length_contract_matrix: Basis
var _newton_grav_field: Vector3
var _newton_grav_potential: float
var _escape_velocity: Vector3
var _esc_lorentz_recip: float
var _infalling_vel: Vector3
var _infall_lorentz_recip: float
var is_black_hole: bool
var should_be_deleted: bool
var is_collidable: bool

## Creates a new body with a given mass, radius, position, and velocity based on
## the scaled units. Initial values assume no gravitational influences
static func new_body(name_text: String, mass: float, charge: float, \
		radius: float, position: Vector3, coord_velocity: Vector3, \
				color: Vector3=Vector3(255.0, 255.0, 255.0), \
				is_collidable: bool = true) -> Body:
	var body := body_scene.instantiate()
	var label_node := body.get_node("Label")
	label_node.set_text(name_text)
	label_node.set_billboard_mode(BaseMaterial3D.BILLBOARD_ENABLED)
	label_node.set_draw_flag(Label3D.FLAG_FIXED_SIZE, true)
	label_node.set_pixel_size(0.001)
	body.mass = mass
	body.charge = charge
	body.rest_radius = radius
	body.mesh = SphereMesh.new()
	body.mesh.radial_segments = 8
	body.mesh.rings = 4
	body.set_display_radius(radius)
	body.mesh.material = ShaderMaterial.new()
	body.mesh.material.shader = body_shader.duplicate()
	body._set_color(color)
	body.em_field_mass = 0.0
	body._try_to_turn_into_black_hole()
	if !body.is_black_hole:
		body._calc_em_field_mass()
		body._try_to_turn_into_black_hole()
	body.position = position
	body.coord_velocity = coord_velocity
	if coord_velocity.length() > Global.max_speed:
		body.coord_velocity = coord_velocity.normalized() * Global.max_speed
	body.proper_time = 0.0
	body.should_be_deleted = false
	body.reset()
	return body

## Returns the total mass of the body, including the mass of its field energy.
func get_total_mass() -> float:
	return mass + em_field_mass

## Returns the radius of a black hole that has the same mass and electric charge
## as this body.
func get_black_hole_radius() -> float:
	return (2.0 * Global.grav_const * get_total_mass()) / \
			(Global.light_speed ** 2.0)

## Returns the Schwarzschild radius of this body; the radius of a Schwarzschild
## black hole of this mass
func get_schwarz_radius() -> float:
	return (2.0 * Global.grav_const * mass) / (Global.light_speed ** 2.0)

## Returns the speed required for a circular orbit in the rest frame of this
## body (gravity only)
func get_grav_rest_orbit_speed(distance: float) -> float:
	var total_mass := get_total_mass()
	if total_mass <= 0.0:
		return 0.0
	return sqrt(Global.grav_const * total_mass / \
			(distance - get_black_hole_radius()))

## Sets the radius and height of the mesh to reflect the size of the radius. If
## is below a minimum display size, then it is set to that minimum size. The
## hitbox is unaffected by this.
func set_display_radius(radius: float) -> void:
	if radius < Global.MIN_DISPLAY_RADIUS:
		mesh.set_radius(Global.MIN_DISPLAY_RADIUS)
		mesh.set_height(2.0 * Global.MIN_DISPLAY_RADIUS)
		get_node("Label").position = Vector3(0.0, Global.MIN_DISPLAY_RADIUS, \
				0.0) * 1.1
		return
	mesh.set_radius(radius)
	mesh.set_height(2.0 * radius)
	get_node("Label").position = Vector3(0.0, radius, 0.0) * 1.1

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
	var total_mass := get_total_mass()
	if is_zero_approx(total_mass):
		return [Vector3(), 0.0]
	var vector_to_other := other_position - position
	var distance := vector_to_other.length()
	var radius_towards := get_radius_towards(other_position)
	var rad_ratio := distance / radius_towards
	var is_inside := distance < radius_towards
	var field: Vector3
	if is_inside:
		field = (-Global.grav_const * total_mass * rad_ratio / \
				(rest_radius**2.0)) * vector_to_other.normalized()
	else:
		field = (-Global.grav_const * total_mass / \
				(distance**3.0)) * vector_to_other
	if !coord_velocity.is_zero_approx():
		var field_parallel = field.project(coord_velocity)
		var field_orthogonal = field - field_parallel
		field = field_parallel * _coord_lorentz_recip + field_orthogonal
	var potential: float
	var potential_sign = -sign(total_mass)
	if is_inside:
		var surface_field = (-Global.grav_const * total_mass / \
				(rest_radius ** 2.0)) * vector_to_other.normalized()
		if !coord_velocity.is_zero_approx():
			var surface_field_par = surface_field.project(coord_velocity)
			var surface_field_orth = surface_field - surface_field_par
			surface_field = surface_field_par * _coord_lorentz_recip + \
					surface_field_orth
		potential = potential_sign * (surface_field.length() * radius_towards \
				+ (field.length() * (radius_towards**2.0 - distance**2.0) / \
				(2.0 * distance)))
	else:
		potential = potential_sign * field.length() * distance
	return [field, potential]

## Adds the effect of the other body's electromagnetic field to this body.
func add_electromagnetic_force(other) -> void:
	var field = other.electromagnetic_field_at(position)
	var force = field * charge
	coord_net_force += force

## Calculates the electromagnetic field by this body at the given position.
func electromagnetic_field_at(other_position: Vector3) -> Vector3:
	if is_zero_approx(charge):
		return Vector3()
	var vector_to_other := other_position - position
	var distance := vector_to_other.length()
	var radius_towards := get_radius_towards(other_position)
	var rad_ratio := distance / radius_towards
	var is_inside := distance < radius_towards
	var field: Vector3
	if is_inside:
		field = (Global.coulomb_const * charge * rad_ratio / \
				(rest_radius ** 2)) * vector_to_other.normalized()
	else:
		field = (Global.coulomb_const * charge / \
				(distance**3.0)) * vector_to_other
	if !coord_velocity.is_zero_approx():
		var field_parallel = field.project(coord_velocity)
		var field_orthogonal = field - field_parallel
		field = field_parallel * _coord_lorentz_recip + field_orthogonal
	return field

## Calibrates the body based on length contraction, escape velocity, and
## infalling velocity. To be called after all gravitational fields and potentials
## are added.
func calibrate() -> void:
	_calc_esc_velocity()
	_calc_infalling_vel()

## Resets the fields and potentials calculated for this body. This should be
## called when the body needs to recalibrate
func reset_fields_and_potentials() -> void:
	_newton_grav_field = Vector3()
	_newton_grav_potential = 0.0
	_escape_velocity = Vector3()
	coord_net_force = Vector3()
	coord_acceleration = Vector3()

## Calculates the coordinate acceleration. To be called after all forces are
## calculated
func calc_coord_acceleration():
	coord_acceleration = coord_net_force / get_total_mass()

## Calculates a timestep for this and another body. A max timestep 
func calc_timestep(other) -> Array:
	var distance = (other.position - position).length()
	var min_dist = Global.max_space_error * distance
	var max_dist = min_dist * 10.0
	if min_dist < Global.max_space_error:
		min_dist = Global.max_space_error
		if min_dist > max_dist:
			max_dist = Global.max_space_error
	var speed = coord_velocity.length()
	if !coord_acceleration.is_finite():
		speed = Global.max_speed
	var other_speed = other.coord_velocity.length()
	if !other.coord_acceleration.is_finite():
		other_speed = Global.max_speed
	var slow_speed: float
	var fast_speed: float
	if speed <= other_speed:
		slow_speed = speed
		fast_speed = other_speed
	else:
		slow_speed = other_speed
		fast_speed = speed
	var accel_mag := _newton_grav_field.length()
	if coord_acceleration.is_finite():
		accel_mag += coord_acceleration.length()
	var other_accel_mag = other._newton_grav_field.length()
	if other.coord_acceleration.is_finite():
		other_accel_mag += other.coord_acceleration.length()
	var low_accel_mag: float
	var high_accel_mag: float
	if accel_mag <= other_accel_mag:
		low_accel_mag = accel_mag
		high_accel_mag = other_accel_mag
	else:
		low_accel_mag = other_accel_mag
		high_accel_mag = accel_mag
	var max_timestep: float
	var min_timestep: float
	if is_zero_approx(low_accel_mag):
		if is_zero_approx(slow_speed):
			max_timestep = Global.DEFAULT_TIMESTEP
			min_timestep = Global.DEFAULT_TIMESTEP
		else:
			max_timestep = max_dist / slow_speed
	else:
		max_timestep = (-slow_speed + \
				sqrt(slow_speed**2.0 + 2.0*low_accel_mag*max_dist)) / \
				low_accel_mag
	if is_zero_approx(high_accel_mag):
		if is_zero_approx(fast_speed):
			min_timestep = Global.DEFAULT_TIMESTEP
		else:
			min_timestep = min_dist / fast_speed
	else:
		min_timestep = (-fast_speed + \
				sqrt(fast_speed**2.0 + 2.0*high_accel_mag*min_dist)) / \
				high_accel_mag
	if is_zero_approx(max_timestep):
		max_timestep = Global.DEFAULT_TIMESTEP
		min_timestep = Global.DEFAULT_TIMESTEP
	elif is_zero_approx(min_timestep):
		min_timestep = Global.DEFAULT_TIMESTEP
	return [min_timestep, max_timestep]

## Move the body to its new position, and calculate its new velocity
func move(coord_timestep: float) -> void:
	var grav_timestep := coord_timestep * _esc_lorentz_recip
	position += coord_velocity * grav_timestep
	if coord_acceleration.is_finite():
		coord_velocity = Global.relativistic_vel_add(coord_velocity, \
				coord_acceleration * grav_timestep)
	else:
		coord_velocity = Global.max_speed * coord_net_force.normalized()
	coord_velocity = Global.relativistic_vel_add( \
			_newton_grav_field / (_esc_lorentz_recip**2.0) * coord_timestep, \
			coord_velocity)
	proper_time += coord_timestep * _infall_lorentz_recip

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
	if (!is_collidable and !other.is_black_hole) or \
			(!is_black_hole and !other.is_collidable):
		return false
	var vector_to_other = other.position - position
	var distance = vector_to_other.length()
	return distance <= get_radius_towards(other.position) + \
			other.get_radius_towards(position)

## Adds the volume, mass, and momentum of another body, moves it to their center
## of mass, and marks the other body for deletion. Also turns the body into a
## black hole if the conditions are met. To be used during collisions
func absorb(other) -> void:
	var new_name_text = get_node("Label").text
	if mass < other.mass:
		new_name_text = other.name_text
	var new_mass = mass + other.mass
	var new_charge = charge + other.charge
	var new_position := get_center_of_mass_with(other)
	var new_coord_velocity := get_center_of_momentum_velocity(other)
	var new_color_and_radius = _combine_colors_and_volume(other)
	var new_color = new_color_and_radius[0]
	var new_rest_radius = new_color_and_radius[1]
	_set_name_text(new_name_text)
	mass = new_mass
	charge = new_charge
	position = new_position
	coord_velocity = new_coord_velocity
	rest_radius = new_rest_radius
	if is_black_hole:
		rest_radius = 0.0
	_calc_em_field_mass()
	_set_color(new_color)
	set_display_radius(rest_radius)
	_try_to_turn_into_black_hole()
	other.should_be_deleted = true

## Returns the relativistic mass of the body based on the coordinate frame
func get_relativistic_mass() -> float:
	return get_total_mass() / _coord_lorentz_recip

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
	return get_total_mass() * coord_velocity / _coord_lorentz_recip

## Caclulates the velocity of the center of momentum frame between this and
## another body
func get_center_of_momentum_velocity(other) -> Vector3:
	var total_momentum = get_coord_momentum() + other.get_coord_momentum()
	var total_momentum_mag = total_momentum.length()
	var total_mass = get_total_mass() + other.get_total_mass()
	var speed = total_momentum_mag / \
			sqrt(total_mass**2.0 + (total_momentum_mag / Global.light_speed)** \
			2.0)
	if speed > Global.max_speed:
		speed = Global.max_speed
	return speed * total_momentum.normalized()

## Recalculates length contraction for the new velocity, and resets fields,
## potentials, related values, and flags
func reset() -> void:
	_calc_length_contraction()
	reset_fields_and_potentials()
	_esc_lorentz_recip = 1.0
	_infalling_vel = coord_velocity
	_infall_lorentz_recip = _coord_lorentz_recip

## Caclulates the effective mass of the electromagnetic field.
func _calc_em_field_mass() -> void:
	em_field_mass = 0.0
	if is_zero_approx(charge):
		return
	if is_black_hole:
		em_field_mass = (Global.coulomb_const * charge**2.0) / \
				(4.0 * Global.grav_const * mass)
		return
	em_field_mass = (3.0 * Global.coulomb_const * charge**2.0) / \
			(5.0 * rest_radius * Global.light_speed**2.0)

## Gets the color of the body
func _get_color() -> Vector3:
	return mesh.material.get_shader_parameter("color")

## Sets the color of the body.
func _set_color(color : Vector3) -> void:
	mesh.material.set_shader_parameter("color", color)

## Calculates the new color and radius if this body were to merge with other.
func _combine_colors_and_volume(other) -> Array:
	var color = _get_color()
	var other_color = other._get_color()
	var radius_cubed := rest_radius ** 3.0
	var other_radius_cubed = other.rest_radius ** 3.0
	var radii_cubed_sum = radius_cubed + other_radius_cubed
	var new_rest_radius = radii_cubed_sum ** (1.0 / 3.0)
	var new_color = (radius_cubed * color + other_radius_cubed * other_color) \
			/ radii_cubed_sum
	return [new_color, new_rest_radius]

## Sets the label text
func _set_name_text(name_text: String) -> void:
	get_node("Label").set_text(name_text)

## Collpses the body into a black hole if its current radius is less than or
## equal to the black hole radius.
func _try_to_turn_into_black_hole() -> void:
	var black_hole_radius = get_black_hole_radius()
	is_black_hole = (rest_radius <= 1.5 * black_hole_radius)
	if is_black_hole:
		_calc_em_field_mass()
		black_hole_radius = get_black_hole_radius()
		rest_radius = black_hole_radius
		set_display_radius(rest_radius)
		_set_color(Vector3())
		is_collidable = true

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
			_length_contract_matrix[i] = \
					basis_vector_par * _coord_lorentz_recip + basis_vector_orth
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
	var escape_speed := sqrt(2.0 * abs(_newton_grav_potential))
	if _newton_grav_field.is_zero_approx():
		if coord_velocity.is_zero_approx():
			_escape_velocity = escape_speed * Vector3(-1.0, 0.0, 0.0)
		else:
			_escape_velocity = escape_speed * coord_velocity.normalized()
	else:
		_escape_velocity = escape_speed * -_newton_grav_field.normalized()
	if escape_speed >= Global.max_speed:
		_escape_velocity = Global.max_speed * _escape_velocity.normalized()
		_newton_grav_field = Vector3()
	_esc_lorentz_recip = Global.lorentz_fact_recip(_escape_velocity)

## Calculates the velocity of the body in the frame of reference of an observer
## falling at the escape speed towards the body at the location. Saves this 
func _calc_infalling_vel() -> void:
	_infalling_vel = Global.relativistic_vel_add(-_escape_velocity, \
			coord_velocity)
	_infall_lorentz_recip = Global.lorentz_fact_recip(_infalling_vel)

## Returns information of the body in the form of a string
func _to_string() -> String:
	return ("Name = %s\n" % get_node("Label").text) + \
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
