extends Control

# «Кремний» — отдельное разворачиваемое окно: код сценария платы.
# Синтаксис, примеры и ошибки — по-русски; запуск генерирует плату
# ТОЛЬКО из внутриигровых компонентов (через core/board_script.gd).
const BoardScript := preload("res://core/board_script.gd")
const EXAMPLE_PATH := "res://data/examples/video_card.silicon"

var _code: CodeEdit
var _log: RichTextLabel
var _stats: Label
var _run_button: Button
var _panel: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_build()
	load_example()  # окно открывается с примером «видеокарта»


# ---------- Интерфейс ----------

func _style(style: Color, border: Color, radius := 8, width := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = style
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func _button(text: String, accent := false, min_w := 96) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 38)
	var normal := _style(Color(0.075, 0.16, 0.135, 0.96), Color(0.18, 0.42, 0.35), 6, 1)
	var hover := _style(Color(0.10, 0.24, 0.20, 0.98), Color(0.32, 0.85, 0.62), 6, 1)
	var pressed := _style(Color(0.12, 0.34, 0.27, 1.0), Color(0.42, 1.0, 0.72), 6, 1)
	if accent:
		normal = _style(Color(0.09, 0.38, 0.27, 1.0), Color(0.42, 1.0, 0.70), 6, 1)
		hover = _style(Color(0.11, 0.47, 0.33, 1.0), Color(0.55, 1.0, 0.78), 6, 1)
		pressed = _style(Color(0.14, 0.56, 0.40, 1.0), Color(0.70, 1.0, 0.85), 6, 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color(0.90, 1.0, 0.94))
	b.add_theme_font_size_override("font_size", 14)
	return b

func _build() -> void:
	# Затемнение за окном — клик мимо закрывает.
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.05, 0.04, 0.55)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(shade)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(PRESET_CENTER)
	_panel.offset_left = -620.0
	_panel.offset_right = 620.0
	_panel.offset_top = -330.0
	_panel.offset_bottom = 330.0
	_panel.add_theme_stylebox_override("panel", _style(Color(0.028, 0.075, 0.062, 0.985), Color(0.23, 0.60, 0.46), 12, 2))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)

	# Шапка: название языка + кнопки
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var titles := VBoxContainer.new()
	header.add_child(titles)
	var title := Label.new()
	title.text = "КРЕМНИЙ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.72))
	titles.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "сценарий платы — собирает её из внутриигровых компонентов"
	subtitle.add_theme_color_override("font_color", Color(0.52, 0.72, 0.64))
	subtitle.add_theme_font_size_override("font_size", 11)
	titles.add_child(subtitle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(spacer)
	var example := _button("Пример: видеокарта", false, 190)
	example.tooltip_text = "Загрузить res://data/examples/video_card.silicon"
	example.pressed.connect(load_example)
	header.add_child(example)
	var clear := _button("Очистить", false, 110)
	clear.pressed.connect(func() -> void:
		_code.text = ""
		_print_result({"ok": true, "log": ["Буфер очищен."], "error": ""}))
	header.add_child(clear)
	_run_button = _button("▶  Запуск", true, 150)
	_run_button.tooltip_text = "Ctrl+Enter"
	_run_button.pressed.connect(run_script)
	header.add_child(_run_button)
	var close_button := _button("✕", false, 44)
	close_button.tooltip_text = "Закрыть (Esc)"
	close_button.pressed.connect(close)
	header.add_child(close_button)

	# Код
	_code = CodeEdit.new()
	_code.size_flags_vertical = SIZE_EXPAND_FILL
	_code.size_flags_horizontal = SIZE_EXPAND_FILL
	_code.custom_minimum_size = Vector2(0, 380)
	_code.draw_tabs = false
	_code.gutters_draw_line_numbers = true

	_code.placeholder_text = "board 16x10\nplace chip_dip16 GFX at 4,2 io_map={0=[P1,P2,P3,P4,P5,P6,P7,P8],1=P9,2=P10}\n…\nasm GFX\n    LIT R0, 0\n    HALT\nend\nflash GFX"
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["JetBrains Mono", "Fira Code", "Cascadia Mono", "DejaVu Sans Mono", "monospace"])
	_code.add_theme_font_override("font", mono)
	_code.add_theme_font_size_override("font_size", 15)
	_code.add_theme_color_override("font_color", Color(0.83, 0.97, 0.89))
	_code.add_theme_color_override("background_color", Color(0.012, 0.038, 0.032))
	_code.add_theme_color_override("line_number_color", Color(0.30, 0.48, 0.41))
	_code.gui_input.connect(_on_code_input)
	column.add_child(_code)

	# Журнал запуска
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.custom_minimum_size = Vector2(0, 118)
	column.add_child(footer)
	var log_panel := PanelContainer.new()
	log_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	log_panel.add_theme_stylebox_override("panel", _style(Color(0.010, 0.030, 0.025), Color(0.13, 0.34, 0.28), 6, 1))
	footer.add_child(log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.add_theme_color_override("default_color", Color(0.62, 0.88, 0.74))
	log_panel.add_child(_log)
	var stats_box := VBoxContainer.new()
	stats_box.custom_minimum_size = Vector2(150, 0)
	footer.add_child(stats_box)
	_stats = Label.new()
	_stats.text = ""
	_stats.add_theme_color_override("font_color", Color(0.52, 0.72, 0.64))
	_stats.add_theme_font_size_override("font_size", 11)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_box.add_child(_stats)
	var hint := Label.new()
	hint.text = "board · clear · place · erase\nwire · unwire · asm … end\nflash · start · reset · note"
	hint.add_theme_color_override("font_color", Color(0.34, 0.52, 0.45))
	hint.add_theme_font_size_override("font_size", 10)
	stats_box.add_child(hint)


# ---------- Действия ----------

func load_example() -> void:
	var text := FileAccess.get_file_as_string(EXAMPLE_PATH)
	if text.is_empty():
		_log.text = "[color=#ff8a80]Не открыть пример: %s[/color]" % EXAMPLE_PATH
		return
	_code.text = text
	_stats.text = "Пример загружен.\nНажми «Запуск»."

func run_script() -> void:
	var source := _code.text
	if source.strip_edges().is_empty():
		_log.text = "[color=#ffd166]Пусто. Впиши сценарий или открой пример.[/color]"
		return
	var editor := get_node_or_null("/root/Main/BoardEditor")
	# main.tscn: world/main.gd — корень; редактор платы — первый ребёнок Main.
	if editor == null:
		editor = get_parent().get_node_or_null("BoardEditor")
	var script := BoardScript.new()
	var result: Dictionary = script.run(source, editor)
	_print_result(result)

func _print_result(result: Dictionary) -> void:
	var lines: Array = result.get("log", [])
	var out: Array[String] = []
	for line in lines:
		var text := str(line)
		if text.begins_with("ОШИБКА"):
			out.append("[color=#ff8a80]%s[/color]" % text.xml_escape())
		elif text.begins_with("flash"):
			out.append("[color=#8dffbe]%s[/color]" % text.xml_escape())
		else:
			out.append("[color=#9fd8bb]%s[/color]" % text.xml_escape())
	_log.text = "\n".join(out)
	_stats.text = ("Готово за один проход." if bool(result.get("ok", false)) else "Остановлено ошибкой.") + "\nСтрок: %d" % _code.text.split("\n").size()
	# Искра не нужна, но пусть HUD узнает про плату.
	var hud := get_node_or_null("/root/Main/Hud")
	if hud and hud.has_method("toast"):
		hud.toast("Сценарий выполнен" if bool(result.get("ok", false)) else "Сценарий упал: строка %d" % int(result.get("line", 0)))

func close() -> void:
	visible = false

func _on_code_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and event.ctrl_pressed:
		run_script()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
