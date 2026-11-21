extends Control
## Главный экран: собирает интерфейс, связывает плату, IDE, экран вывода,
## сохранение/загрузку и симуляцию чипа.

const HELP_TEXT := """[color=#39ff88][b]ЧТО ЭТО[/b][/color]
Вы собираете чип из компонентов на бесконечном поле, пишете для него
программу на ChipScript и сразу играете в результат на экране вывода.
Назначение чипа не ограничено: холодильник, аркада, суперкомпьютер.

[color=#39ff88][b]СБОРКА[/b][/color]
• ЛКМ по палитре — выбрать компонент, ЛКМ по полю — поставить.
  Карточку из палитры можно просто перетащить на поле.
• R — повернуть (пока компонент выбран или под курсором).
• Тяните компонент ЛКМ, чтобы переместить.
• Клик по цветному порту — начало дорожки, клик по другому порту того же
  типа — соединение. Питание ↔ питание, шина ↔ шина, видео ↔ видео.
• ПКМ/СКМ — панорама, колесо — зум, WASD/стрелки — камера, F — показать всё.
• Del — удалить, Esc — отменить режим.
• Дорожки трассируются автоматически и обходят компоненты.

[color=#39ff88][b]ЧИП РАБОТАЕТ, ЕСЛИ[/b][/color]
1. Power In подключён к питанию компонентов (VRM добавляет ватты).
2. Ядра (GPU/CPU) соединены шиной с VRAM / XON / NAND-контроллером.
3. Видео-порт ядра подключён к Display Out.
4. Кулеров хватает на тепло — иначе чип перегревается и глючит.
Слабый чип выдаёт низкий FPS и низкое разрешение рендера.
Ошибки не блокируют сборку: можно собрать нерабочий чип и увидеть глюки.
Компоненты с проблемами помечены красным «!» — наведите мышь, чтобы
прочитать причину в строке состояния.

[color=#39ff88][b]ПРОГРАММА[/b][/color]
Вкладка «ПРОГРАММА» — мини-IDE с подсветкой и примерами.
Точки входа: start(), update(dt), draw() (необязательно).
Ввод: mouse_x(), mouse_y(), mouse_down(btn), mouse_clicked(btn),
key_down("W"), key_pressed("SPACE"), key_released("LEFT").
Рисование: clear, fill_rect, rect, line, fill_circle, circle, text, triangle.
Цвета: "#39ff88", "red", [r, g, b].
Полная шпаргалка — в правой колонке IDE.

[color=#39ff88][b]ЭКРАН ВЫВОДА[/b][/color]
• RUN / STOP / СБРОС — управление симуляцией.
• Наведите курсор на экран — мышь и ВСЕ клавиши уходят в программу чипа.
• Клик по экрану работает как клик внутри вашей игры.
• F11 — полный экран, Esc — выйти (в полном экране).
• FPS, питание, температура, стабильность и шина — в реальном времени.

[color=#39ff88][b]ФАЙЛЫ И ГОРЯЧИЕ КЛАВИШИ[/b][/color]
Ctrl+S — сохранить JSON, Ctrl+O — загрузить, F5 — запустить,
F1 — помощь. Проект хранит схему и код в одном .json.

[color=#4e6a63]Каждый новый .tres в resources/components/ автоматически
появляется в палитре — код менять не нужно.[/color]
"""

const DEFAULT_STATUS := "F5 — запуск · ЛКМ — сборка · ? — помощь"

var board: ChipBoard
var stats: ChipEvaluator.Stats = null
var runtime: ChipRuntime
var chip_view: ChipView
var ide: IdePanel
var output: OutputScreen

var _tab_content: Control
var _output_page: Control
var _program_page: Control
var _tab_output_btn: Button
var _tab_program_btn: Button
var _current_tab := "output"

var _status_label: Label
var _status_timer := 0.0
var _run_btn: Button
var _stop_btn: Button
var _last_running := false
var _last_error := ""
var _console_seq := 0
var _console_timer := 0.0

var _fullscreen_layer: Control
var _fullscreen_content: VBoxContainer
var _is_fullscreen := false

var _save_dialog: FileDialog
var _load_dialog: FileDialog
var _confirm_dialog: ConfirmationDialog
var _help_overlay: Control
var _help_visible := false


func _ready() -> void:
	theme = UITheme.build_theme()
	get_window().min_size = Vector2i(1100, 680)
	get_window().title = "Chip Architect"
	board = DemoProjects.demo_board()
	runtime = ChipRuntime.new()
	runtime.name = "ChipRuntime"
	add_child(runtime)
	runtime.metrics_changed.connect(_on_metrics_changed)

	_build_ui()
	_build_overlays()
	_build_dialogs()

	runtime.set_surface(output.surface)
	chip_view.attach_board(board)
	ide.set_code(DemoProjects.starter_code())
	ide.set_examples(DemoProjects.examples())
	_refresh_stats()
	_update_run_buttons()
	_set_status("Демо-чип загружен. Нажмите RUN (F5).", "ok")
	output.surface.reset_input()


# ---------------------------------------------------------------------------
# Интерфейс
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := UITheme.vbox(8)
	margin.add_child(root)
	root.add_child(_build_topbar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	root.add_child(split)

	chip_view = ChipView.new()
	chip_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip_view.size_flags_stretch_ratio = 1.45
	chip_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(chip_view)
	chip_view.status.connect(_set_status)
	chip_view.board_edited.connect(_on_board_edited)
	chip_view.selection_changed.connect(_on_selection_changed)

	var right := UITheme.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(520, 0)
	split.add_child(right)

	right.add_child(_build_tabbar())

	_tab_content = Control.new()
	_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_tab_content)

	_output_page = Control.new()
	_output_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tab_content.add_child(_output_page)
	output = OutputScreen.new()
	output.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_output_page.add_child(output)
	output.run_requested.connect(_on_run)
	output.stop_requested.connect(_on_stop)
	output.restart_requested.connect(_on_restart)
	output.fullscreen_toggle.connect(_toggle_fullscreen)

	_program_page = Control.new()
	_program_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tab_content.add_child(_program_page)
	ide = IdePanel.new()
	ide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_program_page.add_child(ide)
	ide.run_requested.connect(_on_run)
	ide.check_requested.connect(_on_check)
	ide.example_requested.connect(_on_example_requested)

	_switch_tab("output")


func _build_topbar() -> PanelContainer:
	var panel := UITheme.panel(UITheme.PANEL, UITheme.LINE, 8)
	panel.custom_minimum_size = Vector2(0, 52)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var row := UITheme.hbox(8)
	margin.add_child(row)

	var title_box := UITheme.vbox(-2)
	var title_row := UITheme.hbox(0)
	title_row.add_child(UITheme.label("CHIP", 18, UITheme.ACCENT))
	title_row.add_child(UITheme.label(" ARCHITECT", 18, UITheme.TEXT))
	title_box.add_child(title_row)
	title_box.add_child(UITheme.label("песочница чипов · prototype", 8, UITheme.FAINT))
	row.add_child(title_box)

	var sep := ColorRect.new()
	sep.color = UITheme.LINE
	sep.custom_minimum_size = Vector2(1, 26)
	row.add_child(sep)

	_status_label = UITheme.label(DEFAULT_STATUS, 10, UITheme.DIM)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.clip_text = true
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_status_label)

	var demo_btn := UITheme.button("ДЕМО")
	demo_btn.tooltip_text = "Загрузить готовый рабочий чип и пример программы"
	demo_btn.pressed.connect(_on_demo_pressed)
	var new_btn := UITheme.button("НОВЫЙ")
	new_btn.tooltip_text = "Очистить плату"
	new_btn.pressed.connect(_on_new_pressed)
	var save_btn := UITheme.button("СОХР.")
	save_btn.tooltip_text = "Сохранить схему и код в JSON (Ctrl+S)"
	save_btn.pressed.connect(_open_save_dialog)
	var load_btn := UITheme.button("ЗАГР.")
	load_btn.tooltip_text = "Загрузить проект из JSON (Ctrl+O)"
	load_btn.pressed.connect(_open_load_dialog)
	var help_btn := UITheme.button("?")
	help_btn.custom_minimum_size = Vector2(30, 0)
	help_btn.tooltip_text = "Помощь (F1)"
	help_btn.pressed.connect(_toggle_help)

	_stop_btn = UITheme.button("■ STOP", "danger")
	_stop_btn.pressed.connect(_on_stop)
	_run_btn = UITheme.button("▶ RUN", "primary")
	_run_btn.tooltip_text = "Запустить программу на чипе (F5)"
	_run_btn.pressed.connect(_on_run)

	row.add_child(demo_btn)
	row.add_child(new_btn)
	row.add_child(save_btn)
	row.add_child(load_btn)
	row.add_child(help_btn)
	row.add_child(sep.duplicate())
	row.add_child(_stop_btn)
	row.add_child(_run_btn)
	return panel


func _build_tabbar() -> HBoxContainer:
	var bar := UITheme.hbox(4)
	_tab_output_btn = Button.new()
	_tab_output_btn.text = "ЭКРАН ВЫВОДА"
	_tab_output_btn.focus_mode = Control.FOCUS_NONE
	_tab_output_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tab_output_btn.pressed.connect(func() -> void: _switch_tab("output"))
	_tab_program_btn = Button.new()
	_tab_program_btn.text = "ПРОГРАММА"
	_tab_program_btn.focus_mode = Control.FOCUS_NONE
	_tab_program_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tab_program_btn.pressed.connect(func() -> void: _switch_tab("program"))
	bar.add_child(_tab_output_btn)
	bar.add_child(_tab_program_btn)
	bar.add_child(UITheme.spacer())
	var hint := UITheme.label("F5 — RUN · F1 — помощь", 9, UITheme.FAINT)
	bar.add_child(hint)
	return bar


func _switch_tab(tab: String) -> void:
	_current_tab = tab
	if _output_page != null:
		_output_page.visible = tab == "output"
	if _program_page != null:
		_program_page.visible = tab == "program"
	_style_tab(_tab_output_btn, tab == "output")
	_style_tab(_tab_program_btn, tab == "program")


func _style_tab(btn: Button, active: bool) -> void:
	if btn == null:
		return
	if active:
		btn.add_theme_stylebox_override("normal", UITheme.box(UITheme.PANEL_3, UITheme.ACCENT, 5))
		btn.add_theme_color_override("font_color", UITheme.ACCENT)
	else:
		btn.add_theme_stylebox_override("normal",
			UITheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 5, 0))
		btn.add_theme_color_override("font_color", UITheme.DIM)
	btn.add_theme_stylebox_override("hover", UITheme.box(UITheme.PANEL_2, UITheme.LINE, 5))
	btn.add_theme_stylebox_override("pressed", UITheme.box(UITheme.PANEL_3, UITheme.ACCENT, 5))


# ---------------------------------------------------------------------------
# Оверлеи: полный экран и помощь
# ---------------------------------------------------------------------------

func _build_overlays() -> void:
	_fullscreen_layer = Control.new()
	_fullscreen_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fullscreen_layer.visible = false
	_fullscreen_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fullscreen_layer)

	var fbg := ColorRect.new()
	fbg.color = Color("#050a0c")
	fbg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fullscreen_layer.add_child(fbg)

	var fmargin := MarginContainer.new()
	fmargin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fmargin.add_theme_constant_override("margin_left", 18)
	fmargin.add_theme_constant_override("margin_right", 18)
	fmargin.add_theme_constant_override("margin_top", 12)
	fmargin.add_theme_constant_override("margin_bottom", 10)
	_fullscreen_layer.add_child(fmargin)
	_fullscreen_content = UITheme.vbox(6)
	fmargin.add_child(_fullscreen_content)

	_help_overlay = Control.new()
	_help_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_overlay.visible = false
	_help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_help_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_overlay.add_child(center)

	var panel := UITheme.panel(UITheme.PANEL, Color("#2b555a"), 10)
	panel.custom_minimum_size = Vector2(760, 620)
	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 18)
	pm.add_theme_constant_override("margin_right", 18)
	pm.add_theme_constant_override("margin_top", 14)
	pm.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(pm)
	var pv := UITheme.vbox(8)
	pm.add_child(pv)
	var head := UITheme.hbox(8)
	head.add_child(UITheme.label("ПОМОЩЬ", 16, UITheme.ACCENT))
	head.add_child(UITheme.label("Chip Architect", 11, UITheme.FAINT))
	head.add_child(UITheme.spacer())
	var close_btn := UITheme.button("ЗАКРЫТЬ  ×")
	close_btn.pressed.connect(_toggle_help)
	head.add_child(close_btn)
	pv.add_child(head)
	pv.add_child(UITheme.separator())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.text = HELP_TEXT
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.add_theme_font_override("normal_font", UITheme.mono_font())
	rtl.add_theme_font_override("mono_font", UITheme.mono_font())
	rtl.add_theme_font_size_override("normal_font_size", 12)
	rtl.add_theme_color_override("default_color", UITheme.TEXT)
	scroll.add_child(rtl)
	pv.add_child(UITheme.label("F1 или Esc — закрыть · F11 — полный экран", 9, UITheme.FAINT))
	center.add_child(panel)


func _build_dialogs() -> void:
	_save_dialog = FileDialog.new()
	_save_dialog.title = "Сохранить проект чипа"
	_save_dialog.access = FileDialog.ACCESS_USERDATA
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.filters = PackedStringArray(["*.json ; Chip Architect project"])
	_save_dialog.current_file = "chip_project.json"
	_save_dialog.theme = theme
	_save_dialog.file_selected.connect(_on_save_path)
	add_child(_save_dialog)

	_load_dialog = FileDialog.new()
	_load_dialog.title = "Загрузить проект чипа"
	_load_dialog.access = FileDialog.ACCESS_USERDATA
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.filters = PackedStringArray(["*.json ; Chip Architect project"])
	_load_dialog.theme = theme
	_load_dialog.file_selected.connect(_on_load_path)
	add_child(_load_dialog)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Новый проект"
	_confirm_dialog.dialog_text = "Очистить плату? Код программы останется."
	_confirm_dialog.ok_button_text = "Очистить"
	_confirm_dialog.cancel_button_text = "Отмена"
	_confirm_dialog.theme = theme
	_confirm_dialog.confirmed.connect(_do_new_board)
	add_child(_confirm_dialog)


# ---------------------------------------------------------------------------
# Действия
# ---------------------------------------------------------------------------

func _on_run() -> void:
	if ide.get_code().strip_edges() == "":
		_switch_tab("program")
		_set_status("Программа пуста — напишите код или выберите пример", "warn")
		return
	var parser := ChipScriptParser.new()
	var program := parser.parse(ide.get_code())
	ide.show_compile_result(program)
	if not program.is_valid():
		_switch_tab("program")
		_set_status("Ошибка компиляции: строка %d" % int(program.errors[0].get("line", 0)), "error")
		return

	_refresh_stats()
	ide.clear_console()
	_console_seq = 0
	_last_error = ""
	var ok := runtime.begin(program, stats)
	_flush_console()
	_update_run_buttons()
	if not ok:
		_switch_tab("program")
		ide.log_system("Старт не удался: %s" % runtime.error_message, UITheme.ERROR)
		_set_status("Программа не запустилась — смотрите консоль", "error")
		return
	_switch_tab("output")
	ide.log_system("RUN · %.0f FPS · %d шагов/кадр · бюджет чипа" % [
		stats.fps_limit, stats.steps_budget], UITheme.ACCENT)
	_set_status("Чип запущен · %.0f FPS · %d шагов/кадр" % [stats.fps_limit, stats.steps_budget],
		"ok")


func _on_stop() -> void:
	runtime.stop()
	_update_run_buttons()
	ide.log_system("STOP · программа остановлена", UITheme.WARN)
	_set_status("Остановлено", "warn")


func _on_restart() -> void:
	if runtime.vm == null:
		_on_run()
		return
	ide.clear_console()
	_console_seq = 0
	_last_error = ""
	runtime.restart()
	_flush_console()
	_update_run_buttons()
	_switch_tab("output")
	_set_status("Программа перезапущена", "ok")


func _on_check() -> void:
	var program := ChipScriptParser.new().parse(ide.get_code())
	ide.show_compile_result(program)
	if program.is_valid():
		_set_status("Компиляция OK", "ok")
	else:
		_set_status("Ошибка компиляции", "error")


func _on_example_requested(example_name: String, code: String) -> void:
	ide.set_code(code)
	_set_status("Пример: %s" % example_name, "info")
	_switch_tab("program")


func _on_demo_pressed() -> void:
	runtime.stop()
	var demo := DemoProjects.demo_board()
	board.from_dict(demo.to_dict())
	ide.set_code(DemoProjects.starter_code())
	_refresh_stats()
	if chip_view.field != null:
		chip_view.field.focus_bounds()
	_update_run_buttons()
	_set_status("Демо-чип загружен · нажмите RUN", "ok")


func _on_new_pressed() -> void:
	_confirm_dialog.popup_centered(Vector2i(420, 180))


func _do_new_board() -> void:
	runtime.stop()
	board.clear()
	_refresh_stats()
	if chip_view.field != null:
		chip_view.field.focus_bounds()
	_update_run_buttons()
	_set_status("Плата очищена · добавьте компоненты из палитры", "info")


func _toggle_fullscreen() -> void:
	if not _is_fullscreen:
		_is_fullscreen = true
		output.reparent(_fullscreen_content, false)
		output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		output.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_fullscreen_layer.visible = true
		output.set_fullscreen_state(true)
		_set_status("Полный экран · F11 / Esc — выйти", "info")
	else:
		_is_fullscreen = false
		output.reparent(_output_page, false)
		output.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_fullscreen_layer.visible = false
		output.set_fullscreen_state(false)
		_set_status("Обычный режим", "info")
	layout_screen_deferred()


func layout_screen_deferred() -> void:
	await get_tree().process_frame
	if output != null:
		output.relayout()


func _toggle_help() -> void:
	_help_visible = not _help_visible
	_help_overlay.visible = _help_visible
	if output != null:
		output.set_input_blocked(_help_visible)
	if _help_visible:
		_help_overlay.move_to_front()


# ---------------------------------------------------------------------------
# Симуляция и метрики
# ---------------------------------------------------------------------------

func _on_board_edited() -> void:
	_refresh_stats()


func _on_selection_changed(comp: Dictionary) -> void:
	if comp.is_empty():
		return
	var d := ComponentLibrary.get_def(String(comp.get("def_id", "")))
	if d != null:
		_set_status("%s · %s" % [d.display_name, d.description], "info")


func _refresh_stats() -> void:
	if board == null:
		return
	stats = ChipEvaluator.evaluate(board)
	if stats == null:
		return
	chip_view.set_validation(stats)
	chip_view.set_issues(stats.node_issues)
	output.set_quality(stats.quality)
	output.refresh(stats, runtime.get_metrics())
	runtime.apply_stats(stats)
	if ide != null:
		ide.set_chip_info("Чип: %.0f compute · %.0f FPS · %d шагов/кадр" % [
			stats.compute_effective, stats.fps_limit, stats.steps_budget])


func _on_metrics_changed(data: Dictionary) -> void:
	if stats == null:
		return
	output.refresh(stats, data)
	var running := bool(data.get("running", false))
	if running != _last_running:
		_last_running = running
		_update_run_buttons()
	var err := String(data.get("error", ""))
	if err != "" and err != _last_error:
		_last_error = err
		ide.log_system("Ошибка программы: %s" % err, UITheme.ERROR)
		_set_status("Программа упала — смотрите консоль", "error")
		_switch_tab("program")


func _update_run_buttons() -> void:
	if _run_btn != null:
		_run_btn.text = "↻ RUN" if runtime.running else "▶ RUN"
	if _stop_btn != null:
		_stop_btn.disabled = not runtime.running


func _flush_console() -> void:
	if runtime == null or runtime.vm == null or ide == null:
		return
	var lines := runtime.vm.console_lines
	var total := runtime.vm.console_total
	if total <= _console_seq:
		return
	var new_count := total - _console_seq
	var start := maxi(0, lines.size() - new_count)
	for i in range(start, lines.size()):
		ide.log_line(String(lines[i]), UITheme.TEXT)
	_console_seq = total


func _process(delta: float) -> void:
	_console_timer += delta
	if _console_timer > 0.12:
		_console_timer = 0.0
		_flush_console()
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0 and _status_label != null:
			_status_label.text = DEFAULT_STATUS
			_status_label.add_theme_color_override("font_color", UITheme.FAINT)


func _set_status(text: String, kind: String = "info") -> void:
	if _status_label == null:
		return
	_status_label.text = text
	var color := UITheme.DIM
	match kind:
		"ok":
			color = UITheme.ACCENT
		"error":
			color = UITheme.ERROR
		"warn":
			color = UITheme.WARN
		"info":
			color = UITheme.CYAN
	_status_label.add_theme_color_override("font_color", color)
	_status_timer = 7.0


# ---------------------------------------------------------------------------
# Сохранение / загрузка
# ---------------------------------------------------------------------------

func _open_save_dialog() -> void:
	_save_dialog.popup_centered_ratio(0.55)


func _open_load_dialog() -> void:
	_load_dialog.popup_centered_ratio(0.55)


func _on_save_path(path: String) -> void:
	if not path.ends_with(".json"):
		path += ".json"
	var data := {
		"format": "chip_architect",
		"version": 1,
		"name": "My chip",
		"saved_at": Time.get_datetime_string_from_system(),
		"board": board.to_dict(),
		"code": ide.get_code(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Не удалось сохранить: %s" % error_string(FileAccess.get_open_error()), "error")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_set_status("Сохранено: %s" % path.get_file(), "ok")
	ide.log_system("Проект сохранён: %s" % ProjectSettings.globalize_path(path), UITheme.OK)


func _on_load_path(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("Не удалось открыть файл", "error")
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_status("Некорректный JSON", "error")
		return
	var data: Dictionary = parsed
	if not data.has("board") or not data.has("code"):
		_set_status("В файле нет схемы или кода", "error")
		return
	runtime.stop()
	board.from_dict(data["board"])
	ide.set_code(String(data["code"]))
	_refresh_stats()
	if chip_view.field != null:
		chip_view.field.focus_bounds()
	_update_run_buttons()
	_set_status("Загружено: %s" % path.get_file(), "ok")
	ide.log_system("Проект загружен: %s" % ProjectSettings.globalize_path(path), UITheme.OK)


# ---------------------------------------------------------------------------
# Горячие клавиши
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	if key.keycode == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if key.ctrl_pressed and key.keycode == KEY_S:
		_open_save_dialog()
		get_viewport().set_input_as_handled()
		return
	if key.ctrl_pressed and key.keycode == KEY_O:
		_open_load_dialog()
		get_viewport().set_input_as_handled()
		return
	if key.ctrl_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
		_on_run()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_F5:
		_on_run()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_F1:
		_toggle_help()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_ESCAPE and _help_visible:
		_toggle_help()
		get_viewport().set_input_as_handled()
