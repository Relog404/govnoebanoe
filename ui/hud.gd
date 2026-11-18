extends CanvasLayer

# HUD: только мышь и клавиши 1..5. Собирается кодом — сцена минимальная.
const HudIcon = preload("res://ui/hud_icon.gd")
const TOOL_NAMES := ["Паяльник", "Пинцет", "Тестер", "Лупа", "Курсор"]
const TOOL_HINTS := [
	"ЛКМ: порт A → порт B, дорожка между ними. ПКМ: отмена.",
	"ЛКМ: взять / поставить. ПКМ: снять деталь (упадёт на стол).",
	"Наведи на порт или дорожку: 0 / 1 / Z / X, вольты, миллиамперы.",
	"Колесо: ×1 ×2 ×4 ×8 вокруг курсора. ЛКМ: зафиксировать. ПКМ: сброс. Плату не редактирует.",
	"ЛКМ: выбрать и осмотреть. ПКМ: снять связи с контакта.",
]
var _tool_buttons: Array[Button] = []
var _tool_label: Label
var _hint: Label
var _zoom_label: Label
var _time_label: Label
var _play_button: Button
var _toast: Label
var _tick_box: SpinBox
var _speed_box: SpinBox
var _library: Node

func _ready() -> void:
	var root := $Root
	_build_top(root)
	_build_bottom(root)
	ToolManager.tool_changed.connect(_on_tool_changed)
	ToolManager.zoom_changed.connect(_on_zoom_changed)
	ToolManager.probed.connect(_on_probed)
	_on_tool_changed(ToolManager.current)
	_on_zoom_changed(ToolManager.zoom, ToolManager.pivot, ToolManager.locked)

func set_library(node: Node) -> void:
	_library = node

func _panel(style: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = style
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box

func _mk_button(parent: Control, text: String, min_w := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 34)
	b.add_theme_stylebox_override("normal", _panel(Color(0.055, 0.11, 0.10, 0.92), Color(0.16, 0.36, 0.31)))
	b.add_theme_stylebox_override("hover", _panel(Color(0.08, 0.17, 0.15, 0.95), Color(0.36, 0.88, 0.70)))
	b.add_theme_stylebox_override("pressed", _panel(Color(0.10, 0.28, 0.24, 0.98), Color(0.45, 1.0, 0.78)))
	parent.add_child(b)
	return b

func _build_top(root: Control) -> void:
	var bar := HBoxContainer.new()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(bar)
	root.add_child(margin)
	# Инструменты 1..5
	var tool_box := HBoxContainer.new()
	tool_box.add_theme_constant_override("separation", 6)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel(Color(0.045, 0.085, 0.08, 0.90), Color(0.13, 0.30, 0.27)))
	panel.add_child(tool_box)
	bar.add_child(panel)
	for i in 5:
		var b := _mk_button(tool_box, "", 52)
		var icon := HudIcon.new()
		icon.kind = i
		icon.position = Vector2(11, 2)
		b.add_child(icon)
		b.tooltip_text = "%d — %s" % [i + 1, TOOL_NAMES[i]]
		var hotkey := Label.new()
		hotkey.text = str(i + 1)
		hotkey.add_theme_color_override("font_color", Color(0.55, 0.75, 0.68))
		hotkey.add_theme_font_size_override("font_size", 11)
		hotkey.position = Vector2(36, 17)
		b.add_child(hotkey)
		b.pressed.connect(ToolManager.select.bind(i))
		_tool_buttons.append(b)
	# Лупа: зум и фиксированные ступени
	var loupe_box := HBoxContainer.new()
	var loupe_panel := PanelContainer.new()
	loupe_panel.add_theme_stylebox_override("panel", _panel(Color(0.045, 0.085, 0.08, 0.90), Color(0.13, 0.30, 0.27)))
	loupe_panel.add_child(loupe_box)
	bar.add_child(loupe_panel)
	_zoom_label = Label.new()
	_zoom_label.text = "×1"
	_zoom_label.add_theme_font_size_override("font_size", 20)
	_zoom_label.add_theme_color_override("font_color", Color(0.62, 1.0, 0.83))
	_zoom_label.custom_minimum_size = Vector2(46, 0)
	_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loupe_box.add_child(_zoom_label)
	for step_zoom in [1, 2, 4, 8]:
		var b := _mk_button(loupe_box, "×%d" % step_zoom, 34)
		b.pressed.connect(ToolManager.set_zoom.bind(step_zoom))
	# Название инструмента + подсказка
	var info := VBoxContainer.new()
	bar.add_child(info)
	_tool_label = Label.new()
	_tool_label.add_theme_font_size_override("font_size", 15)
	_tool_label.add_theme_color_override("font_color", Color(0.78, 0.98, 0.90))
	info.add_child(_tool_label)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.52, 0.68, 0.63))
	info.add_child(_hint)

func _build_bottom(root: Control) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	margin.add_child(bar)
	root.add_child(margin)
	# Транспорт симуляции
	_play_button = _mk_button(bar, "▶", 44)
	_play_button.tooltip_text = "Пауза / пуск (симуляция)"
	_play_button.pressed.connect(func() -> void: SimClock.playing = not SimClock.playing)
	var step_button := _mk_button(bar, "Шаг", 44)
	step_button.tooltip_text = "Один такт (когда пауза)"
	step_button.pressed.connect(func() -> void:
		if not SimClock.playing:
			SimClock.step())
	var reset_button := _mk_button(bar, "⟲", 44)
	reset_button.tooltip_text = "Остановить и обнулить время"
	reset_button.pressed.connect(func() -> void: SimClock.reset())
	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(150, 0)
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.add_theme_color_override("font_color", Color(0.62, 1.0, 0.83))
	bar.add_child(_time_label)
	# Такт и скорость
	_tick_box = SpinBox.new()
	_tick_box.min_value = 0.05
	_tick_box.max_value = 1000.0
	_tick_box.step = 0.05
	_tick_box.value = SimClock.tick_ms
	_tick_box.custom_minimum_size = Vector2(88, 34)
	_tick_box.tooltip_text = "Длина такта, мс (реальное ускоренное время)"
	_tick_box.value_changed.connect(func(v: float) -> void: SimClock.tick_ms = v)
	bar.add_child(_tick_box)
	var tick_label := Label.new()
	tick_label.text = "мс/такт"
	tick_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tick_label.add_theme_color_override("font_color", Color(0.52, 0.68, 0.63))
	bar.add_child(tick_label)
	_speed_box = SpinBox.new()
	_speed_box.min_value = 0.25
	_speed_box.max_value = 16.0
	_speed_box.step = 0.25
	_speed_box.value = SimClock.speed
	_speed_box.custom_minimum_size = Vector2(64, 34)
	_speed_box.tooltip_text = "Скорость симуляции, ×"
	_speed_box.value_changed.connect(func(v: float) -> void: SimClock.speed = v)
	bar.add_child(_speed_box)
	var speed_label := Label.new()
	speed_label.text = "×"
	speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speed_label.add_theme_color_override("font_color", Color(0.52, 0.68, 0.63))
	bar.add_child(speed_label)
	# Валидация
	var validate_button := _mk_button(bar, "✓ Проверить плату", 130)
	validate_button.pressed.connect(_on_validate)
	# Тост
	_toast = Label.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.0
	_toast.offset_left = -180
	_toast.offset_top = 64
	_toast.custom_minimum_size = Vector2(360, 30)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Color(0.72, 1.0, 0.87))
	_toast.visible = false
	root.add_child(_toast)

func _process(_delta: float) -> void:
	_time_label.text = "Такт %d" % SimClock.now
	_play_button.text = "⏸" if SimClock.playing else "▶"

func _on_tool_changed(tool: int) -> void:
	for i in _tool_buttons.size():
		_tool_buttons[i].modulate = Color(1.35, 1.35, 1.35) if i == tool else Color.WHITE
	_tool_label.text = TOOL_NAMES[tool]
	_hint.text = TOOL_HINTS[tool]

func _on_zoom_changed(factor: int, _pivot: Vector3, locked: bool) -> void:
	_zoom_label.text = "×%d%s" % [factor, " 🔒" if locked else ""]

func _on_probed(pin: String, sample: Dictionary) -> void:
	if pin.is_empty():
		_hint.text = "Тестер: наведи на порт или дорожку"
		return
	var sig: String = {0: "0", 1: "1", 2: "Z", 3: "X"}.get(int(sample.get("sig", 2)), "?")
	var volts: Variant = sample.get("volts")
	var v := "%.2f В" % float(volts) if volts != null else "Z (плавает)"
	_hint.text = "%s  =  %s  ·  %s  ·  ток %.2f мА%s" % [pin, sig, v, float(sample.get("ma", 0.0)),
		"  ·  КЗ!" if str(sample.get("fault", "")) == "short" else ""]

func _on_validate() -> void:
	var editor := get_parent().get_node_or_null("BoardEditor")
	if editor == null:
		_show_toast("Редактор платы не найден")
		return
	var issues: PackedStringArray = editor.validate_board()
	if issues.is_empty():
		_show_toast("Плата в порядке: КЗ нет, всё подключено, такт есть")
	else:
		_show_toast("Замечания: %d — см. панель отладки" % issues.size())

func _show_toast(message: String) -> void:
	_toast.text = message
	_toast.visible = true
	get_tree().create_timer(2.6).timeout.connect(func() -> void: _toast.visible = false)

func toast(message: String) -> void:
	_show_toast(message)
