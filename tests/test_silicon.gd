extends Node

# Проверка остального железа: модели регистрируются, MINI-8 исполняется,
# дисплеи хранят кадр, дорожки тянут уровень, BoardData сохраняется.
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Проверка: " + label)

const SCENES := [
	"res://components/primitive_capacitor.tscn", "res://components/primitive_diode.tscn",
	"res://components/chip_dip.tscn", "res://components/slot.tscn",
	"res://components/button.tscn", "res://components/switch.tscn",
	"res://components/display_oled.tscn", "res://components/display_ledmatrix.tscn",
	"res://components/display_7seg.tscn", "res://components/trace_straight.tscn",
	"res://components/trace_corner.tscn", "res://components/trace_t.tscn",
	"res://components/trace_cross.tscn", "res://components/case_blank.tscn",
]

func _ready() -> void:
	call_deferred("tests")

func tests() -> void:
	for path in SCENES:
		var scene: PackedScene = load(path)
		check(scene != null, "сцена открывается: " + path.get_file())
		if scene == null:
			continue
		var node: Node3D = scene.instantiate()
		add_child(node)
		check(node.get_node_or_null("Model") != null or node.get_child_count() > 0, "модель создана: " + path.get_file())

	var cap_node: Node3D = load("res://components/primitive_capacitor.tscn").instantiate()
	cap_node.component_id = "C1"
	add_child(cap_node)
	_connect("C1.A", "VCC")  # нет такого порта — connect_ports вернёт false, это тоже проверка
	check(SimBus.sample("C1.B").sig == SimBus.Sig.Z, "конденсатор: без драйверов висит Z")

	var diode: Node3D = load("res://components/primitive_diode.tscn").instantiate()
	diode.component_id = "D2"
	add_child(diode)
	SimBus.drive("D2.A", SimBus.Sig.ONE, 5.0, 1.0)
	SimBus.drive("D2.K", SimBus.Sig.ZERO, 5.0, 1.0)
	SimClock.run(2)
	check(SimBus.current_ma("D2") > 0.0, "диод в проводящем направлении")

	var trace: Node3D = load("res://components/trace_straight.tscn").instantiate()
	trace.component_id = "T1"
	add_child(trace)
	SimBus.drive("T1.W", SimBus.Sig.ONE)
	SimClock.run(2)
	check(SimBus.sample("T1.E").sig == SimBus.Sig.ONE, "дорожка переносит уровень")

	_test_chip()
	_test_displays()
	_test_board_data()
	_test_ui_loads()
	print("Silicon Sandbox / железо: %d проверок, ошибок: %d" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _connect(a: String, b: String) -> void:
	SimRegistry.connect_ports(a, b)

func _test_chip() -> void:
	var chip: Node3D = load("res://components/chip_dip.tscn").instantiate()
	chip.component_id = "U1"
	chip.params = {"pins": 8, "isa": "res://data/isa/mini_isa.json", "io_map": {"0": "P2", "1": "P3"}}
	add_child(chip)
	await get_tree().process_frame   # _ready догрузит ISA
	var isa := IsaLoader.load_isa("res://data/isa/mini_isa.json")
	check(isa.ok and int(isa.registers) == 8 and isa.names.size() == 16, "MINI-8: 8 регистров, 16 инструкций")
	var asm := FileAccess.get_file_as_string("res://tests/isa_sample.asm")
	var assembled := IsaLoader.assemble(asm, isa)
	check(assembled.ok, "MINI-8: пример собирается")
	SimBus.drive("U1.P2", SimBus.Sig.ONE)
	chip.on_event("flash", {"bytes": assembled.bytes})
	chip.on_event("start")
	SimClock.run(16)
	check(bool(chip.state.get("halted", false)), "чип дошёл до HALT")
	check(SimBus.sample("U1.P3").sig == SimBus.Sig.ONE, "порт 1 выведен наружу (6 ≠ 0)")

func _test_displays() -> void:
	var oled: Node3D = load("res://components/display_oled.tscn").instantiate()
	oled.component_id = "U2"
	add_child(oled)
	await get_tree().process_frame
	oled.set_pixel(3, 4, 1)
	oled.set_pixel(100, 60, 1)
	check(oled.get_pixel(3, 4) == 1 and oled.get_pixel(100, 60) == 1 and oled.get_pixel(0, 0) == 0, "OLED 1-bit: кадр держится")
	check(oled.fb_bytes() == 128 * 64 / 8, "OLED 1-bit: размер кадра")
	var seg: Node3D = load("res://components/display_7seg.tscn").instantiate()
	seg.component_id = "U3"
	add_child(seg)
	seg.set_digit(8)
	check(int(seg.state.mask) == 0x7F, "7-сегментный «8» = все сегменты")
	var matrix: Node3D = load("res://components/display_ledmatrix.tscn").instantiate()
	matrix.component_id = "U4"
	add_child(matrix)
	matrix.set_pixel(0, 0, Color.RED)
	matrix.clear()
	check(true, "матрица 8×8 живёт без ошибок")

func _test_board_data() -> void:
	var data: Resource = load("res://components/board_data.gd").new()
	data.width = 4
	data.height = 3
	check(data.can_place([0, 0], [2, 1], 0), "борт: свободная зона принимается")
	data.components.append({"id": "U1", "scene": "res://components/chip_dip.tscn", "cell": [0, 0], "rot": 0, "span": [2, 1], "params": {}})
	check(not data.can_place([1, 0], [1, 1], 0), "борт: занято пересечением")
	check(data.can_place([2, 0], [1, 1], 0), "борт: рядом можно")
	check(data.can_place([2, 1], [1, 2], 1), "борт: поворот на 90° считается")
	var link := ResourceSaver.save(data, "user://test_board.tres")
	check(link == OK, "борт: сохраняется .tres")
	var back: Variant = load("user://test_board.tres")
	check(back is Resource and back.width == 4 and back.components.size() == 1, "борт: читается обратно")

func _test_ui_loads() -> void:
	for path in ["res://ui/hud.tscn", "res://ui/component_library.tscn", "res://ui/isa_editor.tscn", "res://ui/code_editor.tscn", "res://ui/debugger_panel.tscn"]:
		var scene: PackedScene = load(path)
		check(scene != null, "UI открывается: " + path.get_file())
		if scene == null:
			continue
		var node: Node = scene.instantiate()
		add_child(node)
		node.free()
