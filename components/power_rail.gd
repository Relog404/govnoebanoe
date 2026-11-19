extends "res://components/component_base.gd"

# Лабораторный блок питания: VCC = 1 навсегда, GND = 0 навсегда.
# В схеме не источник конфликта — пока его не закоротить с другим драйвером.
func _init() -> void:
	ports = {"VCC": "optional", "GND": "optional"}
	state = {"on": true}

func size_mm() -> Vector3:
	return Vector3(22.0, 14.0, 16.0)

func pin_layout_mm() -> Dictionary:
	return {"VCC": Vector3(-2.54, 0, 8.0), "GND": Vector3(2.54, 0, 8.0)}

func make_mesh() -> Node3D:
	return make_power_rail(params)

func make_power_rail(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(22.0, 12.6, 16.0) * MM
	piece(root, body, Vector3.UP * 6.3, stock(Color("2b2f33"), 0.3, 0.55))
	var face := BoxMesh.new()
	face.size = Vector3(20.6, 9.0, 0.8) * MM
	piece(root, face, Vector3(0, 6.5, 7.65), stock(Color("343a40"), 0.35, 0.4))
	# Цифровой индикатор напряжения (декоративный, светится).
	var disp := BoxMesh.new()
	disp.size = Vector3(9.5, 3.6, 0.5) * MM
	var disp_mat := StandardMaterial3D.new()
	disp_mat.albedo_color = Color("f5c15d")
	disp_mat.emission_enabled = true
	disp_mat.emission = Color("f5a83d")
	disp_mat.emission_energy_multiplier = 1.5
	piece(root, disp, Vector3(-3.2, 7.6, 8.1), disp_mat)
	var knob := CylinderMesh.new()
	knob.top_radius = 2.3 * MM
	knob.bottom_radius = 2.3 * MM
	knob.height = 1.6 * MM
	knob.radial_segments = 16
	var k_mi := piece(root, knob, Vector3(6.2, 6.2, 8.0), stock(Color("14161a"), 0.6, 0.35))
	k_mi.rotation.x = PI * 0.5
	for x: float in [-2.54, 2.54]:
		rod(root, Vector3(x, 0, 8.8), Vector3(x, 0.5, 8.8), 1.5, stock(SILVER, 0.85))
	return root

func tick(_at: int) -> void:
	if not state.get("on", true):
		return
	SimBus.drive(endpoint("VCC"), SimBus.Sig.ONE, float(params.get("volts", 3.3)), 5.0)
	SimBus.drive(endpoint("GND"), SimBus.Sig.ZERO, 0.0, 5.0)
