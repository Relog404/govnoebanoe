class_name BoardEditor
extends Node3D

const BoardData = preload("res://components/board_data.gd")

# Редактор платы: raycast → сетка 10×10 мм → превью → ЛКМ разместить / ПКМ снять.
# Дорожки — настоящие компоненты (trace_*), участвующие в симуляции как КЗ-ветви.
signal part_placed(id: String)
signal part_detached(id: String)
signal board_saved(path: String)
signal validated(issues: PackedStringArray)

const MM := 0.001
const CELL_HI := 1
var board: BoardData = BoardData.new()
var grid_map  # GridMap (вводится в res://board/board_editor.tscn)
var parts_root: Node3D
var traces_root: Node3D
var debris_root: Node3D
var ghost: MeshInstance3D
var carry := {}                     # {mode:"move"|"scene", id?, scene?, span, rot, origin_cell?, origin_rot?}
var hover_cell := Vector2i(-1, -1)
var _counter := 0
var _connected := false

const PART_LIBRARY := {
	"Транзистор NPN": "res://components/primitive_transistor.tscn",
	"Резистор": "res://components/primitive_resistor.tscn",
	"Конденсатор": "res://components/primitive_capacitor.tscn",
	"LED": "res://components/primitive_led.tscn",
	"Диод": "res://components/primitive_diode.tscn",
	"Чип DIP-8/16": "res://components/chip_dip.tscn",
	"Слот": "res://components/slot.tscn",
	"Кнопка": "res://components/button.tscn",
	"Переключатель": "res://components/switch.tscn",
	"OLED 0.96": "res://components/display_oled.tscn",
	"Матрица 8×8": "res://components/display_ledmatrix.tscn",
	"7-сегментный": "res://components/display_7seg.tscn",
	"Дорожка →": "res://components/trace_straight.tscn",
	"Дорожка угол": "res://components/trace_corner.tscn",
	"Дорожка T": "res://components/trace_t.tscn",
	"Дорожка крест": "res://components/trace_cross.tscn",
	"Корпус-заготовка": "res://components/case_blank.tscn",
}

func _ready() -> void:
	grid_map = $GridMap
	parts_root = $Parts
	traces_root = $Traces
	debris_root = $Debris
	_make_cell_library()
	_make_ghost()
	ToolManager.gesture.connect(_on_gesture)
	_connected = true

# ---------- Сетка ----------

func _make_cell_library() -> void:
	var lib := MeshLibrary.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(grid_mm_f() * MM * 0.94, 0.15 * MM, grid_mm_f() * MM * 0.94)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.85, 0.72, 0.30)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	lib.create_item(CELL_HI)
	lib.set_item_mesh(CELL_HI, quad)
	grid_map.mesh_library = lib
	grid_map.cell_size = Vector3(grid_mm_f() * MM, 0.001, grid_mm_f() * MM)

func grid_mm_f() -> float:
	return board.grid_mm

func board_size_m() -> Vector2:
	return Vector2(board.width * board.grid_mm, board.height * board.grid_mm) * MM

func cell_center_m(cell: Vector2i, span := Vector2i(1, 1), rot := 0) -> Vector3:
	var w := float(span.x) if rot & 1 == 0 else float(span.y)
	var h := float(span.y) if rot & 1 == 0 else float(span.x)
	var size := board_size_m()
	var x := (float(cell.x) + w * 0.5) * board.grid_mm * MM - size.x * 0.5
	var z := (float(cell.y) + h * 0.5) * board.grid_mm * MM - size.y * 0.5
	return Vector3(x, 0.0, z)

func point_to_cell(world: Vector3, span := Vector2i(1, 1), rot := 0) -> Variant:
	var size := board_size_m()
	var x := world.x + size.x * 0.5
	var z := world.z + size.y * 0.5
	var w := span.x if rot & 1 == 0 else span.y
	var h := span.y if rot & 1 == 0 else span.x
	# << для левой-нижней клетки (привязка по углу клетки).
	var cx := floori(x / (board.grid_mm * MM) - float(w) * 0.5 + 0.5)
	var cy := floori(z / (board.grid_mm * MM) - float(h) * 0.5 + 0.5)
	if cx < 0 or cy < 0 or cx + w > board.width or cy + h > board.height:
		return null
	return Vector2i(cx, cy)

# ---------- Превью ----------

func _make_ghost() -> void:
	ghost = MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(board.grid_mm, 2.0, board.grid_mm) * MM
	ghost.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.95, 0.63, 0.42)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.32, 0.95, 0.63)
	mat.emission_energy_multiplier = 1.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = mat
	ghost.visible = false
	add_child(ghost)

func _set_ghost(ok: bool) -> void:
	var mat: StandardMaterial3D = ghost.material_override
	var color := Color(0.32, 0.95, 0.63, 0.42) if ok else Color(0.95, 0.32, 0.32, 0.42)
	mat.albedo_color = color
	mat.emission = color

# ---------- raycast ----------

func _ray_from_mouse(mouse: Vector2):
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var origin := cam.project_ray_origin(mouse)
	var normal := cam.project_ray_normal(mouse)
	var to_plane := -origin.y / normal.y if absf(normal.y) > 1e-6 else INF
	var point := origin + normal * to_plane if to_plane != INF else Vector3.INF
	# Прямое пересечение лучом с Area3D (пины и тела).
	var query := PhysicsRayQueryParameters3D.create(origin, origin + normal * 1000.0, 4 | 8)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return {"point": point, "hit": hit}

func build_target(mouse: Vector2) -> Dictionary:
	var ray: Dictionary = _ray_from_mouse(mouse)
	var target := {"point": ray.get("point", Vector3.INF)}
	var cell: Variant = point_to_cell(target.point) if target.point != Vector3.INF else null
	target["cell"] = cell
	target["can_place"] = false
	var span := _carry_span()
	if cell is Vector2i:
		target["can_place"] = board.can_place([cell.x, cell.y], [span.x, span.y], int(carry.get("rot", 0)), str(carry.get("id", "")))
	if ray.has("hit") and not ray.hit.is_empty():
		var col: Object = ray.hit.collider
		if col is Node3D:
			target["point"] = ray.hit.position
			var part := _owner_part(col)
			if part:
				target["id"] = part.component_id
			var pin_name: String = col.get_meta("pin") if col.has_meta("pin") else ""
			if not pin_name.is_empty() and part:
				target["pin"] = part.endpoint(pin_name)
	return target

func _owner_part(node: Node) -> Node3D:
	var n := node
	while n:
		if n is Node3D and not String(n.get("component_id")).is_empty():
			return n
		n = n.get_parent()
	return null

func _carry_span() -> Vector2i:
	if carry.is_empty():
		return Vector2i(1, 1)
	return Vector2i(int(carry.span[0]), int(carry.span[1]))

# ---------- Мышь ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_motion(event.position)
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	# Вращение переносимого компонента/дорожки — только пока несём.
	if not carry.is_empty() and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and int(carry.get("rot", 0)) == 3:
		pass  # колесо занято лупой/камерой: вращаем R
	if not carry.is_empty() and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		var target := build_target(event.position)
		ToolManager.apply(event, target)
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT or event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var target := build_target(event.position)
		ToolManager.apply(event, target)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# R — поворот (можно на любой стадии переноса; клавиша не занята инструментами).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if not carry.is_empty():
			carry.rot = (int(carry.get("rot", 0)) + 1) & 3
			_refresh_ghost()
			get_viewport().set_input_as_handled()

func _on_motion(mouse: Vector2) -> void:
	var target := build_target(mouse)
	hover_cell = target.get("cell") if target.get("cell") is Vector2i else Vector2i(-1, -1)
	if not carry.is_empty():
		_refresh_ghost()
	if ToolManager.current == ToolManager.Tool.TESTER:
		ToolManager.hover(target)

func _refresh_ghost() -> void:
	var span := _carry_span()
	var ok := board.can_place([hover_cell.x, hover_cell.y], [span.x, span.y], int(carry.get("rot", 0)), str(carry.get("id", "")))
	ghost.visible = hover_cell.x >= 0
	if ghost.visible:
		ghost.position = cell_center_m(hover_cell, span, int(carry.get("rot", 0))) + Vector3.UP * 0.002
		var w := float(span.x) if int(carry.get("rot", 0)) & 1 == 0 else float(span.y)
		var h := float(span.y) if int(carry.get("rot", 0)) & 1 == 0 else float(span.x)
		(ghost.mesh as BoxMesh).size = Vector3(w * board.grid_mm, 2.4, h * board.grid_mm) * MM
		_set_ghost(ok)
	grid_map.clear()
	if not carry.is_empty() and hover_cell.x >= 0:
		grid_map.set_cell_item(Vector3i(hover_cell.x, 0, hover_cell.y), CELL_HI)

# ---------- Библиотека и жесты ----------

# Немедленное размещение по drop из палитры (координаты экрана → клетка).
func place_scene_immediately(scene_path: String, mouse: Vector2) -> void:
	start_carry_scene(scene_path)
	_on_motion(mouse)
	_commit_place()

func start_carry_scene(scene_path: String) -> void:
	cancel_carry()
	if not ResourceLoader.exists(scene_path):
		push_error("Нет сцены: " + scene_path)
		return
	var scene: PackedScene = load(scene_path)
	var node: Node3D = scene.instantiate()
	_counter += 1
	var base := scene_path.get_file().get_basename().to_upper().replace("TRACE_", "T")
	var component_id := "P%d_%s" % [_counter, base] if not base.begins_with("T") else "%s%d" % [base, _counter]
	# Сначала узнаём габариты; узел до размещения в дерево не добавляем.
	var size: Vector3 = node.size_mm() if node.has_method("size_mm") else Vector3.ONE
	var span := Vector2i(ceili(size.x / board.grid_mm), ceili(size.z / board.grid_mm))
	var is_trace := scene_path.get_file().begins_with("trace_")
	carry = {"mode": "scene", "scene": scene_path, "id": component_id, "span": [span.x, span.y], "rot": 0,
		"is_trace": is_trace, "case_only": scene_path.get_file().begins_with("case_")}
	node.free()
	ToolManager.select(ToolManager.Tool.TWEEZERS)

func start_move(id: String) -> bool:
	for c: Dictionary in board.components:
		if str(c.get("id", "")) == id:
			carry = {"mode": "move", "id": id, "span": c.get("span", [1, 1]), "rot": int(c.get("rot", 0)), "origin_cell": c.get("cell", [0, 0]), "origin_rot": int(c.get("rot", 0))}
			ToolManager.held = id
			ghost.visible = true
			return true
	for t: Dictionary in board.traces:
		if str(t.get("id", "")) == id:
			carry = {"mode": "move", "id": id, "span": [1, 1], "rot": int(t.get("rot", 0)), "origin_cell": t.get("cell", [0, 0]), "origin_rot": int(t.get("rot", 0))}
			ToolManager.held = id
			ghost.visible = true
			return true
	return false

func cancel_carry() -> void:
	if carry.is_empty():
		return
	if carry.get("mode") == "move":
		var node := _find_node(str(carry.id))
		if node and carry.has("origin_cell"):
			node.position = cell_center_m(Vector2i(carry.origin_cell[0], carry.origin_cell[1]), _carry_span(), int(carry.origin_rot))
			node.rotation.y = -int(carry.origin_rot) * PI * 0.5
	carry = {}
	ToolManager.held = ""
	ghost.visible = false
	grid_map.clear()

func _on_gesture(action: String, data: Dictionary) -> void:
	match action:
		"take":
			var id := str(data.get("id", ""))
			if not id.is_empty():
				start_move(id)
		"place":
			_commit_place()
		"detach":
			_detach_part(str(data.get("id", "")), data)
		"wire_end":
			_record_link(str(data.get("from", "")), str(data.get("to", "")))
		"cancel":
			cancel_carry()

func _find_node(id: String) -> Node3D:
	for root in [parts_root, traces_root]:
		for child in root.get_children():
			if child.get("component_id") == id:
				return child
	return null

func _commit_place() -> void:
	if carry.is_empty() or hover_cell.x < 0:
		cancel_carry()
		return
	if carry.get("mode") == "move":
		_commit_move()
		return
	var scene_path := str(carry.get("scene", ""))
	var scene: PackedScene = load(scene_path)
	var node: Node3D = scene.instantiate()
	node.component_id = str(carry.id)
	var rot := int(carry.get("rot", 0))
	node.position = cell_center_m(hover_cell, _carry_span(), rot)
	node.rotation.y = -rot * PI * 0.5
	var is_trace := scene_path.get_file().begins_with("trace_")
	(traces_root if is_trace else parts_root).add_child(node)
	var entry := {"id": node.component_id, "scene": scene_path, "cell": [hover_cell.x, hover_cell.y],
		"rot": rot, "params": node.params, "span": carry.span}
	if carry.get("case_only", false):
		entry.decor = true
	if is_trace:
		board.traces.append({"id": entry.id, "kind": scene_path.get_file().get_basename(), "cell": entry.cell, "rot": rot})
	else:
		board.components.append(entry)
	carry = {}
	ToolManager.held = ""
	ghost.visible = false
	grid_map.clear()
	part_placed.emit(str(entry.id))

func _commit_move() -> void:
	var id := str(carry.id)
	var node := _find_node(id)
	var span := _carry_span()
	var rot := int(carry.get("rot", 0))
	if node:
		node.position = cell_center_m(hover_cell, span, rot)
		node.rotation.y = -rot * PI * 0.5
	for list: Array in [board.components, board.traces]:
		for entry: Dictionary in list:
			if str(entry.get("id", "")) == id:
				entry.cell = [hover_cell.x, hover_cell.y]
				entry.rot = rot
	carry = {}
	ToolManager.held = ""
	ghost.visible = false
	grid_map.clear()
	part_placed.emit(id)

func _detach_part(id: String, data: Dictionary) -> void:
	if id.is_empty():
		return
	var node := _find_node(id)
	if node:
		SimRegistry.unregister(node)   # снятая деталь из схемы вычеркнута
		var world_xform := node.global_transform
		var body := RigidBody3D.new()
		body.mass = 4.0 + 0.8 * node.get_child_count()  # Грубая масса: больше выводов — тяжелее.
		body.gravity_scale = 1.0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var size: Vector3 = node.size_mm() * MM if node.has_method("size_mm") else Vector3(0.01, 0.005, 0.01)
		shape.size = size
		cs.shape = shape
		cs.position = Vector3.UP * size.y * 0.5
		body.add_child(cs)
		var parent := node.get_parent()
		var g_basis := node.global_transform.basis
		parent.remove_child(node)
		body.transform = world_xform
		debris_root.add_child(body)
		body.add_child(node)
		node.global_transform = world_xform
		ToolManager.cancel()
	var keep: Array[Dictionary] = []
	for c: Dictionary in board.components:
		if str(c.get("id", "")) != id:
			keep.append(c)
	board.components = keep
	var keep_traces: Array[Dictionary] = []
	for t: Dictionary in board.traces:
		if str(t.get("id", "")) != id:
			keep_traces.append(t)
	board.traces = keep_traces
	# Все связи с отсоединённым компонентом обрываются.
	var links: Array[Array] = []
	for link: Array in board.links:
		if not (str(link[0]).begins_with(id + ".") or str(link[1]).begins_with(id + ".")):
			links.append(link)
	board.links = links
	# Пока не реализовано: части остаются в мире как мусор с гравитацией.
	part_detached.emit(id)

func _record_link(a: String, b: String) -> void:
	if a.is_empty() or b.is_empty():
		return
	var link := [a, b] if a < b else [b, a]
	if not board.links.has(link):
		board.links.append(link)

# ---------- Сохранение / загрузка ----------

func save_board(path: String) -> bool:
	var err := ResourceSaver.save(board, path)
	if err == OK:
		board_saved.emit(path)
	return err == OK

func load_board(path: String) -> bool:
	var res := load(path)
	if not res is BoardData:
		return false
	_clear_board()
	board = res
	grid_map.clear()
	for entry: Dictionary in board.catalog():
		var scene: PackedScene = load(str(entry.get("scene", "")))
		if scene == null:
			continue
		var node: Node3D = scene.instantiate()
		node.component_id = str(entry.get("id", "P?"))
		node.params = entry.get("params", {})
		node.position = cell_center_m(Vector2i(entry.cell[0], entry.cell[1]), Vector2i(int(entry.span[0]), int(entry.span[1])), int(entry.get("rot", 0)))
		node.rotation.y = -int(entry.get("rot", 0)) * PI * 0.5
		if str(entry.scene).get_file().begins_with("trace_"):
			traces_root.add_child(node)
		else:
			parts_root.add_child(node)
	for entry: Dictionary in board.traces:
		var kind := str(entry.get("kind", "trace_straight"))
		var scene2: PackedScene = load("res://components/%s.tscn" % kind)
		if scene2 == null:
			continue
		var tile: Node3D = scene2.instantiate()
		tile.component_id = str(entry.get("id", "T?"))
		tile.position = cell_center_m(Vector2i(entry.cell[0], entry.cell[1]), Vector2i(1, 1), int(entry.get("rot", 0)))
		tile.rotation.y = -int(entry.get("rot", 0)) * PI * 0.5
		traces_root.add_child(tile)
	for link: Array in board.links:
		SimRegistry.connect_ports(str(link[0]), str(link[1]))
	return true

func _clear_board() -> void:
	for root in [parts_root, traces_root, debris_root]:
		for child in root.get_children():
			child.free()
	board = BoardData.new()

# ---------- Валидация ----------

func validate_board() -> PackedStringArray:
	var issues := SimRegistry.validate()
	for link: Array in board.links:
		if not SimRegistry.has_pin(str(link[0])) or not SimRegistry.has_pin(str(link[1])):
			issues.append("Битая связь: %s — %s" % [link[0], link[1]])
	var drive := 0
	for id: String in ["P"]:  # Проверка источника такта уже в реестре; здесь — перечисление.
		pass
	validated.emit(issues)
	return issues
