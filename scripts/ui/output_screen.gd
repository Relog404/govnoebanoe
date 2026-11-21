class_name OutputScreen
extends VBoxContainer
## Экран вывода: живой SubViewport с результатом программы чипа,
## метрики, захват мыши и клавиатуры, полноэкранный режим.

signal run_requested
signal stop_requested
signal restart_requested
signal fullscreen_toggle

var surface: ChipDisplaySurface = null

var _sub_viewport: SubViewport
var _texture_rect: TextureRect
var _screen_area: Control
var _screen_border: Panel
var _material: ShaderMaterial

var _fps_label: Label
var _fps_sub: Label
var _status_pill: PanelContainer
var _status_label: Label
var _status_dot: Label
var _fullscreen_btn: Button
var _details: Label
var _quality_label: Label

var _bar_power: MetricBar
var _bar_temp: MetricBar
var _bar_stab: MetricBar
var _bar_mem: MetricBar

var _stats: ChipEvaluator.Stats = null
var _hover_area := false
var _fullscreen := false


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build_screen()
	_build_header()
	_build_metrics()
	_layout_screen.call_deferred()


# ---------------------------------------------------------------------------
# Построение
# ---------------------------------------------------------------------------

func _build_screen() -> void:
	var frame := UITheme.panel(Color("#05090b"), Color("#1e3a3a"), 8)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size = Vector2(0, 210)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	frame.add_child(margin)

	_screen_area = Control.new()
	_screen_area.clip_contents = true
	_screen_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_screen_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_area.resized.connect(_layout_screen)
	margin.add_child(_screen_area)

	_screen_border = Panel.new()
	_screen_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_border.add_theme_stylebox_override("panel",
		UITheme.box(Color(0, 0, 0, 0), Color("#2c5d55"), 3, 1))
	_screen_area.add_child(_screen_border)

	_texture_rect = TextureRect.new()
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen_area.add_child(_texture_rect)

	_sub_viewport = SubViewport.new()
	_sub_viewport.size = Vector2i(320, 180)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.transparent_bg = false
	_sub_viewport.handle_input_locally = true
	_sub_viewport.gui_disable_input = false
	add_child(_sub_viewport)

	surface = ChipDisplaySurface.new()
	_sub_viewport.add_child(surface)
	_texture_rect.texture = _sub_viewport.get_texture()

	_material = ShaderMaterial.new()
	var shader: Shader = load("res://shaders/glitch.gdshader")
	if shader != null:
		_material.shader = shader
		_material.set_shader_parameter("glitch", 0.0)
		_texture_rect.material = _material

	add_child(frame)


func _build_header() -> void:
	var head := UITheme.hbox(8)
	head.add_child(UITheme.heading("ЭКРАН ВЫВОДА", UITheme.VIDEO))
	_status_dot = UITheme.dot(UITheme.FAINT, 9)
	head.add_child(_status_dot)
	_status_pill = UITheme.pill("ОСТАНОВЛЕН", UITheme.DIM)
	_status_label = _status_pill.get_child(0) as Label
	head.add_child(_status_pill)
	head.add_child(UITheme.spacer())

	var fps_box := UITheme.vbox(0)
	_fps_label = UITheme.label("0", 22, UITheme.ACCENT)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_sub = UITheme.label("FPS · цель 0", 9, UITheme.FAINT)
	_fps_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_box.add_child(_fps_label)
	fps_box.add_child(_fps_sub)
	head.add_child(fps_box)

	_fullscreen_btn = UITheme.button("РАЗВЕРНУТЬ")
	_fullscreen_btn.tooltip_text = "Полный экран (F11). Esc — выйти."
	_fullscreen_btn.add_theme_font_size_override("font_size", 10)
	_fullscreen_btn.pressed.connect(func() -> void: fullscreen_toggle.emit())
	head.add_child(_fullscreen_btn)

	# Заголовок всегда сверху, под ним — экран.
	add_child(head)
	move_child(head, 0)


func _build_metrics() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	_bar_power = MetricBar.new()
	_bar_power.configure("ПИТАНИЕ", UITheme.POWER)
	_bar_temp = MetricBar.new()
	_bar_temp.configure("ТЕМПЕРАТУРА", UITheme.CYAN)
	_bar_stab = MetricBar.new()
	_bar_stab.configure("СТАБИЛЬНОСТЬ", UITheme.ACCENT)
	_bar_mem = MetricBar.new()
	_bar_mem.configure("ПАМЯТЬ", UITheme.VIDEO)
	for bar in [_bar_power, _bar_temp, _bar_stab, _bar_mem]:
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(bar)
	add_child(grid)

	var controls := UITheme.hbox(6)
	var run_btn := UITheme.button("▶ RUN", "primary")
	run_btn.tooltip_text = "Запустить программу на чипе (F5)"
	run_btn.pressed.connect(func() -> void: run_requested.emit())
	var stop_btn := UITheme.button("■ STOP", "danger")
	stop_btn.tooltip_text = "Остановить программу"
	stop_btn.pressed.connect(func() -> void: stop_requested.emit())
	var restart_btn := UITheme.button("↻ СБРОС")
	restart_btn.tooltip_text = "Перезапустить программу с начала"
	restart_btn.pressed.connect(func() -> void: restart_requested.emit())
	controls.add_child(run_btn)
	controls.add_child(stop_btn)
	controls.add_child(restart_btn)
	controls.add_child(UITheme.spacer())
	_quality_label = UITheme.label("рендер 320×180", 10, UITheme.FAINT)
	controls.add_child(_quality_label)
	add_child(controls)

	_details = UITheme.label("—", 10, UITheme.FAINT)
	add_child(_details)

	var hint := UITheme.label(
		"Наведите курсор на экран — все клавиши и мышь уходят в программу чипа. F11 — на весь экран.",
		9, UITheme.FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)


# ---------------------------------------------------------------------------
# Геометрия экрана
# ---------------------------------------------------------------------------

func _layout_screen() -> void:
	if _screen_area == null or _texture_rect == null:
		return
	var avail := _screen_area.size
	if avail.x < 8.0 or avail.y < 8.0:
		return
	var aspect := 16.0 / 9.0
	var w := avail.x
	var h := w / aspect
	if h > avail.y:
		h = avail.y
		w = h * aspect
	var rect := Rect2(Vector2((avail.x - w) * 0.5, (avail.y - h) * 0.5), Vector2(w, h))
	_texture_rect.position = rect.position
	_texture_rect.size = rect.size
	_screen_border.position = rect.position - Vector2(2, 2)
	_screen_border.size = rect.size + Vector2(4, 4)


func relayout() -> void:
	_layout_screen.call_deferred()


func set_quality(scale: float) -> void:
	if _sub_viewport == null:
		return
	var w := int(round(320.0 * scale))
	var h := int(round(w * 9.0 / 16.0))
	w = maxi(160, w)
	h = maxi(90, h)
	if _sub_viewport.size != Vector2i(w, h):
		_sub_viewport.size = Vector2i(w, h)
	if _quality_label != null:
		_quality_label.text = "рендер %d×%d" % [w, h]


func set_fullscreen_state(value: bool) -> void:
	_fullscreen = value
	if _fullscreen_btn != null:
		_fullscreen_btn.text = "СВЕРНУТЬ" if value else "РАЗВЕРНУТЬ"


# ---------------------------------------------------------------------------
# Ввод: мышь и все клавиши внутрь SubViewport
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or surface == null:
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_F11:
			fullscreen_toggle.emit()
			get_viewport().set_input_as_handled()
			return
		if key.pressed and key.keycode == KEY_ESCAPE and _fullscreen:
			fullscreen_toggle.emit()
			get_viewport().set_input_as_handled()
			return
		if not (_hover_area or _fullscreen):
			# Мышь могла оказаться над экраном без события движения.
			_hover_area = _screen_area.get_global_rect().has_point(
				get_viewport().get_mouse_position())
			if not _hover_area:
				return
		_sub_viewport.push_input(key.duplicate(), true)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var over_area := _screen_area.get_global_rect().has_point(motion.position)
		if over_area != _hover_area:
			_hover_area = over_area
			if not over_area:
				surface.reset_input()
		if _texture_rect.get_global_rect().has_point(motion.position):
			_forward_mouse(motion)
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _texture_rect.get_global_rect().has_point(mb.position):
			_hover_area = _screen_area.get_global_rect().has_point(mb.position)
			_forward_mouse(mb)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventPanGesture or event is InputEventMagnifyGesture:
		if _hover_area or _fullscreen:
			_sub_viewport.push_input(event.duplicate(), true)
			get_viewport().set_input_as_handled()


func _forward_mouse(event: InputEventMouse) -> void:
	var rect := _texture_rect.get_global_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var local := (event.position - rect.position) / rect.size * Vector2(_sub_viewport.size)
	local.x = clampf(local.x, 0.0, float(_sub_viewport.size.x))
	local.y = clampf(local.y, 0.0, float(_sub_viewport.size.y))
	var dup = event.duplicate()
	dup.position = local
	dup.global_position = local
	_sub_viewport.push_input(dup, true)


# ---------------------------------------------------------------------------
# Метрики
# ---------------------------------------------------------------------------

func refresh(stats: ChipEvaluator.Stats, metrics: Dictionary) -> void:
	if stats == null:
		return
	_stats = stats
	var running := bool(metrics.get("running", false))
	var fps: float = metrics.get("fps", 0.0)
	var target: float = metrics.get("target_fps", stats.fps_limit)
	var temp: float = metrics.get("temperature", 32.0)
	var glitch: float = metrics.get("glitch", 0.0)
	var err := String(metrics.get("error", ""))

	_fps_label.text = str(int(round(fps)))
	_fps_label.add_theme_color_override("font_color",
		UITheme.ERROR if temp > 95.0 else UITheme.ACCENT)
	_fps_sub.text = "FPS · цель %d" % int(round(target))

	var power_usage := 0.0
	if stats.power_capacity > 0.0:
		power_usage = clampf(stats.power_load / stats.power_capacity, 0.0, 1.0)
	_bar_power.set_metric(power_usage, "%.0f / %.0f Вт" % [stats.power_load, stats.power_capacity],
		stats.power_satisfaction < 0.99)

	var temp_norm := clampf((temp - 25.0) / 95.0, 0.0, 1.0)
	_bar_temp.set_metric(temp_norm, "%.0f °C" % temp, temp > 88.0)

	_bar_stab.set_metric(stats.stability, "%d %%" % int(round(stats.stability * 100.0)),
		stats.stability < 0.6)

	var mem_usage := 0.0
	if stats.bandwidth_provided > 0.0:
		mem_usage = clampf(stats.bandwidth_demand / stats.bandwidth_provided, 0.0, 1.0)
	_bar_mem.set_metric(mem_usage, "%.0f / %.0f" % [stats.bandwidth_demand,
		stats.bandwidth_provided], stats.bandwidth_satisfaction < 0.9)

	_details.text = "compute %.0f · качество %d%% · бюджет %d шагов · draw calls %d" % [
		stats.compute_effective, int(round(stats.quality * 100.0)), stats.steps_budget,
		int(metrics.get("draw_calls", 0)),
	]

	if _material != null:
		_material.set_shader_parameter("glitch", clampf(glitch, 0.0, 1.0))

	_update_status(stats, running, err)


func _update_status(stats: ChipEvaluator.Stats, running: bool, err: String) -> void:
	var text := "ОСТАНОВЛЕН"
	var color := UITheme.DIM
	if err != "":
		text = "ОШИБКА"
		color = UITheme.ERROR
	elif not stats.can_output():
		text = "НЕТ СИГНАЛА"
		color = UITheme.WARN
	elif running:
		text = "РАБОТАЕТ"
		color = UITheme.ACCENT
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
	var sb := UITheme.box(Color(color.r * 0.12, color.g * 0.12, color.b * 0.12, 0.9),
		Color(color.r, color.g, color.b, 0.35), 20, 1)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	_status_pill.add_theme_stylebox_override("panel", sb)
	_status_dot.add_theme_color_override("font_color", color)
