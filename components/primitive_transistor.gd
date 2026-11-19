extends "res://components/component_base.gd"

func _init() -> void:
	ports = {"E": "in", "B": "in", "C": "out"}

func size_mm() -> Vector3:
	return Vector3(6.5, 6.1, 3.6)

func pin_layout_mm() -> Dictionary:
	return {"E": Vector3.LEFT * 2.54, "B": Vector3.ZERO, "C": Vector3.RIGHT * 2.54}

func make_mesh() -> Node3D:
	return make_transistor(params)

func make_transistor(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var tin := stock(SILVER, 0.82)
	for i in range(-1, 2):
		var bend := Vector3(i * 2.54, 0.85, 0)
		rod(root, Vector3(i * 2.54, 0, 0), bend, 0.66, tin)
		rod(root, bend, Vector3(i * 1.6, 2.8, 0), 0.66, tin)
	# D-образный срез TO-92: плоская передняя стенка указывает распиновку.
	var rim := PackedVector3Array([Vector3(-2.35, 0, 1.1), Vector3(2.35, 0, 1.1)])
	for i in 11:
		var a := PI * i / 10.0
		rim.append(Vector3(2.35 * cos(a), 0, -1.7 * sin(a)))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rim.size():
		var u := rim[i] + Vector3.UP * 2.5
		var v := rim[(i + 1) % rim.size()] + Vector3.UP * 2.5
		var h := Vector3.UP * 3.6
		for vertex: Vector3 in [u, v+h, v, u, u+h, v+h, u+h, Vector3.UP*6.1, v+h, u, v, Vector3.UP*2.5]:
			surface.set_smooth_group(-1)
			surface.add_vertex(vertex * MM)
	surface.generate_normals()
	piece(root, surface.commit(), Vector3.ZERO, stock(Color.from_string(str(p.get("color", "25292a")), Color.DARK_GRAY)))
	return root

func tick(_at: int) -> void:
	# NPN как цифровой ключ: коллектор умеет только тянуть к нулю.
	var b := int(read_pin("B").sig)
	var e := int(read_pin("E").sig)
	var c := SimBus.Sig.Z
	if b == SimBus.Sig.ONE and e == SimBus.Sig.ZERO:
		c = SimBus.Sig.ZERO
	elif (b == SimBus.Sig.X and e == SimBus.Sig.ZERO) or (b in [SimBus.Sig.ONE, SimBus.Sig.X] and e == SimBus.Sig.X):
		c = SimBus.Sig.X
	SimBus.drive(endpoint("C"), c)
