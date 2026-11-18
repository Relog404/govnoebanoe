extends "res://components/component_base.gd"

# Слот расширения: механика + выводы без встроенного «чипа».
# Игроц задаёт параметры: контактов (кратно 2) и ширину ряда.
func _init() -> void:
	ports = {"A1":"passive","A2":"passive","A3":"passive","A4":"passive","A5":"passive","A6":"passive","A7":"passive","A8":"passive",
		"B1":"passive","B2":"passive","B3":"passive","B4":"passive","B5":"passive","B6":"passive","B7":"passive","B8":"passive"}

func size_mm() -> Vector3:
	return Vector3(22.0, 6.3, 7.6)

func pin_layout_mm() -> Dictionary:
	var out := {}
	for i in 8:
		out["A%d" % (i + 1)] = Vector3((i - 3.5) * 2.54, 0, 1.9)
		out["B%d" % (i + 1)] = Vector3((i - 3.5) * 2.54, 0, -1.9)
	return out

func make_mesh() -> Node3D:
	return make_slot(params)

func make_slot(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var body_color := Color.from_string(str(p.get("color", "111417")), Color.BLACK)
	var body := BoxMesh.new()
	body.size = Vector3(22.0, 4.6, 7.6) * MM
	piece(root, body, Vector3.UP * 2.42, stock(body_color))
	for z: float in [1.9, -1.9]:
		var trench := BoxMesh.new()
		trench.size = Vector3(20.4, 1.1, 1.0) * MM
		piece(root, trench, Vector3(0, 4.15, z), stock(Color("050607")))
		for i in 8:
			var tooth := BoxMesh.new()
			tooth.size = Vector3(0.8, 0.34, 0.85) * MM
			piece(root, tooth, Vector3((i - 3.5) * 2.54, 1.35, z), stock(SILVER, 0.7))
	return root

func tick(_at: int) -> void:
	# Сквозное соединение не размыкаем — это чисто пассивная периферия.
	pass
