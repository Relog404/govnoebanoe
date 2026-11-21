class_name MetricBar
extends Control
## Сегментированная полоска метрики в стиле PCB-индикатора.

var title := ""
var value := 0.0
var value_text := ""
var accent: Color = UITheme.ACCENT
var warning := false

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(0, 38)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(new_title: String, color: Color) -> void:
	title = new_title
	accent = color
	queue_redraw()


func set_metric(new_value: float, text: String, is_warning: bool = false) -> void:
	value = clampf(new_value, 0.0, 1.0)
	value_text = text
	warning = is_warning
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var font_size := 9
	var hot := UITheme.ERROR if warning else accent
	draw_string(_font, Vector2(0, font_size + 1), title, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, UITheme.FAINT)
	var text_size := _font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(_font, Vector2(w - text_size, 11), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		hot)
	var bar_y := 18.0
	var bar_h := 9.0
	var segments := maxi(10, int(w / 9.0))
	var gap := 2.0
	var seg_w := (w - gap * float(segments - 1)) / float(segments)
	var filled := int(round(value * float(segments)))
	for i in segments:
		var x := i * (seg_w + gap)
		var rect := Rect2(x, bar_y, seg_w, bar_h)
		var lit := i < filled
		var col := hot if lit else Color(0.13, 0.22, 0.23, 0.8)
		if lit and warning:
			var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 120.0)
			col = Color(hot.r, hot.g, hot.b, pulse)
		draw_rect(rect, col)
	# Шкала-насечки.
	draw_line(Vector2(0, bar_y + bar_h + 2), Vector2(w, bar_y + bar_h + 2),
		Color(0.16, 0.28, 0.29, 0.5), 1.0)
