extends Node3D

var should_multithread: bool
var max_frame_time_us: float
var bodies := []
var init_num_bodies: int
var max_threads := OS.get_processor_count()
var threads := []
var num_threads: int
var num_bodies_per_thread: int
var timestep: float
var coord_time := 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Set precision and units here
	var precision := 3
	var space_unit := "proton_radius"
	var time_unit := "jiffy"
	var mass_unit := "proton_mass"
	var charge_unit := "elementary_charge"
	Global.set_precision(precision)
	Global.set_scales(space_unit, time_unit, mass_unit, charge_unit)
	
	# Add your bodies here
	_add_body(
		"Positron",
		1.0, "electron_mass",
		1.0, charge_unit,
		1.0, "electron_radius",
		Vector3(), space_unit,
		Vector3(), space_unit, time_unit,
		Vector3(255.0, 0.0, 0.0),
		true
	)
	_add_body(
		"???",
		-1.0, "electron_mass",
		-1.0, charge_unit,
		1.0, "electron_radius",
		Vector3(20.0, 0.0, 0.0), "proton_radius",
		Vector3(), space_unit, time_unit,
		Vector3(255.0, 255.0, 0.0),
		false
	)
	
	# Do not modify
	var furthest_dist := _calc_furthest_dist()
	if is_zero_approx(furthest_dist):
		furthest_dist = bodies[0].rest_radius * 5.0
	$Player.set_initial_position(furthest_dist)
	if Engine.max_fps != 0:
		max_frame_time_us = 1e6 / Engine.max_fps
	else:
		max_frame_time_us = 1e6 / 120.0
	init_num_bodies = len(bodies)
	should_multithread = (init_num_bodies >= max_threads * 2)
	if !should_multithread:
		return
	num_bodies_per_thread = init_num_bodies / max_threads
	for i in range(max_threads):
		threads.append(Thread.new())
	num_threads = len(threads)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	var start_time := Time.get_ticks_usec()
	var elapsed_time := 0
	while elapsed_time < 0.75 * max_frame_time_us:
		_calc_fields_and_potentials()
		_calibrate_bodies()
		_calculate_accelerations()
		timestep = _calc_timestep()
		_move_bodies(timestep)
		_collide_bodies()
		_reset_bodies()
		coord_time += timestep
		elapsed_time = Time.get_ticks_usec() - start_time

## Creates a new body instance with the given parameters, scaled with the given 
## units. Adds the body into the simulation, and returns a reference to it
func _add_body(label: String, mass_amount: float, mass_unit: String, \
		charge_amount: float, charge_unit: String,\
		radius_amount: float, rad_space_unit: String, pos_amount: Vector3, \
		pos_space_unit: String, vel_amount: Vector3, vel_space_unit: String, \
		vel_time_unit: String, color: Vector3=Vector3(255.0, 255.0, 255.0),
		is_collidable=true) \
		-> Body:
	var mass = mass_amount * Global.MASS_SCALES[mass_unit] / \
			Global.MASS_SCALES[Global.mass_unit]
	var charge = charge_amount * Global.CHARGE_SCALES[charge_unit] / \
			Global.CHARGE_SCALES[Global.charge_unit]
	var radius = radius_amount * Global.SPACE_SCALES[rad_space_unit] / \
			Global.SPACE_SCALES[Global.space_unit]
	var position = pos_amount * Global.SPACE_SCALES[pos_space_unit] / \
			Global.SPACE_SCALES[Global.space_unit]
	var velocity = vel_amount * (Global.SPACE_SCALES[vel_space_unit] / \
			Global.SPACE_SCALES[Global.space_unit]) / \
			(Global.TIME_SCALES[vel_time_unit] / \
			Global.TIME_SCALES[Global.time_unit])
	var body := Body.new_body(label, mass, charge, radius, position, velocity, \
			color, is_collidable)
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
	if !should_multithread:
		for i in range(bodies.size()):
			if bodies[i] == null:
				continue
			for j in range(i+1, bodies.size()):
				if bodies[j] == null:
					continue
				bodies[i].add_newton_grav_field_and_potential(bodies[j])
				bodies[i].add_electromagnetic_force(bodies[j])
				bodies[j].add_newton_grav_field_and_potential(bodies[i])
				bodies[j].add_electromagnetic_force(bodies[i])
		return
	var end: int
	for i in range(max_threads-1):
		var start := i * num_bodies_per_thread
		end = start + num_bodies_per_thread
		threads[i].start(_calc_field_and_pot_thread.bind(start, end))
	var start := end
	end = len(bodies)
	threads[num_threads-1].start(_calc_field_and_pot_thread.bind(start, end))
	for thread in threads:
		thread.wait_to_finish()

## Function for other threads to calculate fields and potentials.
func _calc_field_and_pot_thread(start: int, end: int) -> void:
	Thread.set_thread_safety_checks_enabled(false)
	for i in range(start, end):
		if bodies[i] == null:
			continue
		for j in range(len(bodies)):
			if j == i:
				continue
			if bodies[j] == null:
				continue
			bodies[i].add_newton_grav_field_and_potential(bodies[j])
			bodies[i].add_electromagnetic_force(bodies[j])

## Calibrates every body in the simulation
func _calibrate_bodies() -> void:
	if !should_multithread:
		for body in bodies:
			if body == null:
				continue
			body.calibrate()
		return
	var end: int
	for i in range(max_threads-1):
		var start := i * num_bodies_per_thread
		end = start + num_bodies_per_thread
		threads[i].start(_calibrate_bodies_thread.bind(start, end))
	var start := end
	end = len(bodies)
	threads[num_threads-1].start(_calibrate_bodies_thread.bind(start, end))
	for thread in threads:
		thread.wait_to_finish()

## Function for other threads to calibrate bodies
func _calibrate_bodies_thread(start: int, end: int) -> void:
	Thread.set_thread_safety_checks_enabled(false)
	for i in range(start, end):
		if bodies[i] == null:
			continue
		bodies[i].calibrate()

## Calculate the accelerations for all bodies
func _calculate_accelerations() -> void:
	if !should_multithread:
		for body in bodies:
			if body == null:
				continue
			body.calc_coord_acceleration()
		return
	var end: int
	for i in range(max_threads-1):
		var start := i * num_bodies_per_thread
		end = start + num_bodies_per_thread
		threads[i].start(_calc_accel_thread.bind(start, end))
	var start := end
	end = len(bodies)
	threads[num_threads-1].start(_calc_accel_thread.bind(start, end))
	for thread in threads:
		thread.wait_to_finish()

## Function for other threads to calculate accelerations
func _calc_accel_thread(start: int, end: int) -> void:
	Thread.set_thread_safety_checks_enabled(false)
	for i in range(start, end):
		if bodies[i] == null:
			continue
		bodies[i].calc_coord_acceleration()

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
			var timestep_bounds = bodies[i].calc_timestep_bounds(bodies[j])
			if timestep_bounds[0] > min_timestep:
				min_timestep = timestep_bounds[0]
			if timestep_bounds[1] < max_timestep:
				max_timestep = timestep_bounds[1]
			if max_timestep <= min_timestep:
				return max_timestep
	if min_timestep < Global.DEFAULT_TIMESTEP:
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
	if !should_multithread:
		for body in bodies:
			if body == null:
				continue
			body.reset()
		return
	var end: int
	for i in range(max_threads-1):
		var start := i * num_bodies_per_thread
		end = start + num_bodies_per_thread
		threads[i].start(_reset_bodies_thread.bind(start, end))
	var start := end
	end = len(bodies)
	threads[num_threads-1].start(_reset_bodies_thread.bind(start, end))
	for thread in threads:
		thread.wait_to_finish()

func _reset_bodies_thread(start: int, end: int) -> void:
	Thread.set_thread_safety_checks_enabled(false)
	for i in range(start, end):
		if bodies[i] == null:
			continue
		bodies[i].reset()

## Prints all the bodies' information
func _print_bodies() -> void:
	for body in bodies:
		if body == null:
			continue
		print(body)
