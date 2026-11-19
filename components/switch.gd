extends "res://components/component_base.gd"

# Однополюсный двухпозиционный переключатель: COM замыкается на A или на B.
func _init() -> void:
	ports = {"COM": "passive", "A": "passive", "B": "passive"}
	state = {"position": 0}   # 0 → A, 1 → B.

func size_mm() -> Vector3:
	return Vector3(9.2, 3.9, 4.4)

func pin_layout_mm() -> Dictionary:
	return {"COM": Vector3.ZERO, "A": Vector3.RIGHT * -3.2, "B": Vector3.RIGHT * 3.2}

func make_mesh() -> Node3D:
	return make_switch(params)

func make_switch(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var base := BoxMesh.new()
	base.size = Vector3(9.2, 2.4, 4.4) * MM
	piece(root, base, Vector3.UP * 1.2, stock(Color("1a1d1f")))
	var paddle := BoxMesh.new()
	paddle.size = Vector3(2.1, 1.6, 3.0) * MM
	piece(root, paddle, Vector3.UP * 3.05, stock(Color(p.get("knob", "b0463a"))))
	for x: float in [-3.2, 0.0, 3.2]:
		rod(root, Vector3(x, 0, 1.1), Vector3(x, 0.55, 1.1), 0.65, stock(SILVER, 0.8))
	return root

func on_event(kind: String, data: Dictionary) -> void:
	super.on_event(kind, data)
	if kind == "flip":
		state.position = int(data.get("position", 1 - int(state.get("position", 0)))) & 1
		SimRegistry.wake(component_id)

func tick(_at: int) -> void:
	var target: String = "B" if int(state.position) == 1 else "A"
	SimBus.branch(component_id, endpoint("COM"), endpoint(target), 0.001)
