extends Node3D

var bodies := []
var all_calibrated := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_
	var max_dist := _calc_max_dist()
	$Player.position = 1.1 * max_dist * Vector3(0.0, 0.0, -1.0)
	if $Player.position.length() > 1e11:
		$Player.position = 1e11 * Vector3(1.0, 0.0, 0.0).normalized()
	#print("Beginning")
	#_print_bodies()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if !all_calibrated:
		#print("Calibrating")
		all_calibrated = true
		_calc_fields_and_potentials()
		_calibrate_bodies()
		#_print_bodies()
	else:
		#print("Moving")
		var timestep := _calc_timestep()
		_move_bodies(timestep)
		_collide_bodies()
		_reset_bodies()
		all_calibrated = false
		#_print_bodies()

func _add_body(mass_amount: float, mass_unit: String, radius_amount: float, \
		rad_space_unit: String, pos_amount: Vector3, pos_space_unit: String, \
		vel_amount: Vector3, vel_space_unit: String, vel_time_unit: String) -> \
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
	var body := Body.new_body(mass, radius, position, velocity)
	bodies.append(body)
	$Bodies.add_child(body)
	return body

func _calc_max_dist() -> float:
	var max_dist := 0.0
	for body in bodies:
		var dist = body.position.length()
		if dist > max_dist:
			max_dist = dist
	return max_dist

func _calc_fields_and_potentials() -> void:
	for i in range(bodies.size()):
		if bodies[i] == null:
			continue
		for j in range(i+1, bodies.size()):
			if bodies[j] == null:
				continue
			bodies[i].add_grav_field_and_potential(bodies[j])
			bodies[j].add_grav_field_and_potential(bodies[i])

func _calibrate_bodies() -> void:
	for body in bodies:
		if body == null:
			continue
		body.calibrate()
		if body.needs_recalibration:
			all_calibrated = false
	if !all_calibrated:
		for body in bodies:
			if body == null:
				continue
			body.reset_fields_and_potentials()

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
		return 1e-9
	return timestep
	
func _move_bodies(timestep: float) -> void:
	for body in bodies:
		if body == null:
			continue
		body.move(timestep)

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

func _reset_bodies() -> void:
	for body in bodies:
		if body == null:
			continue
		body.reset()

func _print_bodies() -> void:
	for body in bodies:
		if body == null:
			continue
		print(body)
