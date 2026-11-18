# Общий код дорожек: тонкая медная полоса поверх платы; внутренние
# «цепи» нулевого сопротивления между всеми выводами.
extends "res://components/component_base.gd"

const TRACE_H := 0.07
const TRACE_W := 1.4
func _init() -> void:
	ports = {}

func trace_layout() -> Dictionary:
	# По умолчанию: N/S/E/W по краям клетки 10×10 мм.
	return {
		"N": Vector3(0, 0, -4.6), "S": Vector3(0, 0, 4.6),
		"E": Vector3(4.6, 0, 0),  "W": Vector3(-4.6, 0, 0),
	}

func pin_layout_mm() -> Dictionary:
	return trace_layout()

func _board_plate(root: Node3D, segments: Array) -> void:
	# segments: массив [from: Vector2i, to: Vector2i] в мм-плато дорожки.
	var copper := stock(Color("c8a15c"), 0.75, 0.32)
	piece(root, BoxMesh_instance(10.0, 0.35, 10.0), Vector3.UP * 0.175, stock(Color("0e4d3f"), 0.1, 0.6))
	for seg: Array in segments:
		var a := Vector2(seg[0])
		var b := Vector2(seg[1])
		var d := b - a
		var len_v := d.length()
		var m := BoxMesh.new()
		m.size = Vector3(TRACE_W, TRACE_H, len_v + TRACE_W) * MM
		var mi := piece(root, m, Vector3((a.x + b.x) * 0.5, TRACE_H + 0.35, (a.y + b.y) * 0.5), copper)
		mi.rotation.y = atan2(d.x, d.y)

func end_cap(root: Node3D, at: Vector2i) -> void:
	var m := CylinderMesh.new()
	m.top_radius = TRACE_W * 0.62 * MM
	m.bottom_radius = m.top_radius
	m.height = TRACE_H * 2.4 * MM
	m.radial_segments = 14
	piece(root, m, Vector3(at.x, TRACE_H * 1.6, at.y), stock(Color("d4b06a"), 0.8, 0.3))

func BoxMesh_instance(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z) * MM
	return m

func tick(_at: int) -> void:
	# Дорожка — короткое замыкание: ведёт уровень между всеми выводами.
	var pins := pin_layout_mm().keys()
	pins.sort()
	for i in range(1, pins.size()):
		SimBus.branch(component_id + ":" + str(i), endpoint(pins[0]), endpoint(pins[i]), 0.001)
