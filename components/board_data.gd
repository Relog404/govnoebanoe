class_name BoardData
extends Resource

# Доска целиком: сетка 10×10 мм, компоненты, дорожки, провода между портами.
@export var grid_mm := 10.0
@export var width := 12            # клеток по X
@export var height := 8            # клеток по Y
@export var components: Array[Dictionary] = []   # {id, scene, cell:[x,y], rot:int, params:{}, span:[w,h]}
@export var traces: Array[Dictionary] = []       # {kind:String, cell:[x,y], rot:int}
@export var links: Array[Array] = []             # [[pinA, pinB], ...] — пайка паяльником

# Прямоугольник занимаемых клеток с учётом поворота на 90°.
func rect_cells(cell: Array, span: Array, rot: int) -> Array[Vector2i]:
	var w := int(span[0])
	var h := int(span[1])
	if rot & 1 == 1:
		var t := w
		w = h
		h = t
	var out: Array[Vector2i] = []
	for dy in h:
		for dx in w:
			out.append(Vector2i(int(cell[0]) + dx, int(cell[1]) + dy))
	return out

func cell_free(x: int, y: int, ignore_id: String = "") -> bool:
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	for c: Dictionary in components:
		if str(c.get("id", "")) == ignore_id:
			continue
		for p: Vector2i in rect_cells(c.get("cell", [0, 0]), c.get("span", [1, 1]), int(c.get("rot", 0))):
			if p.x == x and p.y == y:
				return false
	for t: Dictionary in traces:
		var p2: Array = t.get("cell", [0, 0])
		if int(p2[0]) == x and int(p2[1]) == y:
			return false
	return true

func can_place(cell: Array, span: Array, rot: int, ignore_id: String = "") -> bool:
	for p: Vector2i in rect_cells(cell, span, rot):
		if not cell_free(p.x, p.y, ignore_id):
			return false
	return true

func catalog() -> Array[Dictionary]:
	var parts := components.duplicate()
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id","")) < str(b.get("id","")))
	return parts
