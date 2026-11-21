class_name ChipComponent
extends Area2D
## Визуальный компонент на плате. Сцена data-driven: внешний вид и порты
## берутся из ComponentDef, позиция — из ChipBoard. Перетаскивание
## инициируется полем (ChipField), которое владеет всей логикой ввода.

const CELL := ChipBoard.CELL

var comp: Dictionary = {}
var def: ComponentDef = null
var is_selected := false
var is_hovered := false
var is_dragging := false
var invalid_drop := false
var hover_port := ""
var issue := ""

var _fan_angle := 0.0
var _fan_accum := 0.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_process(false)
	monitoring = false
	monitorable = false
	input_pickable = false


func setup(new_comp: Dictionary, new_def: ComponentDef) -> void:
	comp = new_comp
	def = new_def
	position = Vector2(comp["cell"]) * CELL
	z_index = 1
	_update_shape()
	if def != null and def.category == "cooling":
		set_process(true)
	queue_redraw()


func _update_shape() -> void:
	if def == null:
		return
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var sz := def.rotated_size(int(comp.get("rot", 0)))
	var rect := RectangleShape2D.new()
	rect.size = Vector2(sz) * CELL - Vector2(8, 8)
	shape_node.shape = rect
	shape_node.position = Vector2(sz) * CELL * 0.5


func comp_id() -> int:
	return int(comp.get("id", -1))


func refresh_from_board() -> void:
	if comp.is_empty():
		return
	position = Vector2(comp["cell"]) * CELL
	_update_shape()
	queue_redraw()


func set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	queue_redraw()


func set_hovered(value: bool) -> void:
	if is_hovered == value:
		return
	is_hovered = value
	queue_redraw()


func set_hover_port(port_name: String) -> void:
	if hover_port == port_name:
		return
	hover_port = port_name
	queue_redraw()


func set_issue(text: String) -> void:
	if issue == text:
		return
	issue = text
	queue_redraw()


func set_dragging(value: bool) -> void:
	is_dragging = value
	queue_redraw()


func set_invalid_drop(value: bool) -> void:
	if invalid_drop == value:
		return
	invalid_drop = value
	queue_redraw()


func _process(delta: float) -> void:
	_fan_accum += delta
	if _fan_accum >= 0.09:
		_fan_accum = 0.0
		_fan_angle = fmod(_fan_angle + 0.55, TAU)
		queue_redraw()


# ---------------------------------------------------------------------------
# Отрисовка
# ---------------------------------------------------------------------------

func _draw() -> void:
	if def == null:
		return
	var sz := def.rotated_size(int(comp.get("rot", 0)))
	var full := Vector2(sz) * CELL
	var inset := 5.0
	var body := Rect2(Vector2(inset, inset), full - Vector2(inset * 2.0, inset * 2.0))

	# Тень и корпус.
	draw_rect(Rect2(Vector2(7, 8), full - Vector2(10, 10)), Color(0, 0, 0, 0.35))
	var base: Color = def.color
	if is_hovered and not is_dragging:
		base = base.lightened(0.12)
	draw_rect(body, base)
	draw_rect(body, base.lightened(0.35), false, 2.0)
	# Внутренняя рамка / текстолит.
	draw_rect(body.grow(-4.0), base.darkened(0.25), false, 1.0)
	_draw_corner_marks(body)

	_draw_category_glyph(body, base)
	_draw_label(body, base)

	# Порты.
	for port in def.ports:
		_draw_port(port, sz)

	if is_selected or is_dragging:
		draw_rect(body.grow(2.0), Color("#39ff88"), false, 2.0)
		_draw_select_marks(body)
	if invalid_drop:
		draw_rect(body, Color(1.0, 0.2, 0.25, 0.28))
		draw_rect(body, Color(1.0, 0.3, 0.35, 0.9), false, 2.0)
	# Значок проблемы компонента (питание/шина/тепло/видео).
	if issue != "":
		draw_rect(body, Color(1.0, 0.25, 0.3, 0.10))
		var badge := Vector2(full.x - 12.0, 12.0)
		draw_circle(badge, 8.5, Color(0.08, 0.02, 0.03, 0.85))
		draw_circle(badge, 7.0, Color(1.0, 0.28, 0.34))
		draw_string(_font, badge + Vector2(-2.0, 4.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.1, 0.02, 0.03))


func _draw_corner_marks(body: Rect2) -> void:
	var c := body.position
	var e := body.end
	var col := Color(1, 1, 1, 0.35)
	var s := 7.0
	draw_line(c, c + Vector2(s, 0), col, 2.0)
	draw_line(c, c + Vector2(0, s), col, 2.0)
	draw_line(Vector2(e.x, c.y), Vector2(e.x - s, c.y), col, 2.0)
	draw_line(Vector2(e.x, c.y), Vector2(e.x, c.y + s), col, 2.0)
	draw_line(Vector2(c.x, e.y), Vector2(c.x + s, e.y), col, 2.0)
	draw_line(Vector2(c.x, e.y), Vector2(c.x, e.y - s), col, 2.0)
	draw_line(e, e - Vector2(s, 0), col, 2.0)
	draw_line(e, e - Vector2(0, s), col, 2.0)


func _draw_select_marks(body: Rect2) -> void:
	var col := Color("#39ff88")
	var b := body.grow(4.0)
	var s := 5.0
	for corner in [b.position, Vector2(b.end.x, b.position.y), Vector2(b.position.x, b.end.y), b.end]:
		draw_rect(Rect2(corner - Vector2(2, 2), Vector2(4, 4)), col)


func _draw_label(body: Rect2, base: Color) -> void:
	var title_col := Color(0.95, 1.0, 0.98, 0.95)
	var small := body.size.x < CELL * 1.5 or body.size.y < CELL * 1.2
	var name := def.display_name
	if small and name.find(" ") > 0:
		name = name.split(" ")[0]
	var font_size := 11 if not small else 9
	var text_y := body.position.y + 6.0
	draw_string(_font, Vector2(body.position.x, text_y + font_size), name,
		HORIZONTAL_ALIGNMENT_CENTER, body.size.x, font_size, title_col)

	if not small:
		var stat := _short_stats()
		if stat != "":
			draw_string(_font, Vector2(body.position.x + 6, body.end.y - 6), stat,
				HORIZONTAL_ALIGNMENT_LEFT, body.size.x - 12, 8, Color(1, 1, 1, 0.55))
	# Цветная полоска категории.
	draw_rect(Rect2(body.position + Vector2(0, 2), Vector2(body.size.x, 2)),
		base.lightened(0.55))


func _short_stats() -> String:
	var parts := PackedStringArray()
	if def.compute > 0.0:
		parts.append("%.0fP" % def.compute)
	if def.bandwidth > 0.0:
		parts.append("%.0fB" % def.bandwidth)
	if def.cooling > 0.0:
		parts.append("%.0fC" % def.cooling)
	if def.power_supply > 0.0:
		parts.append("+%.0fW" % def.power_supply)
	elif def.power_draw > 0.0:
		parts.append("%.0fW" % def.power_draw)
	return " · ".join(parts)


func _draw_category_glyph(body: Rect2, base: Color) -> void:
	var center := body.get_center() + Vector2(0, 2)
	var col := base.lightened(0.55)
	match def.category:
		"compute":
			var s := minf(body.size.x, body.size.y) * 0.26
			draw_rect(Rect2(center - Vector2(s, s), Vector2(s, s) * 2.0), base.darkened(0.35))
			draw_rect(Rect2(center - Vector2(s, s), Vector2(s, s) * 2.0), col, false, 1.0)
			for i in 4:
				var off := -s + i * (s * 2.0 / 3.0)
				draw_line(center + Vector2(off, -s * 1.6), center + Vector2(off, -s), col, 1.0)
				draw_line(center + Vector2(off, s), center + Vector2(off, s * 1.6), col, 1.0)
		"memory":
			for i in 3:
				var y := center.y - 7.0 + i * 6.0
				draw_rect(Rect2(center.x - 16, y, 32, 3), col.darkened(0.2))
		"power":
			for i in 3:
				draw_rect(Rect2(center.x - 13 + i * 10, center.y - 8, 5, 16), col.darkened(0.15))
			draw_rect(Rect2(center.x - 16, center.y + 10, 32, 2), col)
		"cooling":
			draw_arc(center, 15.0, 0, TAU, 32, col, 1.5)
			for i in 4:
				var a := _fan_angle + TAU * i / 4.0
				draw_line(center, center + Vector2(cos(a), sin(a)) * 13.0, col, 2.0)
			draw_circle(center, 3.0, col)
		"io":
			for i in 3:
				var x := center.x - 12 + i * 12
				draw_circle(Vector2(x, center.y), 3.0, col)
				draw_line(Vector2(x, center.y + 5), Vector2(x, center.y + 11), col, 1.0)
		"output":
			var pts := PackedVector2Array([
				center + Vector2(-14, -8), center + Vector2(14, -8),
				center + Vector2(10, 8), center + Vector2(-10, 8),
			])
			draw_colored_polygon(pts, col.darkened(0.3))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), col, 1.0)
		_:
			draw_circle(center, 10.0, col.darkened(0.2))
			draw_circle(center, 6.0, base.darkened(0.3))


func _draw_port(port: Dictionary, sz: Vector2i) -> void:
	var rot := int(comp.get("rot", 0))
	var cell := def.port_cell(port, rot)
	var dir := def.port_dir(port, rot)
	var anchor := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL + Vector2(dir) * (CELL * 0.5)
	var pname := String(port.get("name", ""))
	var kind := String(port.get("kind", ""))
	var col := ComponentDef.kind_color(kind)
	var hovered := pname == hover_port
	var radius := 6.0 if hovered else 4.6
	draw_circle(anchor, radius + 2.0, Color(0, 0, 0, 0.55))
	draw_circle(anchor, radius, col)
	draw_circle(anchor, maxf(1.0, radius - 2.4), Color(0.03, 0.05, 0.06))
	if hovered:
		draw_arc(anchor, radius + 6.0, 0, TAU, 24, col, 1.5)
	# Подпись порта только у больших компонентов и при наведении.
	if hovered and sz.x * sz.y > 1:
		var label := "%s · %s" % [pname, ComponentDef.kind_name(kind)]
		draw_string(_font, anchor + Vector2(8, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			col.lightened(0.2))
