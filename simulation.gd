extends Node3D

const _MAX_CALIBRATION_ROUNDS := 10

var max_frame_time_us: float
var bodies := []
var all_calibrated := false
var calibration_count := 0
var timestep: float
var coord_time := 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.set_precision(7, -4)
	Global.set_scales("kilometer", "millisecond", "kilogram")
	
	var black_hole := _add_body( \
		"Black hole", \
		Vector3(), \
		8.0, "solar_mass", \
		0.0, "kilometer", \
		Vector3(0.0, 0.0, 0.0), "kilometer", \
		Vector3(0.0, 0.0, 0.0), "kilometer", "millisecond")
	var schwarz_radius := black_hole.get_schwarz_radius()
	var test_distance := randf_range(1.5, 10.0) * schwarz_radius
	print("Distance = %f Schwarzschild Radii" % \
			(test_distance / schwarz_radius))
	var test_position := Vector3(test_distance, 0.0, 0.0)
	var test_speed := black_hole.get_rest_orbit_speed(test_distance)
	var test_velocity := Vector3(0.0, test_speed, 0.0)
	_add_body( \
		"Test particle", \
		Vector3(255.0, 255.0, 255.0), \
		1.0, "kilogram", \
		5.0, "kilometer", \
		test_position, "kilometer", \
		test_velocity, "kilometer", "millisecond")
	
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
		if !all_calibrated:
			all_calibrated = true
			if calibration_count <= _MAX_CALIBRATION_ROUNDS:
				_reset_fields_and_potentials()
				_calc_fields_and_potentials()
				_calibrate_bodies()
				calibration_count += 1
		else:
			calibration_count = 0
			timestep = _calc_timestep()
			_move_bodies(timestep)
			_collide_bodies()
			_reset_bodies()
			all_calibrated = false
			coord_time += timestep
		elapsed_time = Time.get_ticks_usec() - start_time

## Creates a new body instance with the given parameters, scaled with the given 
## units. Adds the body into the simulation, and returns a reference to it
func _add_body(label: String, color: Vector3, mass_amount: float, \
		mass_unit: String, radius_amount: float, rad_space_unit: String, \
		pos_amount: Vector3, pos_space_unit: String, vel_amount: Vector3, \
		vel_space_unit: String, vel_time_unit: String) -> \
		Body:
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
	var body := Body.new_body(label, color, mass, radius, position, velocity)
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
		if body.needs_recalibration:
			all_calibrated = false

func _reset_fields_and_potentials() -> void:
	for body in bodies:
		if body == null:
			continue
		body.reset_fields_and_potentials()

## Calculates timesteps between each pair, and returns the smallest one. If
## there is only one body, a default value is used.
func _calc_timestep() -> float:
	var timestep := INF
	for i in range(bodies.size()):
		if bodies[i] == null:
			continue
		for j in range(i+1, bodies.size()):
			if bodies[j] == null:
				continue
			var new_timestep = bodies[i].calc_timestep(bodies[j])
			if new_timestep < timestep:
				timestep = new_timestep
	if timestep == INF:
		return Global.DEFAULT_TIMESTEP
	return timestep

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
				#print("Collision at %f %ss:\n" % [coord_time, Global.time_unit])
				#print(bodies[i])
				#print(bodies[j])
				bodies[i].absorb(bodies[j])
				bodies[j].queue_free()
				bodies[j] = null
				#print("New body:")
				#print(bodies[i])
				#print()

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
