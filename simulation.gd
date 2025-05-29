extends Node3D

const _MAX_CALIBRATION_ROUNDS := 10

var max_frame_time_us: float
var bodies := []
var timestep: float
var coord_time := 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Set precision and units here
	Global.set_precision(5, -5)
	Global.set_scales("kilometer", "second", "kilogram")
	
	# Add your bodies here
	var black_hole = _add_body("Black hole", \
			8.0, "solar_mass", \
			0.0, "kilometer", \
			Vector3(), "kilometer",
			Vector3(), "kilometer", "second", \
			Vector3(), \
			true)
	var schwarz_radius := black_hole.get_schwarz_radius()
	var rads := 1.5
	var distance := rads * schwarz_radius
	var position := distance * Vector3(1.0, 0.0, 0.0)
	var speed := 1.1 * black_hole.get_rest_orbit_speed(distance)
	var velocity := speed * Vector3(0.0, 1.0, 0.0)
	_add_body("1.5", \
			0.001, "kilogram", \
			5.0, "kilometer", \
			position, "kilometer",
			velocity, "kilometer", "second", \
			Vector3(255.0, 255.0, 255.0), \
			false)
	for i in range(9):
		rads = 2.0 + i * 1.0
		distance = rads * schwarz_radius
		position = distance * Vector3(1.0, 0.0, 0.0)
		speed = 1.1 * black_hole.get_rest_orbit_speed(distance)
		velocity = speed * Vector3(0.0, 1.0, 0.0)
		_add_body("%.1f" % rads, \
				0.001, "kilogram", \
				5.0, "kilometer", \
				position, "kilometer",
				velocity, "kilometer", "second", \
				Vector3(255.0, 255.0, 255.0), \
				false)
	
	# Do not modify
	var furthest_dist := _calc_furthest_dist()
	if is_zero_approx(furthest_dist):
		furthest_dist = bodies[0].rest_radius * 5.0
	$Player.set_initial_position(furthest_dist)
	if Engine.max_fps != 0:
		max_frame_time_us = 1e6 / Engine.max_fps
	else:
		max_frame_time_us = 1e6 / 120.0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	var start_time := Time.get_ticks_usec()
	var elapsed_time := 0
	while elapsed_time < 0.75 * max_frame_time_us:
		_reset_fields_and_potentials()
		_calc_fields_and_potentials()
		_calibrate_bodies()
		timestep = _calc_timestep()
		_move_bodies(timestep)
		_collide_bodies()
		_reset_bodies()
		coord_time += timestep
		elapsed_time = Time.get_ticks_usec() - start_time

## Creates a new body instance with the given parameters, scaled with the given 
## units. Adds the body into the simulation, and returns a reference to it
func _add_body(label: String, mass_amount: float, mass_unit: String, \
		radius_amount: float, rad_space_unit: String, pos_amount: Vector3, \
		pos_space_unit: String, vel_amount: Vector3, vel_space_unit: String, \
		vel_time_unit: String, color: Vector3=Vector3(255.0, 255.0, 255.0),
		is_collidable=true) \
		-> Body:
	var mass = mass_amount * Global.MASS_SCALES[mass_unit] / \
			Global.MASS_SCALES[Global.mass_unit]
	var radius = radius_amount * Global.SPACE_SCALES[rad_space_unit] / \
			Global.SPACE_SCALES[Global.space_unit]
	var position = pos_amount * Global.SPACE_SCALES[pos_space_unit] / \
			Global.SPACE_SCALES[Global.space_unit]
	var velocity = vel_amount * (Global.SPACE_SCALES[vel_space_unit] / \
			Global.SPACE_SCALES[Global.space_unit]) / \
			(Global.TIME_SCALES[vel_time_unit] / \
			Global.TIME_SCALES[Global.time_unit])
	var body := Body.new_body(label, mass, radius, position, velocity, color, \
			is_collidable)
	bodies.append(body)
	$Bodies.add_child(body)
	return body

## Calculates the furthest distance from the origin of any body
func _calc_furthest_dist() -> float:
	var furthest_dist := 0.0
	for body in bodies:
		var dist = body.position.length()
		if dist > furthest_dist:
			furthest_dist = dist
	return furthest_dist

## Calculates fields and potentials for every body in the simulation
func _calc_fields_and_potentials() -> void:
	for i in range(bodies.size()):
		if bodies[i] == null:
			continue
		for j in range(i+1, bodies.size()):
			if bodies[j] == null:
				continue
			bodies[i].add_newton_grav_field_and_potential(bodies[j])
			bodies[j].add_newton_grav_field_and_potential(bodies[i])

## Performs one round of calibration for every body in the simulation
func _calibrate_bodies() -> void:
	for body in bodies:
		if body == null:
			continue
		body.calibrate()

func _reset_fields_and_potentials() -> void:
	for body in bodies:
		if body == null:
			continue
		body.reset_fields_and_potentials()

## Calculates timesteps between each pair, and returns the smallest one. If
## there is only one body, a default value is used.
func _calc_timestep() -> float:
	var min_timestep := 0.0
	var max_timestep := INF
	for i in range(bodies.size()):
		if bodies[i] == null:
			continue
		for j in range(i+1, bodies.size()):
			if bodies[j] == null:
				continue
			var new_timesteps = bodies[i].calc_timestep(bodies[j])
			if new_timesteps[0] > min_timestep:
				min_timestep = new_timesteps[0]
			if new_timesteps[1] < max_timestep:
				max_timestep = new_timesteps[1]
			if max_timestep <= min_timestep:
				return max_timestep
	if min_timestep == 0:
		return Global.DEFAULT_TIMESTEP
	return min_timestep

## Moves each body according to the timestep
func _move_bodies(timestep: float) -> void:
	for body in bodies:
		if body == null:
			continue
		body.move(timestep)

## Detects collisions between the bodies, merging and deleting when necessary
func _collide_bodies() -> void:
	for i in range(bodies.size()):
		if bodies[i] == null:
			continue
		for j in range(i+1, bodies.size()):
			if bodies[j] == null:
				continue
			if bodies[i].is_colliding_with(bodies[j]):
				bodies[i].absorb(bodies[j])
				bodies[j].queue_free()
				bodies[j] = null

## Resets every body
func _reset_bodies() -> void:
	for body in bodies:
		if body == null:
			continue
		body.reset()

## Prints all the bodies' information
func _print_bodies() -> void:
	for body in bodies:
		if body == null:
			continue
		print(body)
