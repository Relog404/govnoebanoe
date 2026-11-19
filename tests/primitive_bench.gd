extends Node3D

# Небольшой рабочий образец для проверки моделей, не сцена редактора платы.
const MM := 0.001

func _ready() -> void:
	$Camera.look_at(Vector3(0, 0.001, 0))
	SimRegistry.connect_ports("R1.B", "D1.A")
	SimRegistry.connect_ports("D1.K", "Q1.C")
	SimBus.drive("R1.A", SimBus.Sig.ONE)
	SimBus.drive("Q1.E", SimBus.Sig.ZERO)
	_line([Vector2(-18, 0), Vector2(-14.08, 0)])
	_line([Vector2(-3.92, 0), Vector2(-1.27, 0)])
	_line([Vector2(1.27, 0), Vector2(1.27, 1.6), Vector2(2.67, 3), Vector2(12, 3), Vector2(13.54, 1.46), Vector2(13.54, 0)])
	_line([Vector2(8.46, 0), Vector2(8.46, -2), Vector2(6, -4.46)])
	_line([Vector2(11, 0), Vector2(11, -4.5)])
	_ink("3V3", -16.8, 1.2, 0.7)
	_ink("R1   330R", -9, 2.8, 0.83)
	_ink("D1", 0, -2.2, 0.83)
	_ink("Q1", 14.5, -2.1, 0.83)
	_ink("GND", 6, -5.2, 0.7)
	_ink("IN", 11, -5.2, 0.7)
	_ink("S I L I C O N    /    D I S C R E T E", -8.9, 7.3, 0.9)
	_ink("01 : 03", 14.9, 7.3, 0.9)
	$Legend/BaseDrive.toggled.connect(_set_base)
	_set_base(true)

func _set_base(high: bool) -> void:
	SimClock.post("Q1", "drive", {"pin": "B", "sig": SimBus.Sig.ONE if high else SimBus.Sig.ZERO})
	SimClock.run(4)
	$Legend/BaseDrive.text = "База Q1: %d" % int(high)
	$Legend/Meter.text = "ТОК D1     %.2f мА\nМОЩНОСТЬ R1     %.2f мВт" % [SimBus.current_ma("D1"), $R1.state.watts * 1000]

func _line(points: Array) -> void:
	for i in points.size() - 1:
		var a := Vector3(points[i].x, 0.025, points[i].y) * MM
		var b := Vector3(points[i+1].x, 0.025, points[i+1].y) * MM
		var trace := BoxMesh.new()
		trace.size = Vector3(0.36 * MM, 0.05 * MM, a.distance_to(b) + 0.12 * MM)
		var mi: MeshInstance3D = $R1.piece(self, trace, (a+b)/(2*MM), $R1.stock(Color("beaa6c"), 0.48))
		mi.look_at(b)

func _ink(text: String, x: float, z: float, height_mm: float) -> void:
	var mark := Label3D.new()
	mark.text = text
	mark.font_size = 48
	mark.pixel_size = MM * height_mm / 48
	mark.modulate = Color("cde2d2")
	mark.outline_size = 0
	mark.position = Vector3(x, 0.065, z) * MM
	mark.rotation.x = -PI / 2
	add_child(mark)
