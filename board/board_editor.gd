class_name BoardEditor
extends Node3D

const BoardDataScript = preload("res://components/board_data.gd")

# Редактор платы: raycast → сетка 10×10 мм → превью → ЛКМ разместить / ПКМ снять.
# Дорожки — настоящие компоненты (trace_*), участвующие в симуляции как КЗ-ветви.
signal part_placed(id: String)
signal part_detached(id: String)
signal board_saved(path: String)
signal validated(issues: PackedStringArray)
signal notify(message: String)
signal hover_info(text: String)
signal board_resized(width_mm: float, height_mm: float)

const MM := 0.001
const CELL_HI := 1
var board: BoardDataScript = BoardDataScript.new()
var grid_map  # GridMap (вводится в res://board/board_editor.tscn)
var parts_root: Node3D
var traces_root: Node3D
var debris_root: Node3D
var ghost: MeshInstance3D
var wires_root: Node3D
var carry := {}                     # {mode:"move"|"scene", id?, scene?, span, rot, origin_cell?, origin_rot?}
var hover_cell := Vector2i(-1, -1)
var _counter := 0
var _connected := false

const TYPE_MAP := {
	"transistor": "res://components/primitive_transistor.tscn",
	"resistor": "res://components/primitive_resistor.tscn",
	"capacitor": "res://components/primitive_capacitor.tscn",
	"led": "res://components/primitive_led.tscn",
	"diode": "res://components/primitive_diode.tscn",
	"chip_dip8": "res://components/chip_dip.tscn",
	"chip_dip16": "res://components/chip_dip.tscn",
	"oled": "res://components/display_oled.tscn",
	"matrix": "res://components/display_ledmatrix.tscn",
	"7seg": "res://components/display_7seg.tscn",
	"button": "res://components/button.tscn",
	"switch": "res://components/switch.tscn",
	"slot": "res://components/slot.tscn",
	"power": "res://components/power_rail.tscn",
	"trace_straight": "res://components/trace_straight.tscn",
	"trace_corner": "res://components/trace_corner.tscn",
	"trace_t": "res://components/trace_t.tscn",
	"trace_cross": "res://components/trace_cross.tscn",
	"case": "res://components/case_blank.tscn",
}

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
	"Питание (БП 3.3 В)": "res://components/power_rail.tscn",
}

func _ready() -> void:
	grid_map = $GridMap
	parts_root = $Parts
	traces_root = $Traces
	debris_root = $Debris
	wires_root = $Wires
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
		var cid: String = str(n.get("component_id"))
		if n is Node3D and not cid.is_empty():
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
	if not carry.is_empty() and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if carry.get("mode") == "scene":
			# Деталь «в руке» из палитры: ЛКМ — поставить на клетку, ПКМ — отмена.
			if event.button_index == MOUSE_BUTTON_LEFT:
				_on_motion(event.position)
				_commit_place()
			else:
				cancel_carry()
			get_viewport().set_input_as_handled()
			return
		var target := build_target(event.position)
		ToolManager.apply(event, target)
		get_viewport().set_input_as_handled()
		return
	if ToolManager.current == ToolManager.Tool.CURSOR and event.button_index == MOUSE_BUTTON_LEFT:
		var target := build_target(event.position)
		if _try_toggle_button(target):
			get_viewport().set_input_as_handled()
			return
	if ToolManager.current == ToolManager.Tool.CURSOR and event.button_index == MOUSE_BUTTON_RIGHT:
		var target := build_target(event.position)
		var pin := str(target.get("pin", ""))
		if not pin.is_empty():
			var removed := remove_pin_links(pin)
			notify.emit("Связей на %s убрано: %d" % [pin, removed])
			get_viewport().set_input_as_handled()
			return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# Лупа или перенос детали — колесо наше; иначе пусть камера мира панорамирует.
		if carry.is_empty() and ToolManager.current != ToolManager.Tool.LOUPE:
			return
		var target := build_target(event.position)
		ToolManager.apply(event, target)
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
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
		return
	# Esc — отменить перенос и незавершённую пайку.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel_carry()
		ToolManager.cancel()
		get_viewport().set_input_as_handled()

var _last_hover_text := ""

func _on_motion(mouse: Vector2) -> void:
	var target := build_target(mouse)
	hover_cell = target.get("cell") if target.get("cell") is Vector2i else Vector2i(-1, -1)
	var text := ""
	if hover_cell.x >= 0:
		var free := board.can_place([hover_cell.x, hover_cell.y], [1, 1], 0)
		text = "Клетка (%d, %d)" % [hover_cell.x, hover_cell.y] + (" · свободно" if free else " · занято")
	if text != _last_hover_text:
		_last_hover_text = text
		hover_info.emit(text)
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

# Единый генератор id: P<N>_RESISTOR и т.п. — без PRIMITIVE_/TRACE_ и подчёркиваний.
func _auto_component_id(scene_path: String) -> String:
	_counter += 1
	var base := scene_path.get_file().get_basename().to_upper()
	for junk in ["PRIMITIVE_", "TRACE_"]:
		base = base.replace(junk, "")
	base = base.replace("_", "")
	return "P%d_%s" % [_counter, base]

func start_carry_scene(scene_path: String) -> void:
	cancel_carry()
	if not ResourceLoader.exists(scene_path):
		push_error("Нет сцены: " + scene_path)
		return
	var scene: PackedScene = load(scene_path)
	var node: Node3D = scene.instantiate()
	var component_id := _auto_component_id(scene_path)
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
			_detach_part(str(data.get("id", "")))
		"wire_end":
			_record_link(str(data.get("from", "")), str(data.get("to", "")))
			_add_wire_visual(str(data.get("from", "")), str(data.get("to", "")))
			spark(data.get("point", Vector3.ZERO))
			notify.emit("Припаяно: %s → %s" % [data.get("from", ""), data.get("to", "")])
		"cancel":
			cancel_carry()

func _find_node(id: String) -> Node3D:
	for root in [parts_root, traces_root]:
		for child in root.get_children():
			if child.get("component_id") == id:
				return child
	return null

func _commit_place() -> void:
	if carry.is_empty():
		cancel_carry()
		return
	if hover_cell.x < 0:
		# Деталь остаётся в руке — просто некуда ставить.
		notify.emit("Курсор вне платы — деталь осталась в руке")
		return
	if carry.get("mode") == "move":
		_commit_move()
		return
	var span := _carry_span()
	var rot0 := int(carry.get("rot", 0))
	if not board.can_place([hover_cell.x, hover_cell.y], [span.x, span.y], rot0, str(carry.get("id", ""))):
		# Деталь не теряем: клетка занята — остаётся в руке.
		notify.emit("Клетка занята — туда не поставить")
		return
	var scene_path := str(carry.get("scene", ""))
	var scene: PackedScene = load(scene_path)
	var node: Node3D = scene.instantiate()
	node.component_id = str(carry.id)
	var rot := rot0
	node.position = cell_center_m(hover_cell, span, rot)
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
	if carry.get("mode") == "scene":
		# Серийное размещение: тот же тип детали до Esc/ПКМ.
		carry.id = _auto_component_id(scene_path)
	else:
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

func _detach_part(id: String) -> void:
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
	if not res is BoardDataScript:
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
	rebuild_wire_visuals()
	return true

func _clear_board() -> void:
	for root in [parts_root, traces_root, debris_root, wires_root]:
		for child in root.get_children():
			child.free()
	board = BoardDataScript.new()

# ---------- Валидация ----------

func validate_board() -> PackedStringArray:
	var issues := SimRegistry.validate()
	for link: Array in board.links:
		if not SimRegistry.has_pin(str(link[0])) or not SimRegistry.has_pin(str(link[1])):
			issues.append("Битая связь: %s — %s" % [link[0], link[1]])
	validated.emit(issues)
	return issues

# ---------- Публичный API: сценарии (DSL) и мир ----------

signal watch_requested(pin: String)

func get_part_node(id: String) -> Node3D:
	return _find_node(id)

func place_typed(kind: String, id: String, cell: Vector2i, rot: int, params: Dictionary) -> bool:
	var scene_path: String = TYPE_MAP.get(kind, "")
	if scene_path.is_empty():
		notify.emit("Неизвестный тип: " + kind)
		return false
	if _find_node(id) != null:
		notify.emit("Деталь «%s» уже есть — id должен быть уникальным" % id)
		return false
	var span := Vector2i(1, 1)
	if kind == "chip_dip16":
		span = Vector2i(2, 1)
	elif kind == "chip_dip8":
		span = Vector2i(1, 1)
	else:
		var proto: Node3D = load(scene_path).instantiate()
		var size: Vector3 = proto.size_mm() if proto.has_method("size_mm") else Vector3.ONE
		span = Vector2i(ceili(size.x / grid_mm_f()), ceili(size.z / grid_mm_f()))
		proto.free()
	if not board.can_place([cell.x, cell.y], [span.x, span.y], rot):
		notify.emit("Клетка занята: (%d, %d)" % [cell.x, cell.y])
		return false
	var node: Node3D = load(scene_path).instantiate()
	node.params = params
	node.component_id = id
	node.position = cell_center_m(cell, span, rot)
	node.rotation.y = -rot * PI * 0.5
	var is_trace := scene_path.get_file().begins_with("trace_")
	(traces_root if is_trace else parts_root).add_child(node)
	var entry := {"id": id, "scene": scene_path, "cell": [cell.x, cell.y], "rot": rot, "params": node.params, "span": [span.x, span.y]}
	if is_trace:
		board.traces.append({"id": id, "kind": scene_path.get_file().get_basename(), "cell": entry.cell, "rot": rot})
	else:
		board.components.append(entry)
	notify.emit("Размещено: %s в клетке (%d, %d)" % [id, cell.x, cell.y])
	return true

func erase_part(id: String) -> bool:
	var node := _find_node(id)
	if node == null:
		notify.emit("Деталь не найдена: " + id)
		return false
	SimRegistry.unregister(node)
	_remove_links_where(func(link: Array) -> bool: return str(link[0]).begins_with(id + ".") or str(link[1]).begins_with(id + "."))
	node.free()
	var keep: Array[Dictionary] = []
	for c: Dictionary in board.components:
		if str(c.get("id", "")) != id:
			keep.append(c)
	board.components = keep
	var keep_t: Array[Dictionary] = []
	for t: Dictionary in board.traces:
		if str(t.get("id", "")) != id:
			keep_t.append(t)
	board.traces = keep_t
	notify.emit("Удалено: " + id)
	return true

func resize_board(width_mm: float, height_mm: float) -> bool:
	var w := int(width_mm)
	var h := int(height_mm)
	if w < 20 or h < 20 or w > 400 or h > 400 or w % 10 != 0 or h % 10 != 0:
		notify.emit("Размер платы: 20…400 мм, кратно 10")
		return false
	clear_all()
	board.width = w / 10
	board.height = h / 10
	board_resized.emit(float(w), float(h))
	notify.emit("Плата: %d×%d мм" % [w, h])
	return true

func clear_all() -> void:
	cancel_carry()
	for root in [parts_root, traces_root, debris_root, wires_root]:
		if root == null:
			continue
		for child in root.get_children():
			child.free()
	var keep_w := board.width
	var keep_h := board.height
	board = BoardDataScript.new()
	board.width = keep_w
	board.height = keep_h
	grid_map.clear()

func clear_debris() -> void:
	for child in debris_root.get_children():
		child.free()
	notify.emit("Мусор убран.")

func wire_pins(a: String, b: String) -> bool:
	if not SimRegistry.has_pin(a) or not SimRegistry.has_pin(b):
		notify.emit("Нет пина: %s или %s" % [a, b])
		return false
	if not SimRegistry.connect_ports(a, b):
		notify.emit("Уже соединены или невозможно: %s — %s" % [a, b])
		return false
	_record_link(a, b)
	_add_wire_visual(a, b)
	spark(pin_world(b))
	notify.emit("Припаяно: %s → %s" % [a, b])
	return true

func unwire_pins(a: String, b: String) -> bool:
	SimRegistry.disconnect_ports(a, b)
	var link := [a, b] if a < b else [b, a]
	var keep: Array[Array] = []
	for l: Array in board.links:
		if l != link:
			keep.append(l)
	board.links = keep
	_remove_wire_visual(link)
	notify.emit("Снято: %s — %s" % [link[0], link[1]])
	return true

func remove_pin_links(pin: String) -> int:
	return _remove_links_where(func(link: Array) -> bool: return link[0] == pin or link[1] == pin)

func _remove_links_where(pred: Callable) -> int:
	var removed := 0
	var kept: Array[Array] = []
	for link: Array in board.links:
		if pred.call(link):
			SimRegistry.disconnect_ports(str(link[0]), str(link[1]))
			_remove_wire_visual(link)
			removed += 1
		else:
			kept.append(link)
	board.links = kept
	return removed

func pin_world(pin: String) -> Vector3:
	var id := pin.get_slice(".", 0)
	var pin_name := pin.get_slice(".", 1)
	var node := _find_node(id)
	if node == null:
		return Vector3.ZERO
	var local := Vector3.ZERO
	if node.has_method("pin_layout_mm"):
		local = node.pin_layout_mm().get(pin_name, Vector3.ZERO)
		return node.global_transform * Vector3(local.x * MM, 0.0005, local.z * MM)
	return node.global_transform.origin + Vector3(0, 0.0005, 0)

func _rod_between(parent: Node3D, a: Vector3, b: Vector3, diameter: float) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = diameter * 0.5
	cylinder.bottom_radius = diameter * 0.5
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 8
	cylinder.rings = 0
	var mi := MeshInstance3D.new()
	mi.mesh = cylinder
	mi.material_override = _wire_mat()
	mi.position = (a + b) * 0.5
	mi.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	parent.add_child(mi)

var _wire_material: StandardMaterial3D

func _wire_mat() -> StandardMaterial3D:
	if _wire_material == null:
		_wire_material = StandardMaterial3D.new()
		_wire_material.albedo_color = Color("d89a4a")
		_wire_material.metallic = 0.85
		_wire_material.roughness = 0.32
	return _wire_material

func _add_wire_visual(a: String, b: String) -> void:
	if a.is_empty() or b.is_empty():
		return
	var link := [a, b] if a < b else [b, a]
	var va := pin_world(a)
	var vb := pin_world(b)
	var mid := (va + vb) * 0.5 + Vector3.UP * (0.004 + va.distance_to(vb) * 0.14)
	var parent := Node3D.new()
	parent.set_meta("wire", "%s,%s" % [link[0], link[1]])
	_rod_between(parent, va, mid, 0.00038)
	_rod_between(parent, mid, vb, 0.00038)
	wires_root.add_child(parent)

func _remove_wire_visual(link: Array) -> void:
	var key := "%s,%s" % [link[0], link[1]]
	for child in wires_root.get_children():
		if child.get_meta("wire", "") == key:
			child.free()

func rebuild_wire_visuals() -> void:
	if wires_root == null:
		return
	for child in wires_root.get_children():
		child.free()
	for link: Array in board.links:
		_add_wire_visual(str(link[0]), str(link[1]))

func spark(at: Vector3) -> void:
	var fx := GPUParticles3D.new()
	fx.one_shot = true
	fx.amount = 16
	fx.lifetime = 0.42
	fx.explosiveness = 0.92
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 58.0
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.17
	mat.gravity = Vector3(0, -0.55, 0)
	mat.color = Color(1.0, 0.83, 0.38)
	fx.process_material = mat
	var draw := SphereMesh.new()
	draw.radius = 0.0004
	draw.height = 0.0008
	draw.radial_segments = 6
	draw.rings = 3
	fx.draw_pass_1 = draw
	fx.position = at + Vector3.UP * 0.0012
	fx.emitting = true
	add_child(fx)
	get_tree().create_timer(1.2).timeout.connect(func() -> void: fx.queue_free())

func _try_toggle_button(target: Dictionary) -> bool:
	var id := str(target.get("id", ""))
	if id.is_empty():
		return false
	var node := _find_node(id)
	if node == null or node.get_script() == null:
		return false
	if not node.get_script().resource_path.contains("button"):
		return false
	var pressed := not bool(node.state.get("pressed", false))
	node.on_event("set", {"pressed": pressed})
	spark(target.get("point", Vector3.ZERO))
	notify.emit("Кнопка %s: %s" % [id, "нажата" if pressed else "отпущена"])
	return true
