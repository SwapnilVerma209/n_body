extends CanvasLayer

func _process(float) -> void:
	var position = $"../Player".position
	var distance = position.length()
	var coord_time = $"..".coord_time
	var timestep = $"..".timestep
	var pos_string = "Position: <%d, %d, %d> (%d) %s" % [position.x, \
			position.y, position.z, distance, Global.space_unit]
	var coord_time_string = "Coordinate time: %f %s" % [coord_time, \
			Global.time_unit]
	var timestep_string = "Timestep: %f %s" % [timestep, Global.time_unit]
	var position_label = $"./PositionLabel"
	var time_label = $"./TimeLabel"
	position_label.text = pos_string
	time_label.text = coord_time_string + "\n" + timestep_string
