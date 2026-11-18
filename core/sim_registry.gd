extends Node

signal topology_changed
signal part_removed(id: String)
var _parts: Dictionary = {}
var _wires: Array = []
var _net: Dictionary = {}
var _members: Dictionary = {}
var _dirty: Dictionary = {}

func _ready() -> void:
	SimBus.net_changed.connect(_notify_net)
	SimBus.current_changed.connect(wake)

func register(part: Node3D) -> bool:
	var id: String = part.component_id
	if not id.is_valid_identifier() or _parts.has(id) or part.ports.is_empty():
		return false
	for pin: String in part.ports:
		if not pin.is_valid_identifier():
			return false
	_parts[id] = part
	wake(id)
	_rebuild()
	return true

func unregister(part: Node3D) -> void:
	var id: String = part.component_id
	if _parts.get(id) != part:
		return
	var pins := []
	for p: String in part.ports:
		pins.append(id + "." + p)
	SimBus.forget(id, pins)
	_parts.erase(id)
	_dirty.erase(id)
	_wires = _wires.filter(func(w: Array) -> bool: return not (w[0] in pins or w[1] in pins))
	part_removed.emit(id)
	_rebuild()

# Object.connect уже занят сигналами Godot, поэтому для меди — connect_ports.
func connect_ports(a: String, b: String) -> bool:
	if a == b or not _net.has(a) or not _net.has(b):
		return false
	var wire := [a, b] if a < b else [b, a]
	if _wires.has(wire):
		return false
	_wires.append(wire)
	_rebuild()
	return true

func disconnect_ports(a: String, b: String) -> void:
	_wires.erase([a, b] if a < b else [b, a])
	_rebuild()

func has_part(id: String) -> bool:
	return _parts.has(id)

func has_pin(pin: String) -> bool:
	return _net.has(pin)

func _root(parents: Dictionary, pin: String) -> String:
	while parents[pin] != pin:
		parents[pin] = parents[parents[pin]]
		pin = parents[pin]
	return pin

func _rebuild() -> void:
	var parents := {}
	for id: String in _parts:
		for p: String in _parts[id].ports:
			parents[id + "." + p] = id + "." + p
	for w: Array in _wires:
		var a := _root(parents, w[0])
		var b := _root(parents, w[1])
		parents[b if a < b else a] = a if a < b else b
	_net.clear()
	_members.clear()
	var pins := parents.keys()
	pins.sort()
	for p: String in pins:
		var n := _root(parents, p)
		_net[p] = n
		if not _members.has(n):
			_members[n] = []
		_members[n].append(p)
	SimBus.bind_nets(_net)
	# После разрезания сети имя «левой половины» может остаться прежним.
	for id: String in _parts:
		wake(id)
	topology_changed.emit()

func wake(id: String) -> void:
	if _parts.has(id):
		_dirty[id] = true

func _notify_net(n: String, value: Dictionary) -> void:
	for p: String in _members.get(n, []):
		var id := p.get_slice(".", 0)
		_parts[id].on_signal(p.get_slice(".", 1), value.duplicate())
		wake(id)

func dispatch(id: String, kind: String, data: Dictionary) -> void:
	if _parts.has(id):
		_parts[id].on_event(kind, data)
		wake(id)

func evaluate(tick: int) -> void:
	var batch := _dirty.keys()
	_dirty.clear()
	batch.sort()
	for id: String in batch:
		if _parts.has(id):
			_parts[id].tick(tick)

func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	for n: String in _members:
		var pins: Array = _members[n]
		var reading := SimBus.sample(n)
		if reading.sig == SimBus.Sig.X:
			issues.append(("КЗ: " if reading.fault == "short" else "Конфликт: ") + n)
		var roles := []
		for p: String in pins:
			roles.append(_parts[p.get_slice(".", 0)].ports[p.get_slice(".", 1)])
		if pins.size() == 1 and roles[0] != "optional":
			issues.append("Не подключён: " + n)
		if "clock_in" in roles and not "clock_out" in roles:
			issues.append("Нет источника такта: " + n)
	return issues

func _layout() -> Dictionary:
	var layout := {}
	for id: String in _parts:
		var p: Node3D = _parts[id]
		layout[id] = JSON.stringify([p.get_script().resource_path, p.ports, p.params], "", true, true)
	return layout

func snapshot() -> Dictionary:
	var states := {}
	for id: String in _parts:
		states[id] = _parts[id].state
	return {"layout": _layout(), "states": states, "wires": _wires, "dirty": _dirty}.duplicate(true)

func accepts(s: Dictionary) -> bool:
	if s.get("layout") != _layout() or not (s.get("states") is Dictionary and s.get("wires") is Array and s.get("dirty") is Dictionary):
		return false
	if s.states.size() != _parts.size(): return false
	for id: Variant in s.dirty:
		if not _parts.has(id): return false
	for id: String in _parts:
		if not s.states.get(id) is Dictionary:
			return false
	for w: Variant in s.wires:
		if not w is Array or w.size() != 2 or not _net.has(w[0]) or not _net.has(w[1]) or w[0] == w[1]:
			return false
	return true

func restore(s: Dictionary) -> void:
	_wires = s.wires.duplicate(true)
	_rebuild()
	for id: String in _parts:
		_parts[id].state = s.states[id].duplicate(true)
		_parts[id].refresh_visual()
	_dirty = s.dirty.duplicate()
