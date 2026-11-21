class_name ChipOverlay
extends Node2D
## Слой поверх компонентов: подсветка совместимых портов, призрак
## устанавливаемого компонента и превью дорожки. Рисует ChipField.

var field: Node2D = null


func _draw() -> void:
	if field != null and field.has_method("draw_overlay"):
		field.draw_overlay(self)
