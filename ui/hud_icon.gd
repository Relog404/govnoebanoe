extends Control

# Векторные иконки инструментов: рисуются примитивами, без ассетов.
enum Kind { IRON, TWEEZERS, TESTER, LOUPE, CURSOR }
@export var kind := Kind.IRON
@export var accent := Color("7dffd4")

func _init() -> void:
	custom_minimum_size = Vector2(30, 30)
	tooltip_text = ""

func _draw() -> void:
	var c := accent
	var hot := c.darkened(0.35)
	match kind:
		Kind.IRON:
			# Наконечник → жало → ручка по диагонали.
			draw_line(Vector2(4, 26), Vector2(12.5, 17.5), c, 2.4, true)
			draw_line(Vector2(12, 18.5), Vector2(23.5, 7), hot, 5.2, true)
			draw_circle(Vector2(25.5, 4.8), 2.1, c)
		Kind.TWEEZERS:
			draw_line(Vector2(8.5, 26), Vector2(13.5, 5), c, 2.5, true)
			draw_line(Vector2(21.5, 26), Vector2(16.5, 5), c, 2.5, true)
			draw_line(Vector2(9.6, 20.5), Vector2(20.4, 20.5), hot, 2.0, true)
		Kind.TESTER:
			draw_arc(Vector2(12.5, 12.5), 7.2, 0.35, TAU - 0.35, 40, c, 2.1, true)
			draw_line(Vector2(17.5, 17.5), Vector2(26.5, 26.5), c, 2.6, true)
		Kind.LOUPE:
			draw_arc(Vector2(12.3, 12.3), 6.6, 0, TAU, 40, c, 2.2, true)
			draw_line(Vector2(17.3, 17.3), Vector2(26.2, 26.2), c, 3.1, true)
		Kind.CURSOR:
			draw_colored_polygon(PackedVector2Array([
				Vector2(8.5, 4.5), Vector2(23.5, 14.5), Vector2(16.6, 16.6),
				Vector2(20.4, 25.4), Vector2(16.4, 27.4), Vector2(12.8, 18.6), Vector2(8.5, 22.5)]), c)
