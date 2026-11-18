extends Node

enum Sig { ZERO, ONE, Z, X }
signal net_changed(net: String, sample: Dictionary)
signal current_changed(part_id: String)

var _nets: Dictionary = {}       # Порт → каноническое имя сети.
var _drivers: Dictionary = {}    # Порт → [сигнал, напряжение ONE, выходное R].
var _pulls: Dictionary = {}
var _branches: Dictionary = {}   # Элемент → [порт A, порт B, омы, падение Vf].
var _samples: Dictionary = {}
var _ma: Dictionary = {}
var _dirty := false

func bind_nets(mapping: Dictionary) -> void:
	_nets = mapping.duplicate()
	_dirty = true

func drive(pin: String, value: int, vcc: float = 3.3, ohms: float = 25.0) -> bool:
	return _source(_drivers, pin, value, vcc, ohms)

func pull(pin: String, value: int, vcc: float = 3.3, ohms: float = 10000.0) -> bool:
	return _source(_pulls, pin, value, vcc, ohms)

func _source(table: Dictionary, pin: String, s: int, v: float, r: float) -> bool:
	if not _nets.has(pin) or s < 0 or s > Sig.X or not is_finite(v) or not is_finite(r) or v < 0 or r <= 0:
		return false
	var data := [s, v, r]
	if s == Sig.Z:
		_dirty = table.erase(pin) or _dirty
	elif table.get(pin) != data:
		table[pin] = data
		_dirty = true
	return true

# vf < 0: пассивная двунаправленная ветвь; иначе — направленная нагрузка.
func branch(id: String, a: String, b: String, r: float, vf: float = -1.0) -> void:
	var data := [a, b, maxf(0.0, r), vf]
	if _nets.has(a) and _nets.has(b) and _branches.get(id) != data:
		_branches[id] = data
		_dirty = true

func open_branch(id: String) -> void:
	_dirty = _branches.erase(id) or _dirty

func forget(id: String, pins: Array) -> void:
	for pin in pins:
		_drivers.erase(pin)
		_pulls.erase(pin)
	open_branch(id)
	_dirty = true

func _reading(s: int = Sig.Z, v: Variant = null, r: float = 0.0, fault: String = "") -> Dictionary:
	return {"sig": s, "volts": v, "ohms": r, "ma": 0.0, "fault": fault}

func sample(pin: String) -> Dictionary:
	return _samples.get(_nets.get(pin, ""), _reading()).duplicate()

func current_ma(id: String) -> float:
	return _ma.get(id, 0.0)

func _sorted(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys

func _sources(table: Dictionary, weak: bool) -> Dictionary:
	var result := {}
	var masks := {}
	for pin: String in _sorted(table):
		var n: String = _nets[pin]
		var src: Array = table[pin]
		var value := int(src[0])
		masks[n] = int(masks.get(n, 0)) | (1 << value)
		if not result.has(n):
			var volts: Variant = null if value == Sig.X else (src[1] if value == Sig.ONE else 0.0)
			result[n] = _reading(value, volts, src[2])
		elif (int(masks[n]) & 3) == 3:
			result[n] = _reading(Sig.X, null, 0, "pull_conflict" if weak else "short")
		elif not weak or (int(masks[n]) & (1 << Sig.X)) != 0:
			result[n] = _reading(Sig.X, null, 0, "contention")
	return result

# Один пакет изменений за такт. Медные сети идеальны; резисторы переносят
# уровень на плавающие сети послойно. Это цифровая модель, не делитель SPICE.
func commit(tick: int) -> void:
	if not _dirty:
		return
	_dirty = false
	var solved := _sources(_drivers, false)
	solved.merge(_sources(_pulls, true), false)
	var edges := {}
	var paths := {}
	for id: String in _sorted(_branches):
		var b: Array = _branches[id]
		if b[3] < 0:
			var a: String = _nets[b[0]]
			var z: String = _nets[b[1]]
			for pair: Array in [[a, z], [z, a]]:
				if not edges.has(pair[0]):
					edges[pair[0]] = []
				edges[pair[0]].append([pair[1], id])
	var front := _sorted(solved)
	while not front.is_empty():
		var layer := {}
		for n: String in front:
			for edge: Array in edges.get(n, []):
				var other: String = edge[0]
				if solved.has(other):
					continue
				var proposal: Dictionary = solved[n].duplicate()
				proposal.ohms += _branches[edge[1]][2]
				if layer.has(other):
					if layer[other].sig != proposal.sig:
						layer[other] = _reading(Sig.X, null, 0, "ambiguous")
						continue
					if layer[other].ohms <= proposal.ohms:
						continue
				layer[other] = proposal
				paths[other] = paths.get(n, []) + [edge[1]]
		solved.merge(layer)
		front = _sorted(layer)
	var currents := {}
	for id: String in _sorted(_branches):
		var b: Array = _branches[id]
		var a: String = _nets[b[0]]
		var z: String = _nets[b[1]]
		if not solved.has(a) or not solved.has(z) or solved[a].volts == null or solved[z].volts == null:
			continue
		var dv := float(solved[a].volts) - float(solved[z].volts)
		dv = absf(dv) if b[3] < 0 else maxf(0, dv - float(b[3]))
		if dv == 0.0:
			continue
		var ma := 1000.0 * dv / (float(solved[a].ohms) + float(b[2]) + float(solved[z].ohms))
		var visited := {}
		for via: String in paths.get(a, []) + [id] + paths.get(z, []):
			currents[via] = float(currents.get(via, 0)) + ma
			visited[_nets[_branches[via][0]]] = true
			visited[_nets[_branches[via][1]]] = true
		for n: String in visited:
			solved[n].ma += ma
	var old_samples := _samples
	var old_ma := _ma
	_samples = solved
	_ma = currents
	var changed := old_samples.duplicate()
	changed.merge(solved)
	for n: String in _sorted(changed):
		var value: Dictionary = solved.get(n, _reading())
		if value != old_samples.get(n, _reading()):
			net_changed.emit(n, value.duplicate())
			DebugHooks.on_signal_change.emit(tick, n, value.duplicate())
	var owners := old_ma.duplicate()
	owners.merge(currents)
	for id: String in _sorted(owners):
		if current_ma(id) != float(old_ma.get(id, 0)):
			current_changed.emit(id)

func snapshot() -> Dictionary:
	return {"drivers": _drivers, "pulls": _pulls, "branches": _branches,
		"samples": _samples, "ma": _ma, "dirty": _dirty}.duplicate(true)

func _number(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))

func accepts(s: Dictionary) -> bool:
	for field: String in ["drivers", "pulls", "branches", "samples", "ma"]:
		if not s.get(field) is Dictionary: return false
	if not s.get("dirty") is bool: return false
	for table: Dictionary in [s.drivers, s.pulls]:
		for pin: Variant in table:
			var d: Variant = table[pin]
			if not _nets.has(pin) or not d is Array or d.size() != 3: return false
			if not _number(d[0]) or int(d[0]) != d[0] or int(d[0]) not in [Sig.ZERO, Sig.ONE, Sig.X]: return false
			if not _number(d[1]) or d[1] < 0: return false
			if not _number(d[2]) or d[2] <= 0: return false
	for b: Variant in s.branches.values():
		if not b is Array or b.size() != 4 or not _nets.has(b[0]) or not _nets.has(b[1]): return false
		if not _number(b[2]) or b[2] < 0 or not _number(b[3]): return false
	for v: Variant in s.samples.values():
		if not v is Dictionary or not v.has_all(["sig", "volts", "ohms", "ma", "fault"]): return false
		if not _number(v.sig) or int(v.sig) != v.sig or v.sig < 0 or v.sig > Sig.X: return false
		if not _number(v.ohms) or not _number(v.ma) or not v.fault is String: return false
		if int(v.sig) in [Sig.ZERO, Sig.ONE] and not _number(v.volts): return false
	for v: Variant in s.ma.values():
		if not _number(v) or v < 0: return false
	return true

func restore(s: Dictionary) -> void:
	_drivers = s.drivers.duplicate(true)
	_pulls = s.pulls.duplicate(true)
	_branches = s.branches.duplicate(true)
	_samples = s.samples.duplicate(true)
	# JSON читает даже целые числа как float. Тип enum важен для сравнения пакетов.
	for table: Dictionary in [_drivers, _pulls]:
		for src: Array in table.values(): src[0] = int(src[0])
	for value: Dictionary in _samples.values(): value.sig = int(value.sig)
	_ma = s.ma.duplicate(true)
	_dirty = s.dirty
