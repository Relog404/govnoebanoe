extends Button

# Элемент библиотеки: клик — взять в руки, drag&drop — перенести на плату.
var scene_path := ""

func _init(label_text := "", path := "") -> void:
	scene_path = path
	text = label_text
	tooltip_text = path.get_file()
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = text
	preview.add_theme_color_override("font_color", Color(0.62, 1.0, 0.83))
	set_drag_preview(preview)
	return {"scene": scene_path}
