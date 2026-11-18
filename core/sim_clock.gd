extends Node

@export_range(0.05, 1000.0) var tick_ms := 1.0
@export_range(0.01, 128.0) var speed := 1.0
var now := 0
var playing := false
var _credit := 0.0
var _serial := 0
var _heap: Array = []
var _stepping := false

func _ready() -> void:
	SimRegistry.part_removed.connect(_cancel)

func _process(delta: float) -> void:
	if not playing:
		return
	_credit += delta * 1000.0 * speed
	# Бюджет кадра не меняет очередь: остаток времени не теряется.
	for i in 512:
		if _credit < tick_ms or not playing:
			break
		_credit -= tick_ms
		step()

# Ключ кучи: дедлайн, затем меньший приоритет, затем порядок подачи.
func _before(a: Array, b: Array) -> bool:
	for i in 3:
		if int(a[i]) != int(b[i]):
			return int(a[i]) < int(b[i])
	return false

func _push(e: Array) -> void:
	var i := _heap.size()
	_heap.append(e)
	while i > 0:
		var parent := (i - 1) >> 1
		if not _before(e, _heap[parent]):
			break
		_heap[i] = _heap[parent]
		i = parent
	_heap[i] = e

func _pop() -> Array:
	var first: Array = _heap[0]
	var tail: Array = _heap.pop_back()
	var i := 0
	while 2 * i + 1 < _heap.size():
		var j := 2 * i + 1
		if j + 1 < _heap.size() and _before(_heap[j + 1], _heap[j]):
			j += 1
		if not _before(_heap[j], tail):
			break
		_heap[i] = _heap[j]
		i = j
	if not _heap.is_empty():
		_heap[i] = tail
	return first

func post(id: String, kind: String, data: Dictionary = {}, delay: int = 1, priority: int = 0) -> bool:
	if not SimRegistry.has_part(id): return false
	_push([now + maxi(1, delay), priority, _serial, id, kind, data.duplicate(true)])
	_serial += 1
	return true

func _cancel(id: String) -> void:
	var old := _heap
	_heap = []
	for e: Array in old:
		if e[3] != id:
			_push(e)

func step() -> void:
	if _stepping:
		return
	_stepping = true
	now += 1
	while not _heap.is_empty() and int(_heap[0][0]) <= now:
		var e := _pop()
		SimRegistry.dispatch(e[3], e[4], e[5])
	SimRegistry.evaluate(now)
	SimBus.commit(now)
	_stepping = false
	DebugHooks.on_tick.emit(now)

func run(n: int) -> void:
	for i in maxi(0, n):
		step()

# Снимок — только на границе тактов. Никаких Callable, RID и адресов нод.
func snapshot() -> Dictionary:
	if _stepping:
		return {}
	return {"version": 1, "tick": now, "serial": _serial, "queue": _heap.duplicate(true),
		"ms": tick_ms, "speed": speed, "credit": _credit, "playing": playing,
		"registry": SimRegistry.snapshot(), "bus": SimBus.snapshot()}

func _whole(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and int(v) == v

func restore(s: Dictionary) -> bool:
	if _stepping or s.get("version") != 1 or not s.has_all(["tick", "serial", "ms", "speed", "credit", "playing", "queue", "registry", "bus"]):
		return false
	if not s.registry is Dictionary or not SimRegistry.accepts(s.registry) or not s.queue is Array:
		return false
	if not s.bus is Dictionary or not SimBus.accepts(s.bus) or not s.playing is bool:
		return false
	if not _whole(s.tick) or s.tick < 0 or not _whole(s.serial) or s.serial < 0: return false
	for v: Variant in [s.ms, s.speed, s.credit]:
		if not (v is int or v is float) or not is_finite(float(v)): return false
	if s.ms <= 0 or s.speed <= 0 or s.credit < 0: return false
	var seen := {}
	for i in s.queue.size():
		var e: Variant = s.queue[i]
		if not e is Array or e.size() != 6 or not e[5] is Dictionary: return false
		if not (e[3] is String and SimRegistry.has_part(e[3]) and e[4] is String): return false
		if not _whole(e[0]) or e[0] <= s.tick or not _whole(e[1]) or not _whole(e[2]): return false
		if e[2] < 0 or e[2] >= s.serial or seen.has(int(e[2])): return false
		if i > 0 and _before(e, s.queue[(i - 1) >> 1]): return false
		seen[int(e[2])] = true
	SimRegistry.restore(s.registry)
	SimBus.restore(s.bus)
	now = int(s.tick)
	_serial = int(s.serial)
	_heap = s.queue.duplicate(true)
	tick_ms = float(s.ms)
	speed = float(s.speed)
	_credit = float(s.credit)
	playing = s.playing
	DebugHooks.timeline_reset.emit(now)
	return true
