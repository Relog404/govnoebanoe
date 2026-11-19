extends "res://components/component_base.gd"

func _init() -> void:
	ports = {"A": "in", "K": "in"}
	state = {"burned": false, "ma": 0.0}

func size_mm() -> Vector3:
	return Vector3(9.4, 2.7, 2.5)

func pin_layout_mm() -> Dictionary:
	return {"A": Vector3.LEFT * 4.35, "K": Vector3.RIGHT * 4.35}

func make_mesh() -> Node3D:
	return make_diode(params)

func make_diode(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var tin := stock(SILVER, 0.82)
	for side: float in [-1.0, 1.0]:
		var end := Vector3.RIGHT * 4.35 * side
		rod(root, end, Vector3.RIGHT*2.20*side+Vector3.UP*1.26, 0.66, tin)
	var body := CylinderMesh.new()
	body.top_radius = 1.26 * MM
	body.bottom_radius = 1.26 * MM
	body.height = 4.35 * MM
	body.radial_segments = 14
	_body_and_band(root, body, p)
	return root

func _body_and_band(root: Node3D, body: CylinderMesh, p: Dictionary) -> void:
	var axis := Vector3.RIGHT
	var mi := piece(root, body, Vector3.UP * 1.26, stock(Color(p.get("color", "23272a"))))
	mi.quaternion = Quaternion(Vector3.UP, axis)
	# Серебряная полоса катода — всегда у вывода K (правая сторона).
	var band := CylinderMesh.new()
	band.top_radius = 1.27 * MM
	band.bottom_radius = 1.27 * MM
	band.height = 0.85 * MM
	band.radial_segments = 14
	var m := piece(root, band, Vector3(1.55, 1.26, 0), stock(Color("d8d5cb")))
	m.quaternion = Quaternion(Vector3.UP, axis)

func tick(_at: int) -> void:
	var a := read_pin("A")
	var k := read_pin("K")
	# Обратное пробивание: 50 В максимум по спецификации.
	if a.volts != null and k.volts != null and float(a.volts) - float(k.volts) < -float(params.get("vr_max", 50.0)):
		state.burned = true
	state.ma = SimBus.current_ma(component_id)
	if state.burned:
		SimBus.open_branch(component_id)
	else:
		SimBus.branch(component_id, endpoint("A"), endpoint("K"), float(params.get("rs", 0.5)), maxf(0, float(params.get("vf", 0.7))))
