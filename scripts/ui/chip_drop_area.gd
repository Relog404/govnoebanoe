class_name ChipDropArea
extends SubViewportContainer
## Контейнер поля чипа, принимающий drag&drop из палитры.
## Позиция в локальных координатах контейнера передаётся в ChipField.

signal def_dropped(def_id: String, local_pos: Vector2)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and String(data.get("kind", "")) == "component_def"


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	def_dropped.emit(String(data.get("def_id", "")), at_position)
