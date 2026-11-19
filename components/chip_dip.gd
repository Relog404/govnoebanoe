extends "res://components/component_base.gd"

# Универсальный DIP пользователя: поведения «в кремнии» нет.
# Чип исполняет ISA игрока из definition.isa_path, прошитую через событие
# on_event("flash", {"bytes": [...]}). I/O-карта io_map: номер порта VM → имя пина.
var _isa: Dictionary = {}
var _vm: Dictionary = {}
var _running := false
var _pin_count := 8

func _init() -> void:
	ports = {"P1":"in","P2":"in","P3":"in","P4":"in","P5":"in","P6":"in","P7":"in","P8":"in"}
	state = {"pc": 0, "cycles": 0, "halted": true, "fault": "", "reg": []}

func size_mm() -> Vector3:
	return Vector3(9.4 if _pin_count == 8 else 19.0, 3.2, 6.4 if _pin_count == 8 else 7.0)

func pin_layout_mm() -> Dictionary:
	# Две боковые стороны, шаг 2.54 мм, ряды симметрично относительно центра.
	var n := _pin_count / 2
	var body := size_mm()
	var out := {}
	for i in n:
		var x := (i - (n - 1) * 0.5) * 2.54
		out["P%d" % (i + 1)] = Vector3(x, 0, body.z * 0.5 + 0.9)
	for i in n:
		var x := ((n - 1 - i) - (n - 1) * 0.5) * 2.54
		out["P%d" % (_pin_count + 1 - (i + 1))] = Vector3(x, 0, -(body.z * 0.5 + 0.9))
	return out

func make_mesh() -> Node3D:
	return make_dip(params)

func make_dip(p: Dictionary) -> Node3D:
	_pin_count = 16 if int(p.get("pins", 8)) == 16 else 8
	var body := size_mm()
	var root := Node3D.new()
	var plastic := stock(Color("171a1c"))
	piece(root, BoxMesh_sized(body.x, 2.9, body.z), Vector3.UP * 1.85, plastic)
	var dot := CylinderMesh.new()
	dot.top_radius = 0.55 * MM
	dot.bottom_radius = 0.55 * MM
	dot.height = 0.06 * MM
	dot.radial_segments = 12
	piece(root, dot, Vector3(-body.x * 0.5 + 2.54, 3.32, body.z * 0.5 - 1.6), stock(Color("c9c3b2")))
	# Полукруглая выемка на торце — метка ключа.
	var notch := CylinderMesh.new()
	notch.top_radius = 1.5 * MM
	notch.bottom_radius = 1.5 * MM
	notch.height = 2.9 * MM
	notch.radial_segments = 16

	var n_mi := piece(root, notch, Vector3(-body.x * 0.5, 1.55, 0), stock(Color("24282b")))
	n_mi.rotation.x = PI * 0.5
	n_mi.rotation.y = PI * 0.5
	_g_pins(root, body)
	return root

func BoxMesh_sized(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z) * MM
	return m

func _g_pins(root: Node3D, body: Vector3) -> void:
	var tin := stock(SILVER, 0.82)
	var pin_mat := stock(Color("9aa1a5"), 0.6)
	var body_edge := body.z * 0.5
	for p: String in pin_layout_mm():
		var pos: Vector3 = pin_layout_mm()[p]
		rod(root, Vector3(pos.x, 2.5, sign(pos.z) * body_edge), Vector3(pos.x, 0.55, pos.z), 0.3, pin_mat)
		piece(root, BoxMesh_sized(0.62, 0.58, 0.42), Vector3(pos.x, 0.29, pos.z), pin_mat)
		piece(root, BoxMesh_sized(0.9, 0.08, 1.35), Vector3(pos.x, 0.04, pos.z), tin)

func _ready() -> void:
	# DIP-16: до регистрации в реестре достраиваем порты P9..P16.
	var want16 := int(params.get("pins", 8)) == 16
	if definition and int(definition.parameters.get("pins", 8)) == 16:
		want16 = true
	if want16:
		for i in range(9, 17):
			ports["P%d" % i] = "in"
	super._ready()
	var src: Variant = definition if definition and not definition.isa_path.is_empty() else params.get("isa", "")
	if src is Resource:
		_isa = IsaLoader.compile_isa(FileAccess.get_file_as_string(src.isa_path))
	elif src is String and not src.is_empty():
		var f := FileAccess.open(src, FileAccess.READ)
		_isa = IsaLoader.compile_isa(f.get_as_text()) if f else IsaLoader._bad("ISA не загрузить: " + src)

func on_event(kind: String, data: Dictionary = {}) -> void:
	super.on_event(kind, data)
	match kind:
		"flash":
			if not _isa.get("ok", false):
				state.fault = "нет ISA у чипа"
				return
			var image: Variant = data.get("bytes", [])
			_vm = IsaLoader.flash(image, _isa)
			state.halted = not _vm.get("ok", false)
			state.fault = str(_vm.get("fault", ""))
			state.pc = 0
			state.cycles = 0
			state.reg = _vm.get("regs", []).duplicate() if _vm.get("ok", false) else []
			_running = false
			wake_self()
		"start":
			if _vm.get("ok", false) and not _vm.get("halted", true):
				state.halted = false
				_running = true
				wake_self()
		"reset":
			if _vm.get("ok", false):
				_vm.regs.fill(0)
				_vm.pc = 0
				_vm.halted = false
				_vm.outputs.clear()
				_vm.inputs.clear()
				state.halted = false
				state.pc = 0
				state.cycles = 0
				state.fault = ""
				_running = true
				wake_self()

func wake_self() -> void:
	SimRegistry.wake(component_id)

func _pin_of(map_entry: Variant, index: int) -> String:
	# Вход может задавать одиночный пин или шину из массива пинов (LSB → первый).
	if map_entry is Array:
		return str(map_entry[index]) if index < map_entry.size() else ""
	return str(map_entry) if index == 0 else ""

func _read_port(map_entry: Variant) -> int:
	if map_entry is Array:
		var value := 0
		for i in map_entry.size():
			var s: Dictionary = read_pin(str(map_entry[i]))
			var bit: int = 1 if ((s.get("volts") != null and float(s.volts) > 1.65) or int(s.get("sig", 2)) == SimBus.Sig.ONE) else 0
			value |= bit << i
		return value
	var s: Dictionary = read_pin(str(map_entry))
	return 1 if ((s.get("volts") != null and float(s.volts) > 1.65) or int(s.get("sig", 2)) == SimBus.Sig.ONE) else 0

func _drive_port(map_entry: Variant, value: int) -> void:
	if map_entry is Array:
		for i in map_entry.size():
			if not ports.has(str(map_entry[i])):
				continue
			SimBus.drive(endpoint(str(map_entry[i])), SimBus.Sig.ONE if (value >> i) & 1 else SimBus.Sig.ZERO)
		return
	var pin_name := str(map_entry)
	if ports.has(pin_name):
		SimBus.drive(endpoint(pin_name), SimBus.Sig.ONE if value != 0 else SimBus.Sig.ZERO)

func _io(map: Dictionary) -> void:
	for port_str: String in map:
		if _running:
			_vm.inputs[str(int(port_str))] = _read_port(map[port_str])

func tick(_at: int) -> void:
	if not _running or not _vm.get("ok", false):
		return
	_io(_iom())
	if IsaLoader.execute(_vm, _isa, component_id):
		state.cycles += 1
		state.pc = int(_vm.pc)
		state.reg = _vm.regs.duplicate()
		state.halted = bool(_vm.halted)
		var out: Dictionary = _vm.outputs
		# Порт становится выходом только после первой OUT на него (как GPIO
		# реального кристалла): чисто входные порты не должны вести ноль.
		for port_str: String in out:
			if _iom().has(port_str):
				_drive_port(_iom()[port_str], int(out[port_str]))
		if _vm.halted:
			_running = false
			state.fault = str(_vm.fault)
	if _running:
		wake_self()

func _iom() -> Dictionary:
	if definition and not definition.io_map.is_empty():
		return definition.io_map
	return params.get("io_map", {})
