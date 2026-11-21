class_name WireRouter
extends RefCounted
## Автотрассировка ортогональных дорожек между портами.
## Использует AStarGrid2D: обходит занятые компонентами клетки,
## а дорожки могут пересекаться (как на многослойной печатной плате).

const PADDING := 6
const MAX_SPAN := 96


## Ищет путь между внешними клетками портов.
## Возвращает {"ok": bool, "path": Array[Vector2i]} — путь по центрам клеток.
static func route(blocked: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> Dictionary:
	if from_cell == to_cell:
		var single: Array = [from_cell]
		return {"ok": true, "path": single}

	var pad := PADDING
	var min_c := Vector2i(mini(from_cell.x, to_cell.x) - pad, mini(from_cell.y, to_cell.y) - pad)
	var max_c := Vector2i(maxi(from_cell.x, to_cell.x) + pad, maxi(from_cell.y, to_cell.y) + pad)
	# Защита от гигантских расстояний (не должно случаться, но пусть будет).
	min_c.x = maxi(min_c.x, mini(from_cell.x, to_cell.x) - MAX_SPAN)
	max_c.x = mini(max_c.x, maxi(from_cell.x, to_cell.x) + MAX_SPAN)
	min_c.y = maxi(min_c.y, mini(from_cell.y, to_cell.y) - MAX_SPAN)
	max_c.y = mini(max_c.y, maxi(from_cell.y, to_cell.y) + MAX_SPAN)

	var grid := AStarGrid2D.new()
	grid.region = Rect2i(min_c, max_c - min_c + Vector2i.ONE)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()

	for cell in blocked.keys():
		if grid.region.has_point(cell):
			grid.set_point_solid(cell, true)
	# Порты, смотрящие друг на друга в соседних клетках, должны соединяться
	# даже если клетка формально занята.
	grid.set_point_solid(from_cell, false)
	grid.set_point_solid(to_cell, false)

	var raw: Array = grid.get_id_path(from_cell, to_cell)
	if raw.is_empty():
		return {"ok": false, "path": _fallback(from_cell, to_cell)}

	var cells: Array = []
	for c in raw:
		cells.append(c)
	return {"ok": true, "path": simplify(cells)}


## Оставляет только точки поворота — так дорожка рисуется длинными сегментами.
static func simplify(cells: Array) -> Array:
	if cells.size() <= 2:
		return cells.duplicate()
	var out: Array = []
	out.append(cells[0])
	for i in range(1, cells.size() - 1):
		var prev: Vector2i = cells[i - 1]
		var cur: Vector2i = cells[i]
		var nxt: Vector2i = cells[i + 1]
		var d1 := cur - prev
		var d2 := nxt - cur
		if d1 != d2:
			out.append(cur)
	out.append(cells[cells.size() - 1])
	return out


## Прямая L-образная дорожка, если A* не нашёл путь (например, всё застроено).
static func _fallback(from_cell: Vector2i, to_cell: Vector2i) -> Array:
	var out: Array = []
	out.append(from_cell)
	var bend := Vector2i(to_cell.x, from_cell.y)
	if bend != from_cell and bend != to_cell:
		out.append(bend)
	out.append(to_cell)
	return out


## Точки полилинии в пикселях мира для конкретной связи.
## Включает «ножки» от центров портов до внешних клеток.
static func link_points(a_info: Dictionary, b_info: Dictionary, path: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if a_info.is_empty() or b_info.is_empty():
		return pts
	pts.append(a_info["anchor"])
	var cells: Array = path
	if cells.is_empty():
		pts.append(b_info["anchor"])
		return pts
	for i in cells:
		pts.append((Vector2(i) + Vector2(0.5, 0.5)) * ChipBoard.CELL)
	pts.append(b_info["anchor"])
	return pts
