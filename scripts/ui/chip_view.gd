class_name ChipView
extends VBoxContainer
## Левая часть интерфейса: палитра компонентов, бесконечное поле и валидация.

signal status(text: String, kind: String)
signal board_edited
signal selection_changed(comp: Dictionary)

var field: ChipField = null

var _palette_buttons: Dictionary = {}
var _selected_def_id := ""
var _palette_hint: Label
var _selected_label: Label
var _zoom_label: Label
var _validation: RichTextLabel
var _validation_state: Label
var _validation_summary: Label
var _field_container: ChipDropArea
var _sub_viewport: SubViewport
var _stats: ChipEvaluator.Stats = null
var _zoom_timer := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build_palette()
	_build_field()
	_build_validation()
	set_process(true)
	_fill_palette()


func _input(event: InputEvent) -> void:
	# Пока мышь над полем, горячие клавиши поля работают даже если фокус
	# остался на кнопке палитры. Текстовый ввод в IDE не перехватываем.
	if not (event is InputEventKey) or field == null or _field_container == null:
		return
	if _field_container.has_focus() or not _field_container.is_visible_in_tree():
		return
	if not _field_container.get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is TextEdit or focus_owner is LineEdit:
		return
	if field.handle_key_event(event):
		get_viewport().set_input_as_handled()


func attach_board(board: ChipBoard) -> void:
	if field != null:
		field.attach_board(board)


func current_def_id() -> String:
	return _selected_def_id


# ---------------------------------------------------------------------------
# Палитра
# ---------------------------------------------------------------------------

func _build_palette() -> void:
	var frame := UITheme.panel(UITheme.PANEL, UITheme.LINE, 8)
	frame.custom_minimum_size = Vector2(0, 116)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	frame.add_child(margin)
	var box := UITheme.vbox(6)
	margin.add_child(box)

	var head := UITheme.hbox(8)
	head.add_child(UITheme.heading("ПАЛИТРА КОМПОНЕНТОВ", UITheme.ACCENT))
	var count := UITheme.label("%d шт." % ComponentLibrary.all().size(), 9, UITheme.FAINT)
	head.add_child(count)
	head.add_child(UITheme.spacer())
	head.add_child(UITheme.label("клик — выбрать · Esc — отмена", 9, UITheme.FAINT))
	box.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 64)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UITheme.hbox(6)
	row.name = "Row"
	scroll.add_child(row)
	box.add_child(scroll)
	_palette_row = row

	_palette_hint = UITheme.label("Выберите компонент, чтобы поставить его на поле.", 9,
		UITheme.FAINT)
	_palette_hint.clip_text = true
	box.add_child(_palette_hint)
	add_child(frame)


var _palette_row: HBoxContainer


func _fill_palette() -> void:
	for def in ComponentLibrary.all():
		var b := PaletteButton.new()
		b.def_id = def.id
		b.def_color = def.color
		b.def_name = def.display_name
		b.custom_minimum_size = Vector2(136, 58)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = def.tooltip_text()
		var m := MarginContainer.new()
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_theme_constant_override("margin_left", 10)
		m.add_theme_constant_override("margin_right", 6)
		m.add_theme_constant_override("margin_top", 5)
		m.add_theme_constant_override("margin_bottom", 4)
		var vb := UITheme.vbox(1)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := UITheme.label(def.display_name, 11, UITheme.TEXT)
		name_label.clip_text = true
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var stats_label := UITheme.label(_palette_stats(def), 9, def.color.lightened(0.55))
		stats_label.clip_text = true
		stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(name_label)
		vb.add_child(stats_label)
		m.add_child(vb)
		b.add_child(m)
		b.pressed.connect(_on_palette_pressed.bind(def.id))
		_palette_row.add_child(b)
		_palette_buttons[def.id] = b
		_style_palette_button(b, def, false)


func _palette_stats(def: ComponentDef) -> String:
	var parts := PackedStringArray()
	if def.compute > 0.0:
		parts.append("%d compute" % int(def.compute))
	if def.bandwidth > 0.0:
		parts.append("%d BW" % int(def.bandwidth))
	if def.cooling > 0.0:
		parts.append("%d cool" % int(def.cooling))
	if def.power_supply > 0.0:
		parts.append("+%d W" % int(def.power_supply))
	if def.power_draw > 0.0 and def.compute <= 0.0 and def.cooling <= 0.0:
		parts.append("%d W" % int(def.power_draw))
	if parts.is_empty():
		parts.append(ComponentDef.kind_name(def.category))
	var out := PackedStringArray()
	for i in mini(2, parts.size()):
		out.append(parts[i])
	return " · ".join(out)


func _style_palette_button(button: Button, def: ComponentDef, selected: bool) -> void:
	var bg := def.color.darkened(0.62)
	var border := def.color.darkened(0.2)
	if selected:
		bg = def.color.darkened(0.42)
		border = UITheme.ACCENT
	var normal := UITheme.box(bg, border, 6, 1)
	normal.border_width_left = 4
	var hover := UITheme.box(bg.lightened(0.08), def.color.lightened(0.1), 6, 1)
	hover.border_width_left = 4
	var pressed := UITheme.box(bg.lightened(0.03), UITheme.ACCENT, 6, 1)
	pressed.border_width_left = 4
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _on_palette_pressed(def_id: String) -> void:
	if _selected_def_id == def_id:
		_selected_def_id = ""
	else:
		_selected_def_id = def_id
	_refresh_selection_styles()
	if field != null:
		field.set_placing(_selected_def_id)
	if _selected_def_id != "":
		var def := ComponentLibrary.get_def(_selected_def_id)
		_palette_hint.text = "%s — %s" % [def.display_name, def.description]
		_palette_hint.add_theme_color_override("font_color", def.color.lightened(0.45))
	else:
		_palette_hint.text = "Выберите компонент, чтобы поставить его на поле."
		_palette_hint.add_theme_color_override("font_color", UITheme.FAINT)


func _refresh_selection_styles() -> void:
	for def_id in _palette_buttons:
		var def := ComponentLibrary.get_def(def_id)
		_style_palette_button(_palette_buttons[def_id], def, def_id == _selected_def_id)


# ---------------------------------------------------------------------------
# Поле
# ---------------------------------------------------------------------------

func _build_field() -> void:
	var frame := UITheme.panel(UITheme.BG_2, UITheme.LINE, 8)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	frame.add_child(margin)
	var box := UITheme.vbox(6)
	margin.add_child(box)

	var head := UITheme.hbox(8)
	head.add_child(UITheme.heading("ПОЛЕ ЧИПА", UITheme.CYAN))
	_selected_label = UITheme.label("ничего не выбрано", 10, UITheme.FAINT)
	_selected_label.clip_text = true
	head.add_child(_selected_label)
	head.add_child(UITheme.spacer())
	_zoom_label = UITheme.label("zoom 80%", 9, UITheme.FAINT)
	head.add_child(_zoom_label)
	var zoom_out := UITheme.button("−")
	zoom_out.custom_minimum_size = Vector2(28, 24)
	zoom_out.add_theme_font_size_override("font_size", 14)
	zoom_out.tooltip_text = "Уменьшить"
	zoom_out.pressed.connect(func() -> void:
		if field != null:
			field.zoom_step(1.0 / 1.2)
	)
	var zoom_in := UITheme.button("+")
	zoom_in.custom_minimum_size = Vector2(28, 24)
	zoom_in.add_theme_font_size_override("font_size", 14)
	zoom_in.tooltip_text = "Увеличить"
	zoom_in.pressed.connect(func() -> void:
		if field != null:
			field.zoom_step(1.2)
	)
	var fit := UITheme.button("FIT")
	fit.custom_minimum_size = Vector2(40, 24)
	fit.add_theme_font_size_override("font_size", 9)
	fit.tooltip_text = "Показать всю плату (F)"
	fit.pressed.connect(func() -> void:
		if field != null:
			field.focus_bounds()
	)
	head.add_child(zoom_out)
	head.add_child(zoom_in)
	head.add_child(fit)
	box.add_child(head)

	_field_container = ChipDropArea.new()
	_field_container.stretch = true
	_field_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_field_container.custom_minimum_size = Vector2(0, 280)
	_field_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_field_container.focus_mode = Control.FOCUS_ALL
	box.add_child(_field_container)

	_sub_viewport = SubViewport.new()
	_sub_viewport.size = Vector2i(900, 620)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.handle_input_locally = true
	_sub_viewport.gui_disable_input = false
	_field_container.add_child(_sub_viewport)

	var field_scene: PackedScene = load("res://scenes/chip_field.tscn")
	field = field_scene.instantiate()
	_sub_viewport.add_child(field)
	field.status.connect(_on_field_status)
	field.board_edited.connect(func() -> void: board_edited.emit())
	field.selection_changed.connect(_on_field_selection)
	field.placing_changed.connect(_on_field_placing)

	_field_container.def_dropped.connect(_on_def_dropped)
	_field_container.mouse_entered.connect(func() -> void:
		if field != null:
			field.set_mouse_active(true)
	)
	_field_container.mouse_exited.connect(func() -> void:
		if field != null:
			field.set_mouse_active(false)
	)

	var hint := UITheme.label(
		"ЛКМ — ставить/тащить · порт → порт — дорожка · ПКМ/СКМ — панорама · колесо — зум · WASD — камера · R — поворот · Del — удалить",
		9, UITheme.FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	add_child(frame)


func _on_def_dropped(def_id: String, local_pos: Vector2) -> void:
	if field == null or _sub_viewport == null or _field_container.size.x <= 1.0:
		return
	var factor := Vector2(_sub_viewport.size) / _field_container.size
	field.place_def_at_screen(def_id, local_pos * factor)


func _on_field_status(text: String, kind: String) -> void:
	status.emit(text, kind)


func _on_field_selection(comp: Dictionary) -> void:
	if comp.is_empty():
		_selected_label.text = "ничего не выбрано"
		_selected_label.add_theme_color_override("font_color", UITheme.FAINT)
	else:
		var d := ComponentLibrary.get_def(String(comp.get("def_id", "")))
		if d != null:
			_selected_label.text = "%s · %d°" % [d.display_name, int(comp.get("rot", 0)) * 90]
			_selected_label.add_theme_color_override("font_color", d.color.lightened(0.55))
	selection_changed.emit(comp)


func _on_field_placing(def_id: String) -> void:
	if def_id == _selected_def_id:
		return
	_selected_def_id = def_id
	_refresh_selection_styles()
	if def_id == "":
		_palette_hint.text = "Выберите компонент, чтобы поставить его на поле."
		_palette_hint.add_theme_color_override("font_color", UITheme.FAINT)


# ---------------------------------------------------------------------------
# Валидация
# ---------------------------------------------------------------------------

func _build_validation() -> void:
	var frame := UITheme.panel(UITheme.PANEL, UITheme.LINE, 8)
	frame.custom_minimum_size = Vector2(0, 96)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	frame.add_child(margin)
	var box := UITheme.vbox(3)
	margin.add_child(box)

	var head := UITheme.hbox(6)
	head.add_child(UITheme.heading("ВАЛИДАЦИЯ СХЕМЫ", UITheme.POWER))
	_validation_state = UITheme.label("—", 10, UITheme.FAINT)
	head.add_child(_validation_state)
	head.add_child(UITheme.spacer())
	_validation_summary = UITheme.label("", 9, UITheme.FAINT)
	head.add_child(_validation_summary)
	box.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_validation = RichTextLabel.new()
	_validation.bbcode_enabled = false
	_validation.fit_content = true
	_validation.scroll_active = false
	_validation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_validation.add_theme_font_override("normal_font", UITheme.mono_font())
	_validation.add_theme_font_size_override("normal_font_size", 10)
	scroll.add_child(_validation)
	add_child(frame)


func set_validation(stats: ChipEvaluator.Stats) -> void:
	_stats = stats
	if _validation == null:
		return
	_validation.clear()
	if stats == null:
		return
	for e in stats.errors:
		_validation.push_color(UITheme.ERROR)
		_validation.add_text("✕  " + String(e) + "\n")
		_validation.pop()
	for w in stats.warnings:
		_validation.push_color(UITheme.WARN)
		_validation.add_text("!  " + String(w) + "\n")
		_validation.pop()
	if stats.errors.is_empty() and stats.warnings.is_empty():
		_validation.push_color(UITheme.OK)
		_validation.add_text("✓  Схема в порядке: питание, шина, видео и охлаждение на месте.\n")
		_validation.pop()
		_validation.push_color(UITheme.FAINT)
		_validation.add_text("   Нажмите RUN — программа чипа появится на экране вывода.")
		_validation.pop()

	if not stats.errors.is_empty():
		_validation_state.text = "ОШИБКИ: %d" % stats.errors.size()
		_validation_state.add_theme_color_override("font_color", UITheme.ERROR)
	elif not stats.warnings.is_empty():
		_validation_state.text = "ВНИМАНИЕ: %d" % stats.warnings.size()
		_validation_state.add_theme_color_override("font_color", UITheme.WARN)
	else:
		_validation_state.text = "ЧИП ГОТОВ"
		_validation_state.add_theme_color_override("font_color", UITheme.OK)

	_validation_summary.text = "%.0f/%.0f Вт · %.0f FPS · %d шагов" % [
		stats.power_load, stats.power_capacity, stats.fps_limit, stats.steps_budget]


# ---------------------------------------------------------------------------
# Прочее
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_zoom_timer += delta
	if _zoom_timer >= 0.2 and field != null:
		_zoom_timer = 0.0
		_zoom_label.text = "zoom %d%%" % int(round(field.camera.zoom.x * 100.0))


func flash_status(text: String, kind: String) -> void:
	status.emit(text, kind)
