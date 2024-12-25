extends Camera3D

var _accel
const _angular_accel := PI / (1.0**2 / 2.0)
const _max_angular_speed := 2.0 * PI

var _speed := 0.0
var _angular_speed := 0.0

# Called when the node enters the scene tree for the first time.
## Set player a quarter of the way towards the outer corner of the first octant,
## facing towards the origin
func _ready() -> void:
	far = 2e11
	_accel = Global.MAX_AXIS_DIST / (5.0**2 / 2.0)
	position = 10.0 * Vector3(1.0, 1.0, 1.0)
	transform = transform.looking_at(Vector3(0.0, 0.0, 0.0))
	transform = transform.orthonormalized()

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
		_angular_speed += _angular_accel * delta
		if _angular_speed > _max_angular_speed:
			_angular_speed = _max_angular_speed
	else:
		_angular_speed = 0.0
		
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
	_speed += _accel * delta
