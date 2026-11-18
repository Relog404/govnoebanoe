extends "res://components/component_base.gd"

const BANDS := ["201e1c", "693726", "bb473b", "ed812e", "eac544", "477b4c", "3563a0", "835694", "858986", "ece8da"]
var _body: MeshInstance3D
var _enamel: StandardMaterial3D

func _init() -> void:
	ports = {"A": "passive", "B": "passive"}
	state = {"burned": false, "watts": 0.0}

func size_mm() -> Vector3:
	return Vector3(11.6, 2.5, 2.3)

func pin_layout_mm() -> Dictionary:
	return {"A": Vector3.LEFT * 5.08, "B": Vector3.RIGHT * 5.08}

func make_mesh() -> Node3D:
	return make_resistor(params)

func make_resistor(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var tin := stock(SILVER, 0.83)
	var y := Vector3.UP * 1.35
	for sign_x: float in [-1.0, 1.0]:
		var end := Vector3.RIGHT * 5.08 * sign_x
		rod(root, end, end+y, 0.65, tin)
		rod(root, end+y, Vector3.RIGHT*3.05*sign_x+y, 0.65, tin)
	_enamel = stock(Color("c8b787"))
	_body = rod(root, Vector3.LEFT*3.15+y, Vector3.RIGHT*3.15+y, 2.26, _enamel)
	# Две значащие цифры, множитель и допуск ±5 %.
	var r := clampf(float(p.get("ohms", 330)), 0.1, 9.9e10)
	var exponent := floori(log(r) / log(10.0)) - 1
	var digits := roundi(r / pow(10.0, exponent))
	if digits == 100:
		digits = 10
		exponent += 1
	var multiplier: String = BANDS[clampi(exponent, 0, 9)]
	if exponent < 0: multiplier = "c4a361" if exponent == -1 else "b6bcc1"
	var colors := [BANDS[floori(digits * 0.1)], BANDS[digits % 10], multiplier, "c4a361"]
	for i in 4:
		var x := float([-2.1, -1.1, -0.1, 2.05][i])
		rod(root, Vector3.RIGHT*x+y, Vector3.RIGHT*(x+0.4)+y, 2.30, stock(Color(colors[i])))
	return root

func tick(_at: int) -> void:
	var r := clampf(float(params.get("ohms", 330)), 0.1, 9.9e10)
	state.watts = pow(SimBus.current_ma(component_id) * 0.001, 2) * r
	if state.watts > clampf(float(params.get("rated_w", 0.25)), 0.125, 5.0):
		state.burned = true
	if state.burned:
		SimBus.open_branch(component_id)
	else:
		SimBus.branch(component_id, endpoint("A"), endpoint("B"), r)
	refresh_visual()

func refresh_visual() -> void:
	if _body:
		_body.material_override = stock(Color("302a28")) if state.burned else _enamel
