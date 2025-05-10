extends Camera3D
const _ANGULAR_ACCEL := PI / (1.0**2 / 2.0)
const _MAX_ANGULAR_SPEED := 2.0 * PI

var _max_speed := Global.max_axis_dist
var _acceleration := 2 * Global.max_axis_dist / 25.0
var _speed := 0.0
var _angular_speed := 0.0

# Called when the node enters the scene tree for the first time.
## Set player a quarter of the way towards the outer corner of the first octant,
## facing towards the origin
func _ready() -> void:
	set_initial_position(Global.max_sim_dist)

func set_initial_position(furthest_dist: float) -> void:
	far = 2.0 * Global.max_sim_dist
	position = Vector3(0.0, 0.0, furthest_dist)
	transform = transform.looking_at(Vector3(0.0, 0.0, 0.0))
	transform = transform.orthonormalized()
	_acceleration = 2 * furthest_dist / 25.0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_turn(delta)
	_move(delta)

## Turns the player given the input
func _turn(delta: float) -> void:
	var y_rotation := 0
	var x_rotation := 0
	if Input.is_action_pressed("look_left"):
		y_rotation += 1
	if Input.is_action_pressed("look_right"):
		y_rotation -= 1
	if Input.is_action_pressed("look_up"):
		x_rotation += 1
	if Input.is_action_pressed("look_down"):
		x_rotation -= 1
	rotate_y(y_rotation * _angular_speed * delta)
	transform = transform.orthonormalized()
	if x_rotation == 1:
		if (-transform.basis.z).dot(Vector3(0.0, 1.0, 0.0)) < 0.95:
			rotate_object_local(Vector3(1.0, 0.0, 0.0), _angular_speed * delta)
	elif x_rotation == -1:
		if (-transform.basis.z).dot(Vector3(0.0, 1.0, 0.0)) > -0.95:
			rotate_object_local(Vector3(1.0, 0.0, 0.0), -_angular_speed * delta)
	transform = transform.orthonormalized()
	if x_rotation != 0 || y_rotation != 0:
		_angular_speed += _ANGULAR_ACCEL * delta
		if _angular_speed > _MAX_ANGULAR_SPEED:
			_angular_speed = _MAX_ANGULAR_SPEED
	else:
		_angular_speed = 0.0

## Moves the player given the input
func _move(delta: float) -> void:
	var move_direction = Vector3(0.0, 0.0, 0.0)
	if Input.is_action_pressed("move_forward"):
		move_direction.z -= 1.0
	if Input.is_action_pressed("move_backward"):
		move_direction.z += 1.0
	if Input.is_action_pressed("move_left"):
		move_direction.x -= 1.0
	if Input.is_action_pressed("move_right"):
		move_direction.x += 1.0
	if Input.is_action_pressed("move_up"):
		move_direction.y += 1.0
	if Input.is_action_pressed("move_down"):
		move_direction.y -= 1.0
	if move_direction.is_zero_approx():
		_speed = 0.0
		return
	var curr_basis := transform.basis
	curr_basis.x.y = 0.0
	curr_basis.z.y = 0.0
	curr_basis.y = Vector3(0.0, 1.0, 0.0)
	curr_basis.orthonormalized()
	move_direction = curr_basis * move_direction
	move_direction = move_direction.normalized()
	position += move_direction * _speed * delta
	position = Global.wrap_around_pos(position)
	_speed += _acceleration * delta
	if _speed > _max_speed:
		_speed = _max_speed
