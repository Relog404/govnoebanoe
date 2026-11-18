extends "res://components/trace_common.gd"

func _init() -> void:
	ports = {"E": "passive", "W": "passive", "N": "passive"}

func trace_layout() -> Dictionary:
	return {"E": Vector3(4.6, 0, 0), "W": Vector3(-4.6, 0, 0), "N": Vector3(0, 0, -4.6)}

func make_mesh() -> Node3D:
	var root := Node3D.new()
	_board_plate(root, [[Vector2i(-5, 0), Vector2i(5, 0)], [Vector2i(0, 0), Vector2i(0, -5)]])
	for cap: Vector2i in [Vector2i(-5, 0), Vector2i(5, 0), Vector2i(0, -5)]:
		end_cap(root, cap)
	return root
