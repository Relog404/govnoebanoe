extends "res://components/component_base.gd"

var _lens: StandardMaterial3D
var _hue: Color

func _init() -> void:
	ports = {"A": "in", "K": "in"}
	state = {"burned": false, "ma": 0.0}

func size_mm() -> Vector3:
	return Vector3(4.0, 5.0, 2.7)

func pin_layout_mm() -> Dictionary:
	return {"A": Vector3.LEFT * 1.27, "K": Vector3.RIGHT * 1.27}

func make_mesh() -> Node3D:
	return make_led(params)

func make_led(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	for side: float in [-1.0, 1.0]:
		rod(root, Vector3.RIGHT*1.27*side, Vector3(0.76*side, 1.6, 0), 0.65, stock(SILVER, 0.8))
	_hue = Color.from_string(str(p.get("color", "ff492f")), Color.ORANGE_RED)
	_lens = StandardMaterial3D.new()  # Эмиссия индивидуальна, не разделяем материал.
	_lens.roughness = 0.24
	_lens.emission = _hue
	rod(root, Vector3.UP*1.45, Vector3.UP*1.78, 2.70, _lens)
	rod(root, Vector3.UP*1.78, Vector3.UP*3.75, 2.5, _lens)
	var cap := SphereMesh.new()
	cap.radius = 1.25 * MM
	cap.height = cap.radius
	cap.radial_segments = 12
	cap.rings = 6
	cap.is_hemisphere = true
	piece(root, cap, Vector3.UP*3.75, _lens)
	return root

func tick(_at: int) -> void:
	state.ma = SimBus.current_ma(component_id)
	if state.ma > 20.0:
		state.burned = true
	if state.burned:
		SimBus.open_branch(component_id)
	else:
		SimBus.branch(component_id, endpoint("A"), endpoint("K"), 0.0, maxf(0, float(params.get("vf", 1.8))))
	refresh_visual()

func refresh_visual() -> void:
	if not _lens: return
	_lens.albedo_color = Color("392c29") if state.burned else _hue.darkened(0.38)
	_lens.emission_enabled = not state.burned and state.ma > 0.0
	_lens.emission_energy_multiplier = clampf(float(state.ma) * 0.22, 0, 4.4)
