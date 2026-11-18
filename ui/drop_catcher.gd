extends Control

# Полноэкранный приёмник drop из палитры: перетащил деталь — она в руке, ставишь ЛКМ.
signal dropped(scene_path: String, mouse: Vector2)

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("scene")

func _drop_data(at: Vector2, data: Variant) -> void:
	dropped.emit(str(data.scene), at)
