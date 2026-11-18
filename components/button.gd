extends "res://components/component_base.gd"

# Тактильная кнопка 6×6 мм: прямой контакт при нажатии.
var _cap: MeshInstance3D

func _init() -> void:
	ports = {"1": "passive", "2": "passive"}
	state = {"pressed": false}

func size_mm() -> Vector3:
	return Vector3(6.0, 4.6, 6.0)

func pin_layout_mm() -> Dictionary:
	return {"1": Vector3(-2.54, 0, 0), "2": Vector3(2.54, 0, 0)}

func make_mesh() -> Node3D:
	return make_button(params)

func make_button(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var base := BoxMesh.new()
	base.size = Vector3(6.0, 3.4, 6.0) * MM
	piece(root, base, Vector3.UP * 1.7, stock(Color("1b1e20")))
	var cap := CylinderMesh.new()
	cap.top_radius = 1.55 * MM
	cap.bottom_radius = 1.75 * MM
	cap.height = 1.15 * MM
	cap.radial_segments = 14
	_cap = piece(root, cap, Vector3.UP * 3.95, stock(Color(p.get("cap", "2e3336"))))
	for side: float in [-1.0, 1.0]:
		rod(root, Vector3.RIGHT * 2.54 * side, Vector3.RIGHT * 2.54 * side + Vector3.UP * 0.45, 0.65, stock(SILVER, 0.8))
	return root

func on_event(kind: String, data: Dictionary) -> void:
	super.on_event(kind, data)
	if kind == "set" and data.has("pressed"):
		var v := bool(data.pressed)
		if v != state.pressed:
			state.pressed = v
			SimRegistry.wake(component_id)
			refresh_visual()

func refresh_visual() -> void:
	if _cap:
		_cap.position.y = (3.95 - 0.42) * MM if state.get("pressed", false) else 3.95 * MM

func tick(_at: int) -> void:
	if state.pressed:
		SimBus.branch(component_id, endpoint("1"), endpoint("2"), 0.001)
	else:
		SimBus.open_branch(component_id)
