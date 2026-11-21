class_name ChipDisplaySurface
extends Node2D
## Внутренняя сцена экрана вывода (живёт внутри SubViewport).
## Рисует команды, которые выдала программа чипа, ведёт состояние ввода
## (мышь + все клавиши) и умеет показывать «нет сигнала» / ошибки.

const VIRTUAL_SIZE := Vector2i(320, 180)

## Команды последнего кадра (см. ChipVM._draw).
var commands: Array = []
var glitch := 0.0
var signal_state := "idle"   # idle | running | stopped | error | no_signal
var status_line := ""
var error_text := ""

var input_state := {
	"mouse": Vector2(160, 90),
	"down": {},
	"clicked": {},
	"released": {},
	"keys_down": {},
	"keys_pressed": {},
	"keys_released": {},
	"wheel": 0.0,
	"events": [],
}

var _font: Font
var _rng := RandomNumberGenerator.new()
var _static_accum := 0.0
var _static_lines: Array = []


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_rng.randomize()
	set_process_input(true)
	_regenerate_static()


func _process(delta: float) -> void:
	# Анимированный «снег» на экране без сигнала.
	if signal_state == "no_signal" or signal_state == "idle":
		_static_accum += delta
		if _static_accum >= 0.08:
			_static_accum = 0.0
			_regenerate_static()
			queue_redraw()


func _regenerate_static() -> void:
	_static_lines.clear()
	for i in 26:
		var y := _rng.randf_range(0.0, VIRTUAL_SIZE.y)
		var h := _rng.randf_range(0.6, 2.2)
		var alpha := _rng.randf_range(0.03, 0.16)
		_static_lines.append({"y": y, "h": h, "a": alpha})


# ---------------------------------------------------------------------------
# Кадры
# ---------------------------------------------------------------------------

func set_frame(cmds: Array, glitch_level: float, state: String, status: String = "",
		error_msg: String = "") -> void:
	commands = cmds
	glitch = clampf(glitch_level, 0.0, 1.0)
	signal_state = state
	status_line = status
	error_text = error_msg
	queue_redraw()


func clear_frame() -> void:
	commands = []
	queue_redraw()


# ---------------------------------------------------------------------------
# Ввод
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_set_mouse(_to_virtual(motion.position))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_set_mouse(_to_virtual(mb.position))
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var delta_wheel := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				input_state["wheel"] = float(input_state.get("wheel", 0.0)) + delta_wheel
				_push_event({"k": "wheel", "delta": delta_wheel})
			return
		var btn := int(mb.button_index)
		var down: Dictionary = input_state["down"]
		if mb.pressed:
			down[btn] = true
			(input_state["clicked"] as Dictionary)[btn] = true
			_push_event({"k": "mouse_down", "x": input_state["mouse"].x,
				"y": input_state["mouse"].y, "button": btn})
		else:
			down.erase(btn)
			(input_state["released"] as Dictionary)[btn] = true
			_push_event({"k": "mouse_up", "x": input_state["mouse"].x,
				"y": input_state["mouse"].y, "button": btn})
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.echo:
			return
		var key_name := KeyMap.from_event(key)
		if key_name == "":
			return
		var keys_down: Dictionary = input_state["keys_down"]
		if key.pressed:
			keys_down[key_name] = true
			(input_state["keys_pressed"] as Dictionary)[key_name] = true
			_push_event({"k": "key_down", "key": key_name})
		else:
			keys_down.erase(key_name)
			(input_state["keys_released"] as Dictionary)[key_name] = true
			_push_event({"k": "key_up", "key": key_name})


func _set_mouse(pos: Vector2) -> void:
	var old: Vector2 = input_state["mouse"]
	input_state["mouse"] = pos
	if pos.distance_to(old) > 0.01:
		_push_event({"k": "mouse_move", "x": pos.x, "y": pos.y})


func _push_event(ev: Dictionary) -> void:
	var events: Array = input_state["events"]
	if events.size() < 512:
		events.append(ev)


func _to_virtual(pos: Vector2) -> Vector2:
	var vp := get_viewport()
	var size := Vector2(vp.size)
	if size.x <= 0.0:
		return pos
	var k := size.x / float(VIRTUAL_SIZE.x)
	if k <= 0.0:
		return pos
	var v := pos / k
	return Vector2(clampf(v.x, 0.0, float(VIRTUAL_SIZE.x)), clampf(v.y, 0.0, float(VIRTUAL_SIZE.y)))


## Снимок ввода для одного тика программы.
func take_input_snapshot() -> Dictionary:
	var snap := input_state.duplicate()
	snap["events"] = (input_state["events"] as Array).duplicate()
	return snap


## Вызывается после тика: одиночные события и «нажатия в этом кадре» сбрасываются.
func end_tick() -> void:
	(input_state["events"] as Array).clear()
	(input_state["clicked"] as Dictionary).clear()
	(input_state["released"] as Dictionary).clear()
	(input_state["keys_pressed"] as Dictionary).clear()
	(input_state["keys_released"] as Dictionary).clear()
	input_state["wheel"] = 0.0


func reset_input() -> void:
	(input_state["down"] as Dictionary).clear()
	(input_state["clicked"] as Dictionary).clear()
	(input_state["released"] as Dictionary).clear()
	(input_state["keys_down"] as Dictionary).clear()
	(input_state["keys_pressed"] as Dictionary).clear()
	(input_state["keys_released"] as Dictionary).clear()
	(input_state["events"] as Array).clear()
	input_state["wheel"] = 0.0


func mouse_virtual_position() -> Vector2:
	return input_state["mouse"]


# ---------------------------------------------------------------------------
# Отрисовка
# ---------------------------------------------------------------------------

func _draw() -> void:
	var vp_size := Vector2(get_viewport().size)
	var scale_factor := vp_size.x / float(VIRTUAL_SIZE.x)
	if scale_factor <= 0.0:
		scale_factor = 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale_factor, scale_factor))
	draw_rect(Rect2(Vector2.ZERO, Vector2(VIRTUAL_SIZE)), Color("#05080a"))

	if signal_state == "no_signal":
		_draw_no_signal()
		return
	if signal_state == "idle":
		_draw_idle()
		return

	for cmd in commands:
		_draw_command(cmd)

	if glitch > 0.02:
		_draw_glitch()

	if signal_state == "stopped":
		draw_rect(Rect2(Vector2.ZERO, Vector2(VIRTUAL_SIZE)), Color(0.02, 0.04, 0.05, 0.55))
		_centered_text("ОСТАНОВЛЕНО", 88.0, 16, Color("#8a9aa0"))
		if status_line != "":
			_centered_text(status_line, 104.0, 9, Color("#5b6b72"))
	elif signal_state == "error":
		draw_rect(Rect2(Vector2.ZERO, Vector2(VIRTUAL_SIZE)), Color(0.08, 0.01, 0.02, 0.78))
		_centered_text("ПРОГРАММА УПАЛА", 38.0, 15, Color("#ff5c6c"))
		_draw_wrapped(error_text, 22.0, 58.0, 276.0, 9, Color("#ffb3ba"))
		_centered_text("Исправьте код и нажмите RUN", 158.0, 9, Color("#b06a72"))
	elif signal_state == "running" and status_line != "":
		draw_string(_font, Vector2(6, 12), status_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(0.4, 0.9, 0.65, 0.55))


func _draw_no_signal() -> void:
	for line in _static_lines:
		draw_rect(Rect2(0, line["y"], VIRTUAL_SIZE.x, line["h"]),
			Color(0.5, 0.7, 0.7, line["a"]))
	# Цветные помехи.
	for i in 3:
		var y := _rng.randf_range(0.0, VIRTUAL_SIZE.y - 6.0)
		draw_rect(Rect2(0, y, VIRTUAL_SIZE.x, _rng.randf_range(1.0, 4.0)),
			Color(0.2, 0.8, 0.7, 0.06))
	_centered_text("НЕТ СИГНАЛА", 76.0, 16, Color("#39ff88"))
	_centered_text("Display Out не подключён к видео-выходу ядра", 96.0, 8, Color("#6f8c85"))
	_centered_text("соберите питание, шину и видео — затем RUN", 110.0, 8, Color("#4e6a63"))
	draw_rect(Rect2(0, 130, VIRTUAL_SIZE.x, 1), Color(0.2, 0.9, 0.6, 0.12))


func _draw_idle() -> void:
	for line in _static_lines:
		draw_rect(Rect2(0, line["y"], VIRTUAL_SIZE.x, line["h"]),
			Color(0.4, 0.8, 0.7, line["a"] * 0.5))
	_centered_text("CHIP ARCHITECT", 66.0, 18, Color("#39ff88"))
	_centered_text("соберите чип и нажмите RUN", 92.0, 9, Color("#6f8c85"))
	draw_line(Vector2(60, 106), Vector2(VIRTUAL_SIZE.x - 60, 106), Color(0.2, 0.9, 0.6, 0.25), 1.0)
	_centered_text("мышь и клавиатура работают прямо на экране", 124.0, 8, Color("#4e6a63"))


func _draw_command(cmd: Dictionary) -> void:
	match String(cmd.get("t", "")):
		"clear":
			draw_rect(Rect2(Vector2.ZERO, Vector2(VIRTUAL_SIZE)), cmd["c"])
		"rect":
			var r := Rect2(cmd["x"], cmd["y"], cmd["w"], cmd["h"])
			if bool(cmd.get("outline", false)):
				draw_rect(r, cmd["c"], false, maxf(1.0, float(cmd.get("lw", 1.0))))
			else:
				draw_rect(r, cmd["c"])
		"line":
			draw_line(Vector2(cmd["x1"], cmd["y1"]), Vector2(cmd["x2"], cmd["y2"]),
				cmd["c"], maxf(1.0, float(cmd.get("lw", 1.0))), true)
		"circle":
			var center := Vector2(cmd["x"], cmd["y"])
			var radius: float = cmd["r"]
			if bool(cmd.get("filled", true)):
				draw_circle(center, radius, cmd["c"])
			else:
				draw_arc(center, radius, 0.0, TAU, 48, cmd["c"],
					maxf(1.0, float(cmd.get("lw", 1.0))), true)
		"tri":
			draw_colored_polygon(PackedVector2Array([
				Vector2(cmd["x1"], cmd["y1"]),
				Vector2(cmd["x2"], cmd["y2"]),
				Vector2(cmd["x3"], cmd["y3"]),
			]), cmd["c"])
		"text":
			var size := int(cmd.get("size", 10))
			var pos := Vector2(cmd["x"], cmd["y"] + size * 0.85)
			draw_string(_font, pos + Vector2(1, 1), String(cmd["s"]), HORIZONTAL_ALIGNMENT_LEFT,
				-1, size, Color(0, 0, 0, 0.45))
			draw_string(_font, pos, String(cmd["s"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				cmd["c"])


func _draw_glitch() -> void:
	var strength := glitch
	var bands := int(1.0 + strength * 7.0)
	for i in bands:
		var y := _rng.randf_range(0.0, VIRTUAL_SIZE.y)
		var h := _rng.randf_range(1.0, 3.0 + strength * 6.0)
		draw_rect(Rect2(0, y, VIRTUAL_SIZE.x, h), Color(0.05, 0.1, 0.09, 0.25 + strength * 0.3))
	# Сдвинутые цветные полосы (псевдо-RGB-развал).
	for i in 2:
		var y2 := _rng.randf_range(0.0, VIRTUAL_SIZE.y - 4.0)
		var w := _rng.randf_range(20.0, VIRTUAL_SIZE.x)
		var x := _rng.randf_range(0.0, VIRTUAL_SIZE.x - w)
		draw_rect(Rect2(x, y2, w, _rng.randf_range(1.0, 3.0)),
			Color(1.0, 0.2, 0.4, 0.12 * strength))
		draw_rect(Rect2(x, y2 + 2.0, w, _rng.randf_range(1.0, 2.0)),
			Color(0.2, 0.9, 1.0, 0.12 * strength))
	# Шум.
	var dots := int(strength * 220.0)
	for i in dots:
		var p := Vector2(_rng.randf_range(0.0, VIRTUAL_SIZE.x), _rng.randf_range(0.0, VIRTUAL_SIZE.y))
		draw_rect(Rect2(p, Vector2(1, 1)), Color(0.8, 1.0, 0.9, 0.25))


func _centered_text(text: String, y: float, size: int, color: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := (VIRTUAL_SIZE.x - width) * 0.5
	draw_string(_font, Vector2(x + 1, y + size * 0.85 + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		size, Color(0, 0, 0, 0.5))
	draw_string(_font, Vector2(x, y + size * 0.85), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_wrapped(text: String, x: float, y: float, max_width: float, size: int,
		color: Color) -> void:
	var words := text.split(" ")
	var line := ""
	var line_y := y
	for word in words:
		var test := word if line == "" else line + " " + word
		if _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width and line != "":
			draw_string(_font, Vector2(x, line_y + size), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				color)
			line = word
			line_y += size + 3.0
		else:
			line = test
	if line != "":
		draw_string(_font, Vector2(x, line_y + size), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			color)
