extends "res://components/component_base.gd"

# 8×8 светодиодная матрица: 64 точки одним MultiMeshInstance3D,
# цвет экземпляра = яркость. Порты имитируют строки/столбцы (только чтение сигналов).
const N := 8
var _mm: MultiMeshInstance3D
var _colors: PackedColorArray = PackedColorArray()

func _init() -> void:
	ports = {}
	for i in N:
		ports["R%d" % i] = "in"
		ports["C%d" % i] = "in"
	state = {"on": 0}

func size_mm() -> Vector3:
	return Vector3(32.0, 3.0, 32.0)

func pin_layout_mm() -> Dictionary:
	var out := {}
	for i in N:
		out["R%d" % i] = Vector3((i - 3.5) * 2.54, 0, 13.6)
		out["C%d" % i] = Vector3((i - 3.5) * 2.54, 0, -13.6)
	return out

func make_mesh() -> Node3D:
	var root := Node3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(32.0, 2.8, 32.0) * MM
	piece(root, body, Vector3.UP * 1.4, stock(Color("101315"), 0.1, 0.55))
	_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	var dot := SphereMesh.new()
	dot.radius = 1.52 * MM
	dot.height = dot.radius * 1.35
	dot.radial_segments = 10
	dot.rings = 5
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = dot
	mm.instance_count = N * N
	for y in N:
		for x in N:
			var t := Transform3D()
			t.origin = Vector3((x - 3.5) * 3.6, 2.95, (y - 3.5) * 3.6) * MM
			mm.set_instance_transform(y * N + x, t)
			mm.set_instance_color(y * N + x, Color(0.02, 0.02, 0.02))
	_mm.multimesh = mm
	root.add_child(_mm)
	return root

func set_pixel(x: int, y: int, value: Color) -> void:
	if x < 0 or y < 0 or x >= N or y >= N:
		return
	_mm.multimesh.set_instance_color(y * N + x, value)

func clear() -> void:
	for y in N:
		for x in N:
			set_pixel(x, y, Color(0.02, 0.02, 0.02))

func tick(_at: int) -> void:
	# Сканирование строк/столбцов: точка горит, если строка=1 и столбец=0 (общий анод).
	var rows := []
	var cols := []
	rows.resize(N)
	cols.resize(N)
	for i in N:
		var r := read_pin("R%d" % i)
		var c := read_pin("C%d" % i)
		rows[i] = float(r.volts) > 1.65 if r.volts != null else (r.sig == SimBus.Sig.ONE)
		cols[i] = float(c.volts) > 1.65 if c.volts != null else (c.sig == SimBus.Sig.ONE)
	var on := 0
	var tint: Color = Color.from_string(str(params.get("tint", "ff7a1f")), Color.ORANGE_RED)
	for y in N:
		for x in N:
			var lit: bool = rows[y] and not cols[x]
			set_pixel(x, y, tint * (1.0 if lit else 0.0) + Color(0.02, 0.02, 0.02))
			if lit: on += 1
	state.on = on
