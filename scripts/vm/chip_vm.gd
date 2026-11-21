class_name ChipVM
extends RefCounted
## Песочница ChipScript: дерево-ходильный интерпретатор.
## Никакого доступа к Godot API/DOS — только безопасные встроенные функции,
## лимит шагов, глубины рекурсии и размера массивов.

const SCREEN_SIZE := Vector2i(320, 180)
const MAX_DEPTH := 24
const MAX_ARRAY := 4096
const MAX_STRING := 8192
const MAX_DRAW := 3000
const MAX_CONSOLE_LINES := 120

const OK := 0
const BREAK := 1
const CONTINUE := 2
const RETURN := 3

var program: ChipProgram = null
var globals := {}
var frames: Array = []
var draw_commands: Array = []
var console_lines: Array[String] = []

var error := ""
var error_line := 0
var halted := false
var budget_exceeded := false
var draw_overflow := false

var steps := 0
var step_budget := 4000
var tick_index := 0
var time := 0.0
var dt := 0.0

var input := {}
var ret_value = null
var rng := RandomNumberGenerator.new()

var _aborted := false
var _stopped_gracefully := false
var _depth := 0


func _init() -> void:
	rng.randomize()


# ---------------------------------------------------------------------------
# Запуск и тики
# ---------------------------------------------------------------------------

func set_program(prog: ChipProgram) -> void:
	program = prog
	reset()


func reset() -> void:
	globals.clear()
	frames.clear()
	draw_commands.clear()
	error = ""
	error_line = 0
	halted = false
	budget_exceeded = false
	draw_overflow = false
	_stopped_gracefully = false
	_aborted = false
	_depth = 0
	steps = 0
	tick_index = 0
	time = 0.0
	ret_value = null
	input = {}


## Выполняет глобальные объявления и вызывает start().
func start() -> bool:
	reset()
	if program == null or not program.is_valid():
		error = "Программа не скомпилирована"
		error_line = 0
		halted = true
		return false
	step_budget = maxi(step_budget, 20000)
	_exec_block(program.globals)
	if halted or _aborted:
		_finish_error()
		return false
	if has_function("start"):
		_call_user_function("start", [])
		if halted or _aborted:
			_finish_error()
			return false
	return true


func has_function(fn_name: String) -> bool:
	return program != null and program.functions.has(fn_name)


## Один тик программы. input_state — см. DisplaySurface.get_input_state().
func tick(delta: float, input_state: Dictionary) -> void:
	if program == null or halted:
		return
	dt = delta
	time += delta
	tick_index += 1
	input = input_state
	steps = 0
	budget_exceeded = false
	draw_overflow = false
	_aborted = false
	draw_commands.clear()

	_dispatch_input_events(input_state.get("events", []))

	if not halted and not _aborted:
		_call_optional("update", [delta])
	if not halted and not _aborted and has_function("draw"):
		_call_optional("draw", [])
	if halted:
		_finish_error()


func _finish_error() -> void:
	if _stopped_gracefully or error == "":
		return
	console("Ошибка (строка %d): %s" % [error_line, error])
	halted = true


func _dispatch_input_events(events: Array) -> void:
	for ev in events:
		if halted or _aborted:
			return
		var kind := String(ev.get("k", ""))
		match kind:
			"mouse_down":
				_call_optional("on_mouse_down", [float(ev.get("x", 0.0)), float(ev.get("y", 0.0)),
					float(ev.get("button", 0))])
			"mouse_up":
				_call_optional("on_mouse_up", [float(ev.get("x", 0.0)), float(ev.get("y", 0.0)),
					float(ev.get("button", 0))])
			"mouse_move":
				_call_optional("on_mouse_move", [float(ev.get("x", 0.0)), float(ev.get("y", 0.0))])
			"key_down":
				_call_optional("on_key_down", [String(ev.get("key", ""))])
			"key_up":
				_call_optional("on_key_up", [String(ev.get("key", ""))])
			"wheel":
				_call_optional("on_wheel", [float(ev.get("delta", 0.0))])


func _call_optional(fn_name: String, args: Array) -> void:
	if not has_function(fn_name):
		return
	_call_user_function(fn_name, args)


func _call_user_function(fn_name: String, args: Array):
	if program == null or not program.functions.has(fn_name):
		_runtime_error("Неизвестная функция '%s'" % fn_name, 0)
		return null
	if _depth >= MAX_DEPTH:
		_runtime_error("Слишком глубокая рекурсия (максимум %d)" % MAX_DEPTH, 0)
		return null
	var fn: Dictionary = program.functions[fn_name]
	var frame := {}
	var params: Array = fn.get("params", [])
	for i in params.size():
		frame[String(params[i])] = args[i] if i < args.size() else null
	var saved_ret = ret_value
	ret_value = null
	_depth += 1
	frames.append(frame)
	var code := _exec_block(fn["body"])
	var result = ret_value if code == RETURN else null
	frames.pop_back()
	_depth -= 1
	ret_value = saved_ret
	return result


func _exec_block(stmts: Array) -> int:
	for stmt in stmts:
		if halted or _aborted:
			return OK
		var code := _exec_stmt(stmt)
		if code != OK:
			return code
	return OK


# ---------------------------------------------------------------------------
# Операторы
# ---------------------------------------------------------------------------

func _exec_stmt(st: Dictionary) -> int:
	if not _charge():
		return OK
	var line := int(st.get("line", 0))
	match String(st.get("t", "")):
		"var":
			var value = _eval(st["expr"])
			if halted or _aborted:
				return OK
			_define(String(st["name"]), value)
			return OK
		"assign":
			var rhs = _eval(st["expr"])
			if halted or _aborted:
				return OK
			var target: Dictionary = st["target"]
			var op := String(st["op"])
			if op != "=":
				var current = _read_target(target)
				if halted or _aborted:
					return OK
				var binop := op.substr(0, 1)
				rhs = _binary(binop, current, rhs, line)
				if halted or _aborted:
					return OK
			_write_target(target, rhs)
			return OK
		"if":
			var cond = _eval(st["cond"])
			if halted or _aborted:
				return OK
			if _truthy(cond):
				return _exec_block(st["then"])
			elif st["else"] != null:
				return _exec_block(st["else"])
			return OK
		"while":
			return _exec_while(st)
		"for":
			return _exec_for(st)
		"return":
			ret_value = _eval(st["expr"]) if st["expr"] != null else null
			return RETURN
		"break":
			return BREAK
		"continue":
			return CONTINUE
		"block":
			return _exec_block(st["body"])
		"expr":
			_eval(st["expr"])
			return OK
	return OK


func _exec_while(st: Dictionary) -> int:
	while true:
		if halted or _aborted:
			return OK
		if not _charge():
			return OK
		var cond = _eval(st["cond"])
		if halted or _aborted:
			return OK
		if not _truthy(cond):
			return OK
		var code := _exec_block(st["body"])
		if halted or _aborted:
			return OK
		if code == BREAK:
			return OK
		if code == RETURN:
			return RETURN
	return OK


func _exec_for(st: Dictionary) -> int:
	var iterable = _eval(st["iter"])
	if halted or _aborted:
		return OK
	var items: Array = []
	if typeof(iterable) == TYPE_ARRAY:
		items = iterable
	elif typeof(iterable) == TYPE_STRING:
		for i in String(iterable).length():
			items.append(String(iterable)[i])
	else:
		_runtime_error("for работает только с массивами и строками", int(st.get("line", 0)))
		return OK
	var name := String(st["name"])
	for item in items:
		if halted or _aborted:
			return OK
		_define(name, item)
		var code := _exec_block(st["body"])
		if halted or _aborted:
			return OK
		if code == BREAK:
			return OK
		if code == RETURN:
			return RETURN
	return OK


# ---------------------------------------------------------------------------
# Выражения
# ---------------------------------------------------------------------------

func _eval(e) -> Variant:
	if not _charge():
		return null
	if typeof(e) != TYPE_DICTIONARY:
		return null
	match String(e.get("t", "")):
		"num":
			return float(e["v"])
		"str":
			return String(e["v"])
		"bool":
			return bool(e["v"])
		"null":
			return null
		"var":
			return _lookup(String(e["name"]), int(e.get("line", 0)))
		"array":
			var arr: Array = []
			for item in e["items"]:
				if halted or _aborted:
					return arr
				if arr.size() >= MAX_ARRAY:
					_runtime_error("Слишком большой массив (лимит %d)" % MAX_ARRAY, int(e.get("line", 0)))
					return arr
				arr.append(_eval(item))
			return arr
		"un":
			var value = _eval(e["e"])
			if halted or _aborted:
				return null
			match String(e["op"]):
				"-":
					if typeof(value) == TYPE_STRING:
						_runtime_error("Нельзя взять минус от строки", int(e.get("line", 0)))
						return null
					return -float(value)
				"!", "not":
					return not _truthy(value)
			return null
		"bin":
			if String(e["op"]) == "and":
				var left = _eval(e["l"])
				if halted or _aborted:
					return false
				if not _truthy(left):
					return false
				return _truthy(_eval(e["r"]))
			if String(e["op"]) == "or":
				var left2 = _eval(e["l"])
				if halted or _aborted:
					return false
				if _truthy(left2):
					return true
				return _truthy(_eval(e["r"]))
			var a = _eval(e["l"])
			if halted or _aborted:
				return null
			var b = _eval(e["r"])
			if halted or _aborted:
				return null
			return _binary(String(e["op"]), a, b, int(e.get("line", 0)))
		"call":
			var args: Array = []
			for arg in e["args"]:
				if halted or _aborted:
					return null
				args.append(_eval(arg))
			if halted or _aborted:
				return null
			return _call(String(e["name"]), args, int(e.get("line", 0)))
		"index":
			var obj = _eval(e["obj"])
			if halted or _aborted:
				return null
			var idx = _eval(e["index"])
			if halted or _aborted:
				return null
			return _index_get(obj, idx, int(e.get("line", 0)))
	return null


func _binary(op: String, a, b, line: int):
	match op:
		"+":
			if typeof(a) == TYPE_STRING or typeof(b) == TYPE_STRING:
				return _to_str(a) + _to_str(b)
			if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
				var out: Array = (a as Array).duplicate()
				for item in b:
					if out.size() < MAX_ARRAY:
						out.append(item)
				return out
			return _num(a, line) + _num(b, line)
		"-":
			return _num(a, line) - _num(b, line)
		"*":
			return _num(a, line) * _num(b, line)
		"/":
			var divisor := _num(b, line)
			if is_zero_approx(divisor):
				_runtime_error("Деление на ноль", line)
				return 0.0
			return _num(a, line) / divisor
		"%":
			var divisor2 := _num(b, line)
			if is_zero_approx(divisor2):
				_runtime_error("Остаток от деления на ноль", line)
				return 0.0
			return fmod(_num(a, line), divisor2)
		"==":
			return _values_equal(a, b)
		"!=":
			return not _values_equal(a, b)
		"<":
			return _compare(a, b, line) < 0
		"<=":
			return _compare(a, b, line) <= 0
		">":
			return _compare(a, b, line) > 0
		">=":
			return _compare(a, b, line) >= 0
	return null


func _compare(a, b, line: int) -> int:
	if typeof(a) == TYPE_STRING and typeof(b) == TYPE_STRING:
		return String(a).naturalnocasecmp_to(String(b))
	var na := _num(a, line)
	var nb := _num(b, line)
	if halted:
		return 0
	if na < nb:
		return -1
	if na > nb:
		return 1
	return 0


func _call(fn_name: String, args: Array, line: int):
	if _is_builtin(fn_name):
		return _call_builtin(fn_name, args, line)
	if has_function(fn_name):
		return _call_user_function(fn_name, args)
	_runtime_error("Неизвестная функция '%s'" % fn_name, line)
	return null


# ---------------------------------------------------------------------------
# Переменные
# ---------------------------------------------------------------------------

func _lookup(name: String, line: int):
	if not frames.is_empty():
		var top: Dictionary = frames[frames.size() - 1]
		if top.has(name):
			return top[name]
	if globals.has(name):
		return globals[name]
	_runtime_error("Переменная '%s' не объявлена" % name, line)
	return null


func _define(name: String, value) -> void:
	if frames.is_empty():
		globals[name] = value
	else:
		frames[frames.size() - 1][name] = value


func _read_target(target: Dictionary):
	if String(target["t"]) == "var":
		return _lookup(String(target["name"]), int(target.get("line", 0)))
	var obj = _eval(target["obj"])
	if halted or _aborted:
		return null
	var idx = _eval(target["index"])
	if halted or _aborted:
		return null
	return _index_get(obj, idx, int(target.get("line", 0)))


func _write_target(target: Dictionary, value) -> void:
	if String(target["t"]) == "var":
		var name := String(target["name"])
		if not frames.is_empty() and frames[frames.size() - 1].has(name):
			frames[frames.size() - 1][name] = value
		elif globals.has(name):
			globals[name] = value
		else:
			_define(name, value)
		return
	var obj = _eval(target["obj"])
	if halted or _aborted:
		return
	var idx = _eval(target["index"])
	if halted or _aborted:
		return
	if typeof(obj) == TYPE_ARRAY:
		var i := int(float(idx))
		if i < 0:
			i += (obj as Array).size()
		if i < 0 or i >= (obj as Array).size():
			_runtime_error("Индекс %d вне массива (размер %d)" % [int(float(idx)), (obj as Array).size()],
				int(target.get("line", 0)))
			return
		(obj as Array)[i] = value
		return
	_runtime_error("Присваивание по индексу возможно только для массива", int(target.get("line", 0)))


func _index_get(obj, idx, line: int):
	if typeof(obj) == TYPE_ARRAY:
		var arr: Array = obj
		var i := int(float(idx))
		if i < 0:
			i += arr.size()
		if i < 0 or i >= arr.size():
			_runtime_error("Индекс %d вне массива (размер %d)" % [int(float(idx)), arr.size()], line)
			return null
		return arr[i]
	if typeof(obj) == TYPE_STRING:
		var s := String(obj)
		var j := int(float(idx))
		if j < 0:
			j += s.length()
		if j < 0 or j >= s.length():
			_runtime_error("Индекс %d вне строки" % int(float(idx)), line)
			return null
		return s[j]
	_runtime_error("Индексы работают только с массивами и строками", line)
	return null


# ---------------------------------------------------------------------------
# Встроенные функции
# ---------------------------------------------------------------------------

const BUILTINS := [
	"clear", "fill_rect", "rect", "line", "fill_circle", "circle", "pixel", "text", "triangle",
	"mouse_x", "mouse_y", "mouse_down", "mouse_clicked", "mouse_released",
	"key_down", "key_pressed", "key_released", "wheel",
	"dt", "time", "tick", "width", "height",
	"abs", "min", "max", "floor", "ceil", "round", "sqrt", "sin", "cos", "tan", "atan2",
	"pow", "clamp", "lerp", "sign", "rand", "random", "dist", "pi",
	"str", "num", "len", "push", "pop", "range", "lower", "upper", "substr", "has",
	"print", "halt",
]


func _is_builtin(name: String) -> bool:
	return name in BUILTINS


func _call_builtin(name: String, args: Array, line: int):
	match name:
		# --- рисование ---
		"clear":
			_draw({"t": "clear", "c": _to_color(_arg(args, 0, "#05080a"))})
			return null
		"fill_rect":
			if not _need(args, 5, name, line):
				return null
			_draw({"t": "rect", "x": _num(args[0], line), "y": _num(args[1], line),
				"w": _num(args[2], line), "h": _num(args[3], line), "c": _to_color(args[4])})
			return null
		"rect":
			if not _need(args, 5, name, line):
				return null
			_draw({"t": "rect", "x": _num(args[0], line), "y": _num(args[1], line),
				"w": _num(args[2], line), "h": _num(args[3], line), "c": _to_color(args[4]),
				"outline": true, "lw": _num_opt(args, 5, 1.0, line)})
			return null
		"line":
			if not _need(args, 5, name, line):
				return null
			_draw({"t": "line", "x1": _num(args[0], line), "y1": _num(args[1], line),
				"x2": _num(args[2], line), "y2": _num(args[3], line), "c": _to_color(args[4]),
				"lw": _num_opt(args, 5, 1.0, line)})
			return null
		"fill_circle":
			if not _need(args, 4, name, line):
				return null
			_draw({"t": "circle", "x": _num(args[0], line), "y": _num(args[1], line),
				"r": maxf(0.0, _num(args[2], line)), "c": _to_color(args[3]), "filled": true})
			return null
		"circle":
			if not _need(args, 4, name, line):
				return null
			_draw({"t": "circle", "x": _num(args[0], line), "y": _num(args[1], line),
				"r": maxf(0.0, _num(args[2], line)), "c": _to_color(args[3]), "filled": false,
				"lw": _num_opt(args, 4, 1.0, line)})
			return null
		"pixel":
			if not _need(args, 3, name, line):
				return null
			_draw({"t": "rect", "x": _num(args[0], line), "y": _num(args[1], line),
				"w": 1.0, "h": 1.0, "c": _to_color(args[2])})
			return null
		"triangle":
			if not _need(args, 7, name, line):
				return null
			_draw({"t": "tri",
				"x1": _num(args[0], line), "y1": _num(args[1], line),
				"x2": _num(args[2], line), "y2": _num(args[3], line),
				"x3": _num(args[4], line), "y3": _num(args[5], line),
				"c": _to_color(args[6])})
			return null
		"text":
			if not _need(args, 4, name, line):
				return null
			var s := _to_str(args[2])
			if s.length() > 512:
				s = s.substr(0, 512)
			_draw({"t": "text", "x": _num(args[0], line), "y": _num(args[1], line),
				"s": s, "c": _to_color(args[3]), "size": clampf(_num_opt(args, 4, 10.0, line), 6.0, 48.0)})
			return null

		# --- ввод ---
		"mouse_x":
			return float((input.get("mouse", Vector2.ZERO) as Vector2).x)
		"mouse_y":
			return float((input.get("mouse", Vector2.ZERO) as Vector2).y)
		"mouse_down":
			return _button_state("down", int(_num(_arg(args, 0, 0.0), line)))
		"mouse_clicked":
			return _button_state("clicked", int(_num(_arg(args, 0, 0.0), line)))
		"mouse_released":
			return _button_state("released", int(_num(_arg(args, 0, 0.0), line)))
		"key_down":
			var keys: Dictionary = input.get("keys_down", {})
			return keys.has(KeyMap.normalize(_to_str(_arg(args, 0, ""))))
		"key_pressed":
			var kp: Dictionary = input.get("keys_pressed", {})
			return kp.has(KeyMap.normalize(_to_str(_arg(args, 0, ""))))
		"key_released":
			var kr: Dictionary = input.get("keys_released", {})
			return kr.has(KeyMap.normalize(_to_str(_arg(args, 0, ""))))
		"wheel":
			return float(input.get("wheel", 0.0))

		# --- время и экран ---
		"dt":
			return dt
		"time":
			return time
		"tick":
			return float(tick_index)
		"width":
			return float(SCREEN_SIZE.x)
		"height":
			return float(SCREEN_SIZE.y)

		# --- математика ---
		"abs":
			return absf(_num(_arg(args, 0, 0.0), line))
		"min":
			if args.is_empty():
				return 0.0
			var mn := _num(args[0], line)
			for i in range(1, args.size()):
				mn = minf(mn, _num(args[i], line))
			return mn
		"max":
			if args.is_empty():
				return 0.0
			var mx := _num(args[0], line)
			for i in range(1, args.size()):
				mx = maxf(mx, _num(args[i], line))
			return mx
		"floor":
			return floorf(_num(_arg(args, 0, 0.0), line))
		"ceil":
			return ceilf(_num(_arg(args, 0, 0.0), line))
		"round":
			return roundf(_num(_arg(args, 0, 0.0), line))
		"sqrt":
			return sqrt(maxf(0.0, _num(_arg(args, 0, 0.0), line)))
		"sin":
			return sin(_num(_arg(args, 0, 0.0), line))
		"cos":
			return cos(_num(_arg(args, 0, 0.0), line))
		"tan":
			return tan(_num(_arg(args, 0, 0.0), line))
		"atan2":
			return atan2(_num(_arg(args, 0, 0.0), line), _num(_arg(args, 1, 0.0), line))
		"pow":
			return pow(_num(_arg(args, 0, 0.0), line), _num(_arg(args, 1, 0.0), line))
		"clamp":
			return clampf(_num(_arg(args, 0, 0.0), line), _num(_arg(args, 1, 0.0), line),
				_num(_arg(args, 2, 1.0), line))
		"lerp":
			return lerpf(_num(_arg(args, 0, 0.0), line), _num(_arg(args, 1, 0.0), line),
				_num(_arg(args, 2, 0.0), line))
		"sign":
			return signf(_num(_arg(args, 0, 0.0), line))
		"rand":
			return rng.randf_range(_num(_arg(args, 0, 0.0), line), _num(_arg(args, 1, 1.0), line))
		"random":
			return rng.randf()
		"dist":
			return Vector2(_num(_arg(args, 0, 0.0), line), _num(_arg(args, 1, 0.0), line)).distance_to(
				Vector2(_num(_arg(args, 2, 0.0), line), _num(_arg(args, 3, 0.0), line)))
		"pi":
			return PI

		# --- строки и массивы ---
		"str":
			return _to_str(_arg(args, 0, ""))
		"num":
			return _num(_arg(args, 0, 0.0), line)
		"len":
			var v = _arg(args, 0, "")
			if typeof(v) == TYPE_ARRAY:
				return float((v as Array).size())
			return float(_to_str(v).length())
		"push":
			if not _need(args, 2, name, line):
				return null
			var arr = _arg(args, 0, null)
			if typeof(arr) != TYPE_ARRAY:
				_runtime_error("push(массив, значение) ожидает массив", line)
				return null
			if (arr as Array).size() >= MAX_ARRAY:
				_runtime_error("Массив переполнен (лимит %d)" % MAX_ARRAY, line)
				return null
			(arr as Array).append(args[1])
			return float((arr as Array).size())
		"pop":
			var arr2 = _arg(args, 0, null)
			if typeof(arr2) != TYPE_ARRAY:
				_runtime_error("pop(массив) ожидает массив", line)
				return null
			if (arr2 as Array).is_empty():
				return null
			return (arr2 as Array).pop_back()
		"range":
			var from := _num(_arg(args, 0, 0.0), line)
			var to := _num(_arg(args, 1, 0.0), line)
			var step := _num_opt(args, 2, 1.0, line)
			if is_zero_approx(step):
				step = 1.0
			var out_arr: Array = []
			var i := from
			var guard := 0
			while (step > 0.0 and i < to) or (step < 0.0 and i > to):
				if out_arr.size() >= MAX_ARRAY or guard > MAX_ARRAY:
					break
				out_arr.append(i)
				i += step
				guard += 1
			return out_arr
		"lower":
			return _to_str(_arg(args, 0, "")).to_lower()
		"upper":
			return _to_str(_arg(args, 0, "")).to_upper()
		"substr":
			var s2 := _to_str(_arg(args, 0, ""))
			var start := int(_num(_arg(args, 1, 0.0), line))
			var count := int(_num_opt(args, 2, float(s2.length()), line))
			return s2.substr(clampi(start, 0, s2.length()), maxi(count, 0))
		"has":
			var hay = _arg(args, 0, null)
			var needle = _arg(args, 1, null)
			if typeof(hay) == TYPE_ARRAY:
				return (hay as Array).has(needle)
			return _to_str(hay).find(_to_str(needle)) != -1

		# --- служебное ---
		"print":
			var parts := PackedStringArray()
			for a in args:
				parts.append(_to_str(a))
			console(" ".join(parts))
			return null
		"halt":
			_stopped_gracefully = true
			halted = true
			console("Программа остановлена (halt)")
			return null

	return null


## Запись в консоль IDE (с ограничением размера).
func console(text: String) -> void:
	var line := text
	if line.length() > MAX_STRING:
		line = line.substr(0, MAX_STRING)
	console_lines.append(line)
	while console_lines.size() > MAX_CONSOLE_LINES:
		console_lines.pop_front()


# ---------------------------------------------------------------------------
# Помощники
# ---------------------------------------------------------------------------

func _charge() -> bool:
	if halted:
		return false
	steps += 1
	if steps > step_budget:
		budget_exceeded = true
		_aborted = true
		return false
	return true


func _runtime_error(message: String, line: int) -> void:
	if error != "":
		return
	error = message
	error_line = line
	halted = true


func _draw(cmd: Dictionary) -> void:
	if draw_commands.size() >= MAX_DRAW:
		draw_overflow = true
		return
	draw_commands.append(cmd)


func _arg(args: Array, index: int, fallback):
	if index < 0 or index >= args.size():
		return fallback
	return args[index]


func _num(value, line: int) -> float:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return float(value)
		TYPE_BOOL:
			return 1.0 if value else 0.0
		TYPE_STRING:
			return String(value).to_float()
		TYPE_NIL:
			return 0.0
	_runtime_error("Ожидалось число, получено '%s'" % _type_name(value), line)
	return 0.0


func _num_opt(args: Array, index: int, fallback: float, line: int) -> float:
	if index < 0 or index >= args.size():
		return fallback
	return _num(args[index], line)


func _need(args: Array, count: int, fn_name: String, line: int) -> bool:
	if args.size() < count:
		_runtime_error("Функция %s ожидает минимум %d аргументов (передано %d)" % [
			fn_name, count, args.size()], line)
		return false
	return true


func _button_state(which: String, button: int) -> bool:
	var d: Dictionary = input.get(which, {})
	return d.has(button) and bool(d[button])


func _truthy(v) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return bool(v)
		TYPE_INT, TYPE_FLOAT:
			return not is_zero_approx(float(v))
		TYPE_STRING:
			return String(v) != ""
		TYPE_ARRAY:
			return not (v as Array).is_empty()
	return true


func _values_equal(a, b) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	var num_a := ta == TYPE_INT or ta == TYPE_FLOAT or ta == TYPE_BOOL
	var num_b := tb == TYPE_INT or tb == TYPE_FLOAT or tb == TYPE_BOOL
	if num_a and num_b:
		return is_equal_approx(_to_float(a), _to_float(b))
	if ta == TYPE_STRING and tb == TYPE_STRING:
		return String(a) == String(b)
	if ta == TYPE_NIL or tb == TYPE_NIL:
		return a == null and b == null
	return a == b


func _to_float(v) -> float:
	if typeof(v) == TYPE_BOOL:
		return 1.0 if v else 0.0
	return float(v)


func _to_str(v) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_FLOAT:
			var f := float(v)
			if is_equal_approx(f, roundf(f)) and absf(f) < 1e15:
				return str(int(f))
			return str(f)
		TYPE_INT:
			return str(int(v))
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for item in (v as Array):
				parts.append(_to_str(item))
			return "[" + ", ".join(parts) + "]"
	return str(v)


func _type_name(v) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "bool"
		TYPE_INT, TYPE_FLOAT:
			return "число"
		TYPE_STRING:
			return "строка"
		TYPE_ARRAY:
			return "массив"
	return "значение"


func _to_color(v) -> Color:
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v
		if arr.size() >= 3:
			var a := 1.0
			if arr.size() >= 4:
				a = clampf(float(arr[3]), 0.0, 1.0)
			return Color(clampf(float(arr[0]), 0.0, 1.0), clampf(float(arr[1]), 0.0, 1.0),
				clampf(float(arr[2]), 0.0, 1.0), a)
		return Color.WHITE
	var s := _to_str(v).strip_edges().to_lower()
	match s:
		"red":
			return Color("#ff4d4d")
		"green":
			return Color("#39ff88")
		"blue":
			return Color("#4db8ff")
		"yellow":
			return Color("#ffe066")
		"orange":
			return Color("#ffa64d")
		"cyan":
			return Color("#33d6e0")
		"magenta", "pink":
			return Color("#ff66cc")
		"white":
			return Color.WHITE
		"black":
			return Color.BLACK
		"gray", "grey":
			return Color("#8a9aa0")
		"transparent":
			return Color(0, 0, 0, 0)
	if s.begins_with("#"):
		var hex := s.substr(1)
		if hex.length() == 3:
			var r := hex.substr(0, 1)
			var g := hex.substr(1, 1)
			var b := hex.substr(2, 1)
			hex = r + r + g + g + b + b
		if hex.length() == 6:
			return Color8(hex.substr(0, 2).hex_to_int(), hex.substr(2, 2).hex_to_int(),
				hex.substr(4, 2).hex_to_int())
		if hex.length() == 8:
			return Color8(hex.substr(0, 2).hex_to_int(), hex.substr(2, 2).hex_to_int(),
				hex.substr(4, 2).hex_to_int(), hex.substr(6, 2).hex_to_int())
	return Color.WHITE
