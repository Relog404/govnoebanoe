extends "res://components/component_base.gd"

# Корпус-заготовка: только механика, в схеме не участвует (пустой id по умолчанию).
func _init() -> void:
	ports = {}        # Нет портов → не регистрируется в симуляции.

func size_mm() -> Vector3:
	return Vector3(120.0, 25.0, 80.0)

func make_mesh() -> Node3D:
	var root := Node3D.new()
	var wall := stock(Color("20262b"), 0.15, 0.55)
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(120.0, 2.0, 80.0) * MM
	piece(root, floor_box, Vector3.UP * 1.0, wall)
	var sides := [
		[Vector3(0, 12.5, -39.0), Vector3(120.0, 23.0, 2.0)],
		[Vector3(0, 12.5, 39.0),  Vector3(120.0, 23.0, 2.0)],
		[Vector3(-59.0, 12.5, 0), Vector3(2.0, 23.0, 80.0)],
		[Vector3(59.0, 12.5, 0),  Vector3(2.0, 23.0, 80.0)],
	]
	for def: Array in sides:
		var m := BoxMesh.new()
		m.size = def[1] * MM
		piece(root, m, def[0], wall)
	# Четыре стойки под плату.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var post := CylinderMesh.new()
			post.top_radius = 2.4 * MM
			post.bottom_radius = 2.4 * MM
			post.height = 6.0 * MM
			post.radial_segments = 12
			piece(root, post, Vector3(sx * 50.0, 5.0, sz * 32.0), stock(Color("2c343b"), 0.1, 0.6))
	return root
