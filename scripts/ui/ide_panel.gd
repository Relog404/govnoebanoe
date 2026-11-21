class_name IdePanel
extends VBoxContainer
## Мини-IDE: редактор ChipScript с подсветкой, примеры, шпаргалка, консоль.

signal run_requested
signal check_requested
signal example_requested(example_name: String, code: String)

const CHEATSHEET := """[color=#39ff88][b]ТОЧКИ ВХОДА[/b][/color]
[color=#33d6e0]start()[/color] — один раз при запуске
[color=#33d6e0]update(dt)[/color] — каждый кадр
[color=#33d6e0]draw()[/color] — необязательно; можно рисовать прямо в update

[color=#39ff88][b]СОБЫТИЯ[/b][/color]
on_mouse_down(x, y, btn)
on_mouse_up(x, y, btn)
on_mouse_move(x, y)
on_key_down("W")
on_key_up("W")
on_wheel(delta)

[color=#39ff88][b]ВВОД[/b][/color]
mouse_x() · mouse_y()
mouse_down(btn) · mouse_clicked(btn) · mouse_released(btn)
key_down("W") · key_pressed("SPACE") · key_released("LEFT")
Клавиши: A-Z, 0-9, SPACE, ENTER, ESC, TAB,
SHIFT, CTRL, ALT, LEFT/RIGHT/UP/DOWN, F1-F12

[color=#39ff88][b]РИСОВАНИЕ[/b][/color]
clear(color)
fill_rect(x, y, w, h, color)
rect(x, y, w, h, color[, толщина])
line(x1, y1, x2, y2, color[, толщина])
fill_circle(x, y, r, color)
circle(x, y, r, color[, толщина])
pixel(x, y, color)
triangle(x1, y1, x2, y2, x3, y3, color)
text(x, y, "строка", color[, размер])
Цвет: "#39ff88", "red", "cyan" или [r, g, b] (0..1)

[color=#39ff88][b]МАТЕМАТИКА[/b][/color]
abs · min · max · floor · ceil · round · sqrt
sin · cos · tan · atan2 · pow · clamp · lerp · sign
rand(a, b) · random() · dist(x1, y1, x2, y2) · pi()

[color=#39ff88][b]ДАННЫЕ[/b][/color]
var a = [1, 2, 3]     массивы
len(a) · push(a, v) · pop(a) · range(0, 10)
str(x) · num(x) · has(a, v)
for i in range(0, 10) { ... }

Экран: 320×180 виртуальных пикселей.
dt() — секунды с прошлого кадра.
Ваш чип ограничивает FPS и бюджет инструкций:
тяжёлая программа будет тормозить на слабой сборке.
"""

var code_edit: CodeEdit
var console: RichTextLabel
var status_label: Label
var _examples_box: VBoxContainer
var _chip_info := ""

var _error_lines: Array[int] = []


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build()
	set_process(false)


func _build() -> void:
	# --- Верхняя панель ---
	var bar := UITheme.hbox(6)
	bar.add_child(UITheme.heading("ПРОГРАММА ЧИПА", UITheme.CYAN))
	bar.add_child(UITheme.label("ChipScript", 10, UITheme.FAINT))
	bar.add_child(UITheme.spacer())
	var check_btn := UITheme.button("ПРОВЕРИТЬ")
	check_btn.tooltip_text = "Скомпилировать программу и показать ошибки"
	check_btn.pressed.connect(func() -> void: check_requested.emit())
	bar.add_child(check_btn)
	var run_btn := UITheme.button("▶ ЗАПУСТИТЬ", "primary")
	run_btn.tooltip_text = "Собрать программу и запустить её на текущем чипе (F5)"
	run_btn.pressed.connect(func() -> void: run_requested.emit())
	bar.add_child(run_btn)
	add_child(bar)

	# --- Код + боковая панель ---
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = -240
	add_child(split)

	var code_wrap := UITheme.panel(UITheme.BG_2, UITheme.LINE, 6)
	code_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var code_box := UITheme.vbox(4)
	var code_margin := MarginContainer.new()
	code_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code_margin.add_theme_constant_override("margin_left", 6)
	code_margin.add_theme_constant_override("margin_right", 4)
	code_margin.add_theme_constant_override("margin_top", 4)
	code_margin.add_theme_constant_override("margin_bottom", 2)

	code_edit = CodeEdit.new()
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code_edit.custom_minimum_size = Vector2(280, 200)
	code_edit.syntax_highlighter = ChipScriptHighlighter.new()
	code_edit.gutters_draw_line_numbers = true
	code_edit.gutters_zero_pad_line_numbers = false
	code_edit.highlight_current_line = true
	code_edit.caret_blink = true
	code_edit.indent_automatic = true
	code_edit.auto_brace_completion_enabled = true
	code_edit.line_folding = false
	code_edit.draw_tabs = true
	code_edit.scroll_past_end_of_file = true
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	code_edit.indent_size = 2
	code_edit.add_theme_font_override("font", UITheme.mono_font())
	code_edit.add_theme_font_size_override("font_size", 13)
	code_edit.add_theme_color_override("selection_color", Color(0.2, 0.8, 0.5, 0.22))
	code_edit.add_theme_constant_override("line_spacing", 2)
	code_edit.text_changed.connect(_on_text_changed)
	code_margin.add_child(code_edit)
	code_box.add_child(code_margin)

	status_label = UITheme.label("Готово", 10, UITheme.FAINT)
	status_label.clip_text = true
	status_label.custom_minimum_size = Vector2(0, 16)
	var status_wrap := MarginContainer.new()
	status_wrap.add_theme_constant_override("margin_left", 8)
	status_wrap.add_theme_constant_override("margin_bottom", 4)
	status_wrap.add_child(status_label)
	code_box.add_child(status_wrap)
	code_wrap.add_child(code_box)
	split.add_child(code_wrap)

	var side_wrap := UITheme.panel(UITheme.PANEL, UITheme.LINE_SOFT, 6)
	side_wrap.custom_minimum_size = Vector2(220, 0)
	var side := UITheme.vbox(6)
	var side_margin := MarginContainer.new()
	side_margin.add_theme_constant_override("margin_left", 8)
	side_margin.add_theme_constant_override("margin_right", 8)
	side_margin.add_theme_constant_override("margin_top", 8)
	side_margin.add_theme_constant_override("margin_bottom", 8)
	side_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_margin.add_child(side)
	side_wrap.add_child(side_margin)
	split.add_child(side_wrap)

	side.add_child(UITheme.heading("ПРИМЕРЫ", UITheme.ACCENT))
	_examples_box = UITheme.vbox(4)
	side.add_child(_examples_box)
	side.add_child(UITheme.separator())

	var help_head := UITheme.hbox(4)
	help_head.add_child(UITheme.heading("ШПАРГАЛКА", UITheme.CYAN))
	help_head.add_child(UITheme.spacer())
	help_head.add_child(UITheme.label("320×180", 9, UITheme.FAINT))
	side.add_child(help_head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.text = CHEATSHEET
	rtl.add_theme_font_override("normal_font", UITheme.mono_font())
	rtl.add_theme_font_override("mono_font", UITheme.mono_font())
	rtl.add_theme_font_size_override("normal_font_size", 11)
	rtl.add_theme_font_size_override("mono_font_size", 11)
	rtl.add_theme_color_override("default_color", UITheme.DIM)
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rtl)

	# --- Консоль ---
	var console_wrap := UITheme.panel(UITheme.BG_2, UITheme.LINE_SOFT, 6)
	console_wrap.custom_minimum_size = Vector2(0, 104)
	var cbox := UITheme.vbox(2)
	var chead := UITheme.hbox(6)
	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 8)
	cm.add_theme_constant_override("margin_right", 8)
	cm.add_theme_constant_override("margin_top", 5)
	cm.add_theme_constant_override("margin_bottom", 5)
	cm.add_child(cbox)
	console_wrap.add_child(cm)
	chead.add_child(UITheme.heading("КОНСОЛЬ · PRINT", UITheme.POWER))
	chead.add_child(UITheme.spacer())
	var clear_btn := UITheme.button("ОЧИСТИТЬ")
	clear_btn.add_theme_font_size_override("font_size", 9)
	clear_btn.pressed.connect(clear_console)
	chead.add_child(clear_btn)
	cbox.add_child(chead)

	var cscroll := ScrollContainer.new()
	cscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cbox.add_child(cscroll)
	console = RichTextLabel.new()
	console.bbcode_enabled = false
	console.fit_content = true
	console.scroll_following = true
	console.selection_enabled = true
	console.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	console.add_theme_font_override("normal_font", UITheme.mono_font())
	console.add_theme_font_size_override("normal_font_size", 11)
	cscroll.add_child(console)
	add_child(console_wrap)


func set_examples(examples: Array) -> void:
	if _examples_box == null:
		return
	for child in _examples_box.get_children():
		child.queue_free()
	for ex in examples:
		var b := UITheme.button(String(ex.get("name", "Пример")), "normal")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = String(ex.get("desc", ""))
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_example_button.bind(String(ex.get("name", "")),
			String(ex.get("code", ""))))
		_examples_box.add_child(b)


func _on_example_button(ex_name: String, code: String) -> void:
	example_requested.emit(ex_name, code)


# ---------------------------------------------------------------------------
# API для Main
# ---------------------------------------------------------------------------

func set_code(text: String) -> void:
	code_edit.text = text
	code_edit.set_caret_line(0)
	code_edit.set_caret_column(0)
	_clear_error_marks()
	status_label.text = "Код обновлён"
	status_label.add_theme_color_override("font_color", UITheme.FAINT)


func get_code() -> String:
	return code_edit.text


func set_chip_info(text: String) -> void:
	_chip_info = text
	if _error_lines.is_empty():
		status_label.text = text
		status_label.add_theme_color_override("font_color", UITheme.FAINT)


func show_compile_result(program: ChipProgram) -> void:
	_clear_error_marks()
	if program == null or not program.is_valid():
		if program != null:
			for e in program.errors:
				var line := clampi(int(e.get("line", 1)) - 1, 0, maxi(0, code_edit.get_line_count() - 1))
				code_edit.set_line_background_color(line, Color(1.0, 0.25, 0.35, 0.18))
				_error_lines.append(line)
			var first := program.errors[0]
			status_label.text = "Ошибка · строка %d: %s" % [int(first.get("line", 0)),
				String(first.get("message", ""))]
		else:
			status_label.text = "Ошибка компиляции"
		status_label.add_theme_color_override("font_color", UITheme.ERROR)
		_log("Компиляция не удалась:", UITheme.ERROR)
		if program != null:
			for e in program.errors:
				_log("  строка %d: %s" % [int(e.get("line", 0)), String(e.get("message", ""))],
					UITheme.ERROR)
	else:
		status_label.text = "OK · %d функций · %s" % [
			program.functions.size(), _chip_info]
		status_label.add_theme_color_override("font_color", UITheme.OK)
		_log("Компиляция OK: %d функций" % program.functions.size(), UITheme.OK)


func _clear_error_marks() -> void:
	for line in _error_lines:
		if line >= 0 and line < code_edit.get_line_count():
			code_edit.set_line_background_color(line, Color(0, 0, 0, 0))
	_error_lines.clear()


func _on_text_changed() -> void:
	if not _error_lines.is_empty():
		_clear_error_marks()
	status_label.text = "Изменено · Ctrl+Enter — проверить и запустить"
	status_label.add_theme_color_override("font_color", UITheme.WARN)


# ---------------------------------------------------------------------------
# Консоль
# ---------------------------------------------------------------------------

func _log(text: String, color: Color = UITheme.DIM) -> void:
	if console == null:
		return
	console.push_color(color)
	console.add_text(text + "\n")
	console.pop()


func log_line(text: String, color: Color = UITheme.DIM) -> void:
	_log(text, color)


func log_program_output(lines: Array) -> void:
	for line in lines:
		_log(String(line), UITheme.TEXT)


func log_system(text: String, color: Color = UITheme.CYAN) -> void:
	_log("› " + text, color)


func clear_console() -> void:
	if console != null:
		console.clear()


func focus_code() -> void:
	code_edit.grab_focus()
