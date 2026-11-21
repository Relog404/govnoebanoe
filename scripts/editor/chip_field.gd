class_name ChipField
extends Node2D
## Бесконечное поле редактора чипа.
## Сетка рисуется в _draw() относительно Camera2D, компоненты — сцены
## Component.tscn, дорожки трассируются автоматически (WireRouter).

signal selection_changed(comp: Dictionary)
signal status(text: String, kind: String)
signal board_edited
signal placing_changed(def_id: String)

const CELL := ChipBoard.CELL
const ZOOM_MIN := 0.18
const ZOOM_MAX := 3.2
const PORT_PICK_PX := 16.0
const KEY_PAN_SPEED := 900.0

@onready var camera: Camera2D = $Camera2D
@onready var overlay: Node2D = $Overlay

var board: ChipBoard = null
var placing_def_id := ""
var placing_rot := 0
var selected_id := -1
var hovered_id := -1
var hovered_port: Dictionary = {}
var wire_from: Dictionary = {}
var drag: Dictionary = {}
var panning := false
var pan_button := 0
var mouse_active := false

var mouse_screen := Vector2.ZERO
var mouse_world := Vector2.ZERO
var hover_cell := Vector2i.ZERO

var _components: Dictionary = {}
var _scene: PackedScene = preload("res://scenes/components/component.tscn")
var _font: Font
var _key_pan: Dictionary = {}
var _pan_moved := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	overlay.field = self
	set_process(true)
	set_process_unhandled_input(true)
	call_deferred("_deferred_focus")


func _deferred_focus() -> void:
	await get_tree().process_frame
	focus_bounds()


func attach_board(new_board: ChipBoard) -> void:
	if board != null and board.changed.is_connected(_on_board_changed):
		board.changed.disconnect(_on_board_changed)
	board = new_board
	board.changed.connect(_on_board_changed)
	selected_id = -1
	hovered_id = -1
	hovered_port = {}
	wire_from = {}
	drag = {}
	_sync_components()
	_recompute_paths()
	_emit_selection()
	queue_redraw()
	focus_bounds()


func set_placing(def_id: String) -> void:
	placing_def_id = def_id
	placing_rot = 0
	wire_from = {}
	drag = {}
	hovered_port = {}
	placing_changed.emit(placing_def_id)
	overlay.queue_redraw()
	queue_redraw()


func cancel_modes() -> void:
	placing_def_id = ""
	placing_changed.emit("")
	wire_from = {}
	if not drag.is_empty() and _components.has(drag["id"]):
		_components[drag["id"]].set_dragging(false)
		_components[drag["id"]].refresh_from_board()
	drag = {}
	overlay.queue_redraw()
	queue_redraw()


func set_mouse_active(value: bool) -> void:
	mouse_active = value
	if not value:
		_key_pan.clear()
		if hovered_id != -1 and _components.has(hovered_id):
			_components[hovered_id].set_hovered(false)
			_components[hovered_id].set_hover_port("")
		hovered_id = -1
		hovered_port = {}
		wire_from = {}
		if not drag.is_empty():
			if _components.has(drag["id"]):
				var node: ChipComponent = _components[drag["id"]]
				node.set_dragging(false)
				node.set_invalid_drop(false)
				node.refresh_from_board()
			drag = {}
		overlay.queue_redraw()
		queue_redraw()


func get_selected_component() -> Dictionary:
	if board == null or selected_id == -1:
		return {}
	return board.get_component(selected_id)


func delete_selected() -> void:
	var id := selected_id if selected_id != -1 else hovered_id
	if id == -1:
		status.emit("Ничего не выбрано", "warn")
		return
	var comp := board.get_component(id)
	if comp.is_empty():
		return
	var d := board.def_of(comp)
	board.remove_component(id)
	selected_id = -1
	hovered_id = -1
	status.emit("Удалено: %s" % (d.display_name if d != null else "компонент"), "info")


func rotate_selected() -> void:
	var id := hovered_id if hovered_id != -1 else selected_id
	if id == -1:
		if placing_def_id != "":
			placing_rot = (placing_rot + 1) % 4
			status.emit("Поворот: %d°" % (placing_rot * 90), "info")
			queue_redraw()
			overlay.queue_redraw()
		return
	var comp := board.get_component(id)
	if comp.is_empty():
		return
	if board.rotated_component(id):
		status.emit("Поворот: %d°" % (int(comp["rot"]) * 90), "info")
	else:
		status.emit("Нельзя повернуть: мешают соседние компоненты", "error")


func zoom_step(factor: float) -> void:
	_zoom_at(get_viewport_rect().size * 0.5, factor)


func focus_bounds() -> void:
	var view := get_viewport_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		return
	if board == null or board.components.is_empty():
		camera.position = Vector2.ZERO
		camera.zoom = Vector2(0.8, 0.8)
		return
	var r := board.bounds_cells().grow(2)
	var w := maxf(3.0, float(r.size.x)) * CELL
	var h := maxf(3.0, float(r.size.y)) * CELL
	var z := clampf(minf(view.x / w, view.y / h), 0.22, 1.15)
	camera.position = Vector2(r.get_center()) * CELL
	camera.zoom = Vector2(z, z)
	queue_redraw()
	overlay.queue_redraw()


# ---------------------------------------------------------------------------
# Синхронизация с моделью
# ---------------------------------------------------------------------------

func _on_board_changed() -> void:
	_sync_components()
	_recompute_paths()
	_emit_selection()
	queue_redraw()
	overlay.queue_redraw()
	board_edited.emit()


func _sync_components() -> void:
	if board == null:
		return
	var alive := {}
	for comp in board.components:
		var id := int(comp["id"])
		alive[id] = true
		var node: ChipComponent = _components.get(id, null)
		if node == null:
			node = _scene.instantiate()
			add_child(node)
			_components[id] = node
		node.setup(comp, board.def_of(comp))
		node.set_selected(id == selected_id)
		node.set_hovered(id == hovered_id)
		if wire_from.is_empty():
			node.set_hover_port("")
	for id in _components.keys():
		if not alive.has(id):
			_components[id].queue_free()
			_components.erase(id)
	if selected_id != -1 and not alive.has(selected_id):
		selected_id = -1


func _recompute_paths() -> void:
	if board == null:
		return
	var blocked := board.occupied_cells()
	for link in board.links:
		var a := board.get_component(int(link["a"]))
		var b := board.get_component(int(link["b"]))
		if a.is_empty() or b.is_empty():
			continue
		var pa := board.port_info(a, String(link["a_port"]))
		var pb := board.port_info(b, String(link["b_port"]))
		if pa.is_empty() or pb.is_empty():
			continue
		var res := WireRouter.route(blocked, pa["outward"], pb["outward"])
		board.set_link_path(int(link["id"]), res["path"], not bool(res["ok"]))


func _emit_selection() -> void:
	selection_changed.emit(get_selected_component())


# ---------------------------------------------------------------------------
# Ввод
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		mouse_screen = event.position
		mouse_world = screen_to_world(mouse_screen)
		hover_cell = Vector2i(floori(mouse_world.x / CELL), floori(mouse_world.y / CELL))

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if panning:
			camera.position -= motion.relative / camera.zoom.x
			_pan_moved += absf(motion.relative.x) + absf(motion.relative.y)
			mouse_world = screen_to_world(mouse_screen)
			hover_cell = Vector2i(floori(mouse_world.x / CELL), floori(mouse_world.y / CELL))
			get_viewport().set_input_as_handled()
			overlay.queue_redraw()
			queue_redraw()
			return
		if not drag.is_empty():
			_update_drag()
		elif not wire_from.is_empty():
			_update_hover()
		else:
			_update_hover()
		_refresh_cursor_visuals()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.14)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.14)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				panning = true
				pan_button = mb.button_index
				_pan_moved = 0.0
			else:
				if panning and mb.button_index == MOUSE_BUTTON_RIGHT and _pan_moved < 4.0:
					rotate_selected()
				panning = false
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_press()
			else:
				_on_left_release()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey:
		if handle_key_event(event):
			get_viewport().set_input_as_handled()


func handle_key_event(event: InputEvent) -> bool:
	## Общая обработка клавиш поля: вызывается из _unhandled_input (когда
	## SubViewport в фокусе) и из ChipView (когда мышь над полем, но фокус
	## у другого контрола).
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	var key_name := KeyMap.from_event(key)
	if key_name == "":
		return false
	if key.pressed and not key.echo:
		match key_name:
			"R":
				rotate_selected()
				return true
			"DELETE", "X":
				delete_selected()
				return true
			"ESC":
				cancel_modes()
				return true
			"F":
				focus_bounds()
				return true
		match key_name:
			"W", "A", "S", "D", "LEFT", "RIGHT", "UP", "DOWN":
				_key_pan[key_name] = true
				return true
		return false
	if key.is_released():
		match key_name:
			"W", "A", "S", "D", "LEFT", "RIGHT", "UP", "DOWN":
				_key_pan[key_name] = false
				return true
	return false


func _process(delta: float) -> void:
	if not mouse_active or _key_pan.is_empty():
		if not wire_from.is_empty():
			overlay.queue_redraw()
		return
	var dir := Vector2.ZERO
	if _key_pan.get("A", false) or _key_pan.get("LEFT", false):
		dir.x -= 1.0
	if _key_pan.get("D", false) or _key_pan.get("RIGHT", false):
		dir.x += 1.0
	if _key_pan.get("W", false) or _key_pan.get("UP", false):
		dir.y -= 1.0
	if _key_pan.get("S", false) or _key_pan.get("DOWN", false):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		camera.position += dir.normalized() * KEY_PAN_SPEED * delta / camera.zoom.x
		_refresh_cursor_visuals()
	if not wire_from.is_empty():
		overlay.queue_redraw()


func _on_left_press() -> void:
	if board == null:
		return
	var port := _port_at(mouse_world)
	if not wire_from.is_empty():
		if port.is_empty():
			wire_from = {}
			overlay.queue_redraw()
			return
		if int(port["comp_id"]) == int(wire_from["comp_id"]):
			wire_from = {}
			overlay.queue_redraw()
			return
		_try_connect(port)
		return

	if not port.is_empty():
		wire_from = port
		selected_id = int(port["comp_id"])
		_emit_selection()
		status.emit("Порт %s · %s — тяните к другому порту" % [
			String(port["name"]), ComponentDef.kind_name(String(port["kind"]))], "info")
		overlay.queue_redraw()
		return

	var comp := _component_at(hover_cell)
	if not comp.is_empty():
		selected_id = int(comp["id"])
		_emit_selection()
		_begin_drag(comp)
		return

	if placing_def_id != "":
		_place_at(hover_cell)
		return

	if selected_id != -1:
		selected_id = -1
		_emit_selection()
		_sync_components()
		overlay.queue_redraw()


func _on_left_release() -> void:
	if not drag.is_empty():
		_finish_drag()
		return
	if not wire_from.is_empty():
		var port := _port_at(mouse_world)
		if not port.is_empty() and int(port["comp_id"]) != int(wire_from["comp_id"]):
			_try_connect(port)
		elif port.is_empty():
			wire_from = {}
			overlay.queue_redraw()


func _begin_drag(comp: Dictionary) -> void:
	var id := int(comp["id"])
	drag = {
		"id": id,
		"grab": hover_cell - comp["cell"],
		"origin": comp["cell"],
		"new_cell": comp["cell"],
		"valid": true,
	}
	var node: ChipComponent = _components.get(id, null)
	if node != null:
		node.set_dragging(true)


func _update_drag() -> void:
	if drag.is_empty() or board == null:
		return
	var comp := board.get_component(int(drag["id"]))
	if comp.is_empty():
		drag = {}
		return
	var d := board.def_of(comp)
	var new_cell: Vector2i = hover_cell - drag["grab"]
	var valid := board.can_place(d.id, new_cell, int(comp["rot"]), int(comp["id"]))
	drag["new_cell"] = new_cell
	drag["valid"] = valid
	var node: ChipComponent = _components.get(int(drag["id"]), null)
	if node != null:
		node.position = Vector2(new_cell) * CELL
		node.set_invalid_drop(not valid)


func _finish_drag() -> void:
	var id := int(drag["id"])
	var node: ChipComponent = _components.get(id, null)
	if node != null:
		node.set_dragging(false)
		node.set_invalid_drop(false)
	if bool(drag.get("valid", false)) and Vector2i(drag["new_cell"]) != Vector2i(drag["origin"]):
		board.moved_component(id, drag["new_cell"])
		status.emit("Компонент перемещён", "info")
	elif node != null:
		node.refresh_from_board()
	drag = {}
	overlay.queue_redraw()


func _try_connect(target: Dictionary) -> void:
	var res := board.connect_ports(int(wire_from["comp_id"]), String(wire_from["name"]),
		int(target["comp_id"]), String(target["name"]))
	if bool(res.get("ok", false)):
		status.emit("Соединено: %s ↔ %s" % [wire_from["name"], target["name"]], "ok")
	else:
		status.emit(String(res.get("error", "Ошибка соединения")), "error")
	wire_from = {}
	overlay.queue_redraw()


func _place_at(cell: Vector2i) -> void:
	var d := ComponentLibrary.get_def(placing_def_id)
	if d == null:
		return
	if not board.can_place(d.id, cell, placing_rot):
		status.emit("Здесь уже занято", "error")
		return
	var id := board.add_component(d.id, cell, placing_rot)
	selected_id = id
	_sync_components()
	_emit_selection()
	queue_redraw()
	overlay.queue_redraw()
	status.emit("Установлено: %s" % d.display_name, "ok")


## Ставит компонент по точке в координатах SubViewport (drag&drop из палитры).
func place_def_at_screen(def_id: String, screen_pos: Vector2) -> bool:
	if board == null:
		return false
	var d := ComponentLibrary.get_def(def_id)
	if d == null:
		return false
	var world := screen_to_world(screen_pos)
	var cell := Vector2i(floori(world.x / CELL), floori(world.y / CELL))
	var rot := posmod(placing_rot, 4)
	var sz := d.rotated_size(rot)
	var attempts := [
		{"rot": rot, "cell": cell - Vector2i(int(sz.x / 2), int(sz.y / 2))},
		{"rot": rot, "cell": cell},
		{"rot": 0, "cell": cell - Vector2i(int(d.size.x / 2), int(d.size.y / 2))},
		{"rot": 0, "cell": cell},
	]
	for a in attempts:
		var place_cell: Vector2i = a["cell"]
		var place_rot := int(a["rot"])
		if not board.can_place(d.id, place_cell, place_rot):
			continue
		var id := board.add_component(d.id, place_cell, place_rot)
		selected_id = id
		_sync_components()
		_emit_selection()
		queue_redraw()
		overlay.queue_redraw()
		status.emit("Установлено: %s (drag&drop)" % d.display_name, "ok")
		return true
	status.emit("Здесь не хватает места для %s" % d.display_name, "error")
	return false


func _update_hover() -> void:
	if board == null:
		return
	var port := _port_at(mouse_world)
	hovered_port = port
	var comp := {}
	if not port.is_empty():
		comp = board.get_component(int(port["comp_id"]))
	else:
		comp = _component_at(hover_cell)
	var new_hover := int(comp.get("id", -1))
	if new_hover != hovered_id:
		if hovered_id != -1 and _components.has(hovered_id):
			_components[hovered_id].set_hovered(false)
		hovered_id = new_hover
		if hovered_id != -1 and _components.has(hovered_id):
			_components[hovered_id].set_hovered(true)
	var port_name := ""
	if not port.is_empty() and int(port["comp_id"]) == hovered_id:
		port_name = String(port["name"])
	for id in _components:
		var node: ChipComponent = _components[id]
		node.set_hover_port(port_name if id == hovered_id else "")


func _refresh_cursor_visuals() -> void:
	queue_redraw()
	overlay.queue_redraw()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_pos)
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	var after := screen_to_world(screen_pos)
	camera.position += before - after
	mouse_world = screen_to_world(mouse_screen)
	hover_cell = Vector2i(floori(mouse_world.x / CELL), floori(mouse_world.y / CELL))
	queue_redraw()
	overlay.queue_redraw()


# ---------------------------------------------------------------------------
# Координаты и попадания
# ---------------------------------------------------------------------------

func screen_to_world(screen_pos: Vector2) -> Vector2:
	var view := get_viewport_rect().size
	var z := camera.zoom.x
	return (screen_pos - view * 0.5) / z + camera.position


func _component_at(cell: Vector2i) -> Dictionary:
	if board == null:
		return {}
	return board.find_component_at(cell)


func _port_at(world_pos: Vector2) -> Dictionary:
	if board == null:
		return {}
	var best := {}
	var best_dist := PORT_PICK_PX / camera.zoom.x
	for comp in board.components:
		for info in board.world_ports(comp):
			var dist: float = (info["anchor"] as Vector2).distance_to(world_pos)
			if dist < best_dist:
				best_dist = dist
				best = info
	return best


# ---------------------------------------------------------------------------
# Отрисовка поля
# ---------------------------------------------------------------------------

func _draw() -> void:
	if board == null:
		return
	var view := get_viewport_rect().size
	var z := camera.zoom.x
	var half := view * 0.5 / z
	var top_left := camera.position - half
	var area := Rect2(top_left, half * 2.0)

	# Фон платы.
	draw_rect(area.grow(CELL * 2.0), Color("#060b0e"))
	draw_rect(area.grow(CELL), Color("#081116"))

	# Шаг сетки зависит от зума.
	var step := 1
	if z < 0.3:
		step = 8
	elif z < 0.55:
		step = 4
	elif z < 1.0:
		step = 2
	var step_px := float(step) * CELL
	var lw := 1.0 / z

	var start_x := floorf(top_left.x / step_px) * step_px
	var start_y := floorf(top_left.y / step_px) * step_px
	var x := start_x
	while x <= top_left.x + half.x * 2.0 + step_px:
		var gx := int(round(x / CELL))
		var col := Color(0.10, 0.18, 0.20, 0.55)
		if posmod(gx, 8) == 0:
			col = Color(0.14, 0.35, 0.36, 0.55)
		draw_line(Vector2(x, top_left.y), Vector2(x, top_left.y + half.y * 2.0), col, lw)
		x += step_px
	var y := start_y
	while y <= top_left.y + half.y * 2.0 + step_px:
		var gy := int(round(y / CELL))
		var col2 := Color(0.10, 0.18, 0.20, 0.55)
		if posmod(gy, 8) == 0:
			col2 = Color(0.14, 0.35, 0.36, 0.55)
		draw_line(Vector2(top_left.x, y), Vector2(top_left.x + half.x * 2.0, y), col2, lw)
		y += step_px

	# Оси и координатные метки.
	draw_line(Vector2(top_left.x, 0), Vector2(top_left.x + half.x * 2.0, 0),
		Color(0.25, 0.75, 0.6, 0.35), lw * 1.5)
	draw_line(Vector2(0, top_left.y), Vector2(0, top_left.y + half.y * 2.0),
		Color(0.25, 0.75, 0.6, 0.35), lw * 1.5)
	_draw_grid_labels(top_left, half, z)

	# Дорожки.
	_draw_links(z)
	_draw_wire_preview(z)


func _draw_grid_labels(top_left: Vector2, half: Vector2, z: float) -> void:
	if z < 0.42:
		return
	var font_size := int(clampf(10.0 / z, 9.0, 22.0))
	var major := 8
	var left_cell := int(floorf(top_left.x / CELL))
	var right_cell := int(ceilf((top_left.x + half.x * 2.0) / CELL))
	var top_cell := int(floorf(top_left.y / CELL))
	var bottom_cell := int(ceilf((top_left.y + half.y * 2.0) / CELL))
	var col := Color(0.35, 0.65, 0.6, 0.5)
	var first := int(ceilf(float(left_cell) / major)) * major
	for gx in range(first, right_cell + 1, major):
		var sx := gx * CELL
		draw_string(_font, Vector2(sx + 3.0 / z, top_left.y + 14.0 / z), str(gx),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
	var first_y := int(ceilf(float(top_cell) / major)) * major
	for gy in range(first_y, bottom_cell + 1, major):
		var sy := gy * CELL
		draw_string(_font, Vector2(top_left.x + 3.0 / z, sy - 3.0 / z), str(gy),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _draw_links(z: float) -> void:
	var lw := 1.0 / z
	for link in board.links:
		var a := board.get_component(int(link["a"]))
		var b := board.get_component(int(link["b"]))
		if a.is_empty() or b.is_empty():
			continue
		var pa := board.port_info(a, String(link["a_port"]))
		var pb := board.port_info(b, String(link["b_port"]))
		if pa.is_empty() or pb.is_empty():
			continue
		var pts := WireRouter.link_points(pa, pb, link["path"])
		if pts.size() < 2:
			continue
		var kind := String(pa["kind"])
		var col := ComponentDef.kind_color(kind)
		var blocked := bool(link.get("blocked", false))
		if blocked:
			col = Color(1.0, 0.3, 0.35, 0.8)
		# Тёмная подложка + цветной провод.
		draw_polyline(pts, Color(0.02, 0.04, 0.05, 0.85), maxf(4.0, 5.0 * lw))
		draw_polyline(pts, col.darkened(0.25), maxf(2.0, 3.0 * lw))
		draw_polyline(pts, col, maxf(1.0, 1.4 * lw))
		# Контактные площадки на изгибах.
		for i in range(1, pts.size() - 1):
			draw_circle(pts[i], maxf(1.5, 2.2 * lw), col)
		# Маркеры у портов.
		draw_circle(pa["anchor"], maxf(2.0, 3.0 * lw), col)
		draw_circle(pb["anchor"], maxf(2.0, 3.0 * lw), col)
		if kind == "power":
			draw_circle(pa["anchor"], maxf(1.0, 1.2 * lw), Color(0.1, 0.07, 0.02))
		if blocked:
			var mid := pts[int(pts.size() / 2)]
			draw_circle(mid, maxf(3.0, 5.0 * lw), Color(0.9, 0.2, 0.25))


func _draw_wire_preview(z: float) -> void:
	if wire_from.is_empty():
		return
	var start: Vector2 = wire_from["anchor"]
	var out_cell: Vector2i = wire_from["outward"]
	var out_pos := (Vector2(out_cell) + Vector2(0.5, 0.5)) * CELL
	var col := ComponentDef.kind_color(String(wire_from["kind"]))
	var pts := PackedVector2Array([start, out_pos])
	var target := mouse_world
	var compatible_target := false
	if not hovered_port.is_empty() and int(hovered_port["comp_id"]) != int(wire_from["comp_id"]):
		compatible_target = String(hovered_port["kind"]) == String(wire_from["kind"])
		if compatible_target:
			var target_cell: Vector2i = hovered_port["outward"]
			var res := WireRouter.route(board.occupied_cells(), out_cell, target_cell)
			var cells: Array = res["path"]
			for i in range(1, cells.size()):
				pts.append((Vector2(cells[i]) + Vector2(0.5, 0.5)) * CELL)
			pts.append(hovered_port["anchor"])
			target = hovered_port["anchor"]
	else:
		var mouse_cell := Vector2i(floori(mouse_world.x / CELL), floori(mouse_world.y / CELL))
		var mouse_center := (Vector2(mouse_cell) + Vector2(0.5, 0.5)) * CELL
		pts.append(Vector2(out_pos.x, mouse_center.y))
		pts.append(mouse_world)
		target = mouse_world
	var draw_col := col if compatible_target else Color(col.r, col.g, col.b, 0.6)
	draw_polyline(pts, Color(0.02, 0.04, 0.05, 0.8), maxf(3.0, 4.0 / z))
	draw_polyline(pts, draw_col, maxf(1.0, 2.0 / z))
	draw_circle(target, maxf(3.0, 5.0 / z), draw_col)


# ---------------------------------------------------------------------------
# Оверлей: призрак установки и подсветка портов
# ---------------------------------------------------------------------------

func draw_overlay(canvas: CanvasItem) -> void:
	if board == null:
		return
	var z := camera.zoom.x
	var t := Time.get_ticks_msec() / 1000.0

	if not wire_from.is_empty():
		var kind := String(wire_from["kind"])
		for comp in board.components:
			for info in board.world_ports(comp):
				if int(info["comp_id"]) == int(wire_from["comp_id"]):
					continue
				var compatible := String(info["kind"]) == kind
				var pos: Vector2 = info["anchor"]
				if compatible:
					var pulse := 0.5 + 0.5 * sin(t * 6.0)
					var col := ComponentDef.kind_color(kind)
					canvas.draw_arc(pos, (10.0 + pulse * 3.0) / z, 0, TAU, 22, col, 2.0 / z)
					if not hovered_port.is_empty() and int(hovered_port["comp_id"]) == int(info["comp_id"]) \
							and String(hovered_port["name"]) == String(info["name"]):
						canvas.draw_circle(pos, 7.0 / z, Color(col.r, col.g, col.b, 0.35))
				else:
					canvas.draw_circle(pos, 2.5 / z, Color(0.5, 0.5, 0.5, 0.35))

	if placing_def_id != "" and drag.is_empty() and wire_from.is_empty():
		_draw_ghost(canvas, z)

	if not drag.is_empty():
		var valid := bool(drag.get("valid", true))
		var col := Color("#39ff88") if valid else Color("#ff5566")
		var comp := board.get_component(int(drag["id"]))
		if not comp.is_empty():
			var d := board.def_of(comp)
			var cell: Vector2i = drag["new_cell"]
			var rect := Rect2(Vector2(cell) * CELL, Vector2(d.rotated_size(int(comp["rot"]))) * CELL)
			canvas.draw_rect(rect.grow(-2.0 / z), Color(col.r, col.g, col.b, 0.55), false, 2.0 / z)
			if not valid:
				canvas.draw_rect(rect.grow(-2.0 / z), Color(1, 0.2, 0.3, 0.12))


func _draw_ghost(canvas: CanvasItem, z: float) -> void:
	var d := ComponentLibrary.get_def(placing_def_id)
	if d == null:
		return
	var sz := d.rotated_size(placing_rot)
	var valid := board.can_place(d.id, hover_cell, placing_rot)
	var col := Color("#39ff88") if valid else Color("#ff5566")
	var rect := Rect2(Vector2(hover_cell) * CELL, Vector2(sz) * CELL)
	canvas.draw_rect(rect.grow(-4.0), Color(col.r, col.g, col.b, 0.10))
	canvas.draw_rect(rect.grow(-4.0), col, false, 2.0 / z)
	for port in d.ports:
		var cell := d.port_cell(port, placing_rot)
		var dir := d.port_dir(port, placing_rot)
		var pos := Vector2(hover_cell) * CELL + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL \
			+ Vector2(dir) * (CELL * 0.5)
		canvas.draw_circle(pos, 4.0, ComponentDef.kind_color(String(port.get("kind", ""))))
	canvas.draw_string(_font, Vector2(rect.position.x, rect.position.y - 8.0 / z),
		"%s · %d°" % [d.display_name, placing_rot * 90], HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(clampf(11.0 / z, 9.0, 26.0)), col)
