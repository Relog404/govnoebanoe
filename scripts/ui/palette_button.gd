class_name PaletteButton
extends Button
## Карточка компонента в палитре. Помимо клика её можно перетащить
## прямо на поле чипа — ChipDropArea примет данные и поставит компонент.

var def_id := ""
var def_color := Color(0.3, 0.7, 0.6)
var def_name := ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if def_id == "":
		return null
	# Превью перетаскиваемой карточки.
	var preview := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = def_color.darkened(0.45)
	sb.border_color = def_color.lightened(0.2)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	preview.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = def_name
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color("#eafff6"))
	preview.add_child(l)
	set_drag_preview(preview)
	return {"kind": "component_def", "def_id": def_id}
