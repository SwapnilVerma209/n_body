extends Node3D

var body_scene = load("res://body.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for i in range(1000):
		randomize()
		var body = body_scene.instantiate()
		var radius := randf_range(1.0, 1e9)
		body.mesh.radius = radius
		body.mesh.height = 2.0 * radius
		body.position = Vector3( \
				randf_range(-Global.MAX_AXIS_DIST, Global.MAX_AXIS_DIST), \
				randf_range(-Global.MAX_AXIS_DIST, Global.MAX_AXIS_DIST), \
				randf_range(-Global.MAX_AXIS_DIST, Global.MAX_AXIS_DIST))
		$Bodies.add_child(body)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
