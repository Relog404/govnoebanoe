extends Node

const R := preload("res://components/primitive_resistor.tscn")
const D := preload("res://components/primitive_led.tscn")
const Q := preload("res://components/primitive_transistor.tscn")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Проверка: " + label)

func part(scene: PackedScene, id: String, params: Dictionary = {}) -> Node3D:
	var p: Node3D = scene.instantiate()
	p.component_id = id
	p.params = params
	add_child(p)
	return p

func mouse(key: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.pressed = true
	e.button_index = key
	return e

func _ready() -> void:
	call_deferred("tests")

func tests() -> void:
	var r := part(R, "R1")
	var d := part(D, "D1")
	var q := part(Q, "Q1")
	check((r.get_node("Model") as Node3D).get_child_count() >= 9, "процедурная сборка")
	check(is_equal_approx(q.get_node("C").position.x, 2.54e-3), "миллиметры и шаг выводов")
	check(d.get_node("Body").get_child(0) is CollisionShape3D, "коллайдер под луч")
	check(SimRegistry.connect_ports("R1.B", "D1.A"), "первая дорожка")
	check(not SimRegistry.connect_ports("D1.A", "R1.B"), "запрет дубля")
	check(not SimRegistry.connect_ports("D1.A", "Q404.B"), "проверка адреса")
	SimRegistry.connect_ports("D1.K", "Q1.C")
	SimBus.drive("R1.A", SimBus.Sig.ONE)
	SimBus.drive("Q1.E", SimBus.Sig.ZERO)
	SimClock.post("Q1", "drive", {"pin":"B", "sig":SimBus.Sig.ONE})
	SimClock.run(5)
	var ma := 1500.0 / 380.0
	check(is_equal_approx(SimBus.current_ma("D1"), ma), "ток LED через резистор и NPN")
	check(is_equal_approx(r.state.watts, 330.0 * pow(ma / 1000, 2)), "I²R")
	check(not d.state.burned and not r.state.burned, "рабочие номиналы")
	check(SimBus.sample("D1.K").sig == SimBus.Sig.ZERO, "открытый коллектор")
	check(is_equal_approx(SimBus.sample("R1.A").ma, ma), "ток тестера на шине")
	SimClock.post("Q1", "drive", {"pin":"B", "sig":1}, 2, 10)
	SimClock.post("Q1", "drive", {"pin":"B", "sig":1}, 2, -1)
	SimClock.post("Q1", "drive", {"pin":"B", "sig":0}, 2, 10)
	SimBus.pull("Q1.C", SimBus.Sig.ONE, 5.0)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(SimClock.snapshot(), "", true, true))
	SimClock.run(5)
	check(SimBus.sample("Q1.B").sig == SimBus.Sig.ZERO, "приоритет и FIFO в один срок")
	check(SimBus.sample("D1.K").volts == 5.0, "освобождённый коллектор + подтяжка")
	check(SimBus.current_ma("D1") == 0, "обратное смещение")
	var expected: Variant = JSON.parse_string(JSON.stringify(SimClock.snapshot(), "", true, true))
	SimRegistry.disconnect_ports("D1.K", "Q1.C")
	check(SimClock.restore(snap), "откат JSON вместе с топологией, очередью и pending drive")
	SimClock.run(5)
	var actual: Variant = JSON.parse_string(JSON.stringify(SimClock.snapshot(), "", true, true))
	check(actual == expected, "бит-в-бит воспроизводимые логические состояния")
	var bad := snap.duplicate(true)
	bad.bus.drivers = "ошибка"
	check(not SimClock.restore(bad), "отказ от повреждённого снимка")
	bad = snap.duplicate(true)
	bad.registry.layout.erase("Q1")
	check(not SimClock.restore(bad), "другая сборка не принимается")
	# Конфликт проверяем на пассивной сети: транзистор на следующем такте
	# честно стирает посторонний драйвер на своё выходном контакте.
	SimBus.drive("R1.B", SimBus.Sig.ONE)
	SimBus.drive("D1.A", SimBus.Sig.ONE)
	SimClock.step()
	check(SimBus.sample("R1.B").sig == SimBus.Sig.X, "два активных владельца даже при 1/1")
	SimBus.drive("D1.A", SimBus.Sig.ZERO)
	SimClock.step()
	check(SimBus.sample("R1.B").fault == "short", "КЗ при 1/0")
	check("КЗ: D1.A" in SimRegistry.validate(), "диагностика сети")
	SimBus.drive("R1.B", SimBus.Sig.Z)
	SimBus.drive("D1.A", SimBus.Sig.Z)
	SimBus.drive("Q1.C", SimBus.Sig.Z)
	SimBus.drive("D1.K", SimBus.Sig.Z)
	SimBus.pull("D1.K", SimBus.Sig.ZERO)
	SimClock.step()
	check(SimBus.sample("Q1.C").sig == SimBus.Sig.X, "противоположные подтяжки")
	SimBus.pull("D1.K", SimBus.Sig.Z)
	SimBus.pull("Q1.C", SimBus.Sig.Z)
	SimClock.step()
	check(SimBus.sample("Q1.C").volts == null, "Z не выдумывает напряжение")
	SimClock.post("Q1", "drive", {"pin":"E", "sig":1}, 2)
	q.free()
	q = part(Q, "Q1")
	SimClock.run(3)
	check(SimBus.sample("Q1.E").sig == SimBus.Sig.Z, "удаление отменяет события до повторного id")
	SimRegistry.disconnect_ports("R1.B", "D1.A")
	SimBus.drive("D1.A", SimBus.Sig.ONE, 5.0)
	SimBus.drive("D1.K", SimBus.Sig.ZERO)
	SimClock.run(4)
	check(d.state.burned and SimBus.current_ma("D1") == 0, "LED >20 мА переходит в обрыв")
	r.params.ohms = 10
	r.params.rated_w = 5
	SimRegistry.wake("R1")
	SimBus.drive("R1.A", SimBus.Sig.ONE, 5.0, 1.0)
	SimBus.drive("R1.B", SimBus.Sig.ZERO, 5.0, 1.0)
	SimClock.run(4)
	check(not r.state.burned and r.state.watts > 1.0, "5-ваттный номинал выдерживает нагрузку")
	r.params.rated_w = 0.125
	SimRegistry.wake("R1")
	SimClock.run(3)
	check(r.state.burned and SimBus.current_ma("R1") == 0, "резистор сгорает по номиналу")
	q.ports.B = "clock_in"
	check("Нет источника такта: Q1.B" in SimRegistry.validate(), "валидация тактового входа")
	_test_tools()
	_test_isa()
	print("Silicon Sandbox: %d проверок, ошибок: %d" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _test_tools() -> void:
	ToolManager.select(ToolManager.Tool.IRON)
	ToolManager.apply(mouse(MOUSE_BUTTON_LEFT), {"pin":"Q1.B"})
	check(ToolManager.first_pin == "Q1.B", "первый контакт паяльника")
	ToolManager.select(ToolManager.Tool.LOUPE)
	var wires: Array = SimRegistry.snapshot().wires
	var target := {"pin":"D1.K", "point":Vector3.RIGHT}
	ToolManager.apply(mouse(MOUSE_BUTTON_LEFT), target)
	for i in 5: ToolManager.apply(mouse(MOUSE_BUTTON_WHEEL_UP), target)
	check(ToolManager.zoom == 8 and ToolManager.locked, "фокус и предел лупы")
	check(ToolManager.first_pin.is_empty() and SimRegistry.snapshot().wires == wires, "лупа не редактирует плату")
	ToolManager.apply(mouse(MOUSE_BUTTON_RIGHT), target)
	check(ToolManager.zoom == 1 and not ToolManager.locked, "сброс лупы")
	ToolManager.select(ToolManager.Tool.IRON)
	ToolManager.apply(mouse(MOUSE_BUTTON_LEFT), {"pin":"Q1.B"})
	ToolManager.apply(mouse(MOUSE_BUTTON_LEFT), {"pin":"D1.K"})
	check(SimRegistry.snapshot().wires.size() == wires.size()+1, "пайка двух портов")
	ToolManager.select(ToolManager.Tool.TWEEZERS)
	ToolManager.apply(mouse(MOUSE_BUTTON_LEFT), {"id":"D1"})
	ToolManager.apply(mouse(MOUSE_BUTTON_LEFT), {"can_place":false})
	check(ToolManager.held == "D1", "не отпускать на занятой клетке")
	ToolManager.apply(mouse(MOUSE_BUTTON_RIGHT), {})
	check(ToolManager.held.is_empty(), "отмена перемещения")

func _test_isa() -> void:
	var spec := {"registers":3, "instructions":[
		{"name":"LIT","code":42,"args":["r","u8"],"do":[["mov",0,1]]},
		{"name":"PLUS","code":7,"args":["r","u8"],"do":[["add",0,1]]},
		{"name":"SKIPZ","code":200,"args":["r","addr"],"do":[["jz",0,1]]},
		{"name":"READ","code":91,"args":["r","u8"],"do":[["in",0,1]]},
		{"name":"SAVE","code":13,"args":["addr","r"],"do":[["st",0,1]]},
		{"name":"LOAD","code":11,"args":["r","addr"],"do":[["ld",0,1]]},
		{"name":"SEND","code":84,"args":["u8","r"],"do":[["out",0,1]]},
		{"name":"STOP","code":0,"do":[["halt"]]}]}
	var isa := IsaLoader.compile_isa(JSON.stringify(spec))
	check(isa.ok, "компиляция пользовательской ISA")
	var asm := "LIT R0, 0xFF ; переполнение\nPLUS R0, 1\nSKIPZ R0, port\nSTOP\nport: READ R1, 2\nSAVE 0x80, R1\nLOAD R2, 0x80\nSEND 3, R2\nSTOP"
	var assembled := IsaLoader.assemble(asm, isa)
	check(assembled.ok, "сборка с меткой вперёд")
	if not assembled.ok: return
	var listing := IsaLoader.disassemble(assembled.bytes, isa)
	check(listing.ok and IsaLoader.assemble(listing.source, isa).bytes == assembled.bytes, "полный цикл дизассемблера")
	var vm := IsaLoader.flash(assembled.bytes, isa)
	vm.inputs["2"] = 77
	for i in 16:
		if not IsaLoader.execute(vm, isa, "TEST"): break
	check(vm.halted and vm.fault == "" and vm.regs == [0,77,77], "исполнение, переход и регистры")
	check(vm.ram[128] == 77 and vm.outputs.get("3") == 77, "память и протокол I/O")
	check(not IsaLoader.assemble("LIT R3, 1", isa).ok, "границы регистров")
	check(not IsaLoader.assemble("LIT R0, 256", isa).ok, "границы байта")
	check(not IsaLoader.assemble("SKIPZ R0, missing", isa).ok, "неизвестная метка")
	check(not IsaLoader.disassemble([42,0], isa).ok, "неполная машинная инструкция")
	var broken := IsaLoader.flash([42,255,1], isa)
	check(not IsaLoader.execute(broken, isa, "TEST") and broken.halted, "повреждённая прошивка: останов без вылета")
	spec.instructions[0]["do"] = [["mov",1,0]]
	check(not IsaLoader.compile_isa(JSON.stringify(spec)).ok, "запрет записи в литерал")
	spec.instructions[0].code = 7
	check(not IsaLoader.compile_isa(JSON.stringify(spec)).ok, "повреждённая таблица")
