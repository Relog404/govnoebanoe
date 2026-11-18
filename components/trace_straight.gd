extends "res://components/trace_common.gd"

func _init() -> void:
	ports = {"E": "passive", "W": "passive"}

func trace_layout() -> Dictionary:
	return {"E": Vector3(4.6, 0, 0), "W": Vector3(-4.6, 0, 0)}

func make_mesh() -> Node3D:
	var root := Node3D.new()
	_board_plate(root, [[Vector2i(-5, 0), Vector2i(5, 0)]])
	for x: int in [-5, 5]:
		end_cap(root, Vector2i(x, 0))
	return root
