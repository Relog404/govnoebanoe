class_name ChipBoard
extends RefCounted
## Модель платы: компоненты, связи портов, ортогональная трассировка.
## Ничего не рисует и не знает про UI — только данные и геометрия.

signal changed

## Размер клетки в пикселях мира.
const CELL := 64.0

var components: Array[Dictionary] = []
var links: Array[Dictionary] = []
var next_component_id := 1
var next_link_id := 1


# ---------------------------------------------------------------------------
# Компоненты
# ---------------------------------------------------------------------------

func add_component(def_id: String, cell: Vector2i, rot: int = 0) -> int:
	if ComponentLibrary.get_def(def_id) == null:
		push_warning("ChipBoard: unknown component '%s'" % def_id)
		return -1
	var comp := {
		"id": next_component_id,
		"def_id": def_id,
		"cell": cell,
		"rot": posmod(rot, 4),
	}
	next_component_id += 1
	components.append(comp)
	changed.emit()
	return int(comp["id"])


func remove_component(comp_id: int) -> void:
	for i in range(components.size() - 1, -1, -1):
		if int(components[i]["id"]) == comp_id:
			components.remove_at(i)
			break
	for i in range(links.size() - 1, -1, -1):
		var l: Dictionary = links[i]
		if int(l["a"]) == comp_id or int(l["b"]) == comp_id:
			links.remove_at(i)
	changed.emit()


func get_component(comp_id: int) -> Dictionary:
	for comp in components:
		if int(comp["id"]) == comp_id:
			return comp
	return {}


func def_of(comp: Dictionary) -> ComponentDef:
	if comp.is_empty():
		return null
	return ComponentLibrary.get_def(String(comp["def_id"]))


func component_count() -> int:
	return components.size()


func moved_component(comp_id: int, cell: Vector2i) -> bool:
	var comp := get_component(comp_id)
	if comp.is_empty():
		return false
	if cell == comp["cell"]:
		return false
	comp["cell"] = cell
	changed.emit()
	return true


func rotated_component(comp_id: int) -> bool:
	var comp := get_component(comp_id)
	if comp.is_empty():
		return false
	var d := def_of(comp)
	if d == null:
		return false
	var new_rot := (int(comp["rot"]) + 1) % 4
	if not can_place(d.id, comp["cell"], new_rot, comp_id):
		return false
	comp["rot"] = new_rot
	changed.emit()
	return true


## Можно ли поставить/повернуть компонент в этой области.
func can_place(def_id: String, cell: Vector2i, rot: int, ignore_id: int = -1) -> bool:
	var d := ComponentLibrary.get_def(def_id)
	if d == null:
		return false
	var test_rect := Rect2i(cell, d.rotated_size(rot))
	for other in components:
		if int(other["id"]) == ignore_id:
			continue
		var od := def_of(other)
		if od == null:
			continue
		var other_rect := Rect2i(other["cell"], od.rotated_size(int(other["rot"])))
		if test_rect.intersects(other_rect):
			return false
	return true


## Все занятые клетки (кроме исключённого компонента).
func occupied_cells(exclude_id: int = -1) -> Dictionary:
	var out := {}
	for comp in components:
		if int(comp["id"]) == exclude_id:
			continue
		for c in component_cells(comp):
			out[c] = true
	return out


func component_cells(comp: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := def_of(comp)
	if d == null:
		return out
	var sz := d.rotated_size(int(comp["rot"]))
	var origin: Vector2i = comp["cell"]
	for y in sz.y:
		for x in sz.x:
			out.append(origin + Vector2i(x, y))
	return out


func find_component_at(cell: Vector2i) -> Dictionary:
	for comp in components:
		var d := def_of(comp)
		if d == null:
			continue
		var sz := d.rotated_size(int(comp["rot"]))
		if Rect2i(comp["cell"], sz).has_point(cell):
			return comp
	return {}


## Компонент, у которого клетка совпадает с портом в указанной мировой позиции.
func find_port_at(world_pos: Vector2) -> Dictionary:
	for comp in components:
		for info in world_ports(comp):
			if (info["anchor"] as Vector2).distance_to(world_pos) <= 18.0:
				return info
	return {}


func bounds_cells() -> Rect2i:
	if components.is_empty():
		return Rect2i(-6, -4, 12, 8)
	var r := Rect2i()
	var first := true
	for comp in components:
		var d := def_of(comp)
		if d == null:
			continue
		var cr := Rect2i(comp["cell"], d.rotated_size(int(comp["rot"])))
		if first:
			r = cr
			first = false
		else:
			r = r.merge(cr)
	return r


# ---------------------------------------------------------------------------
# Порты
# ---------------------------------------------------------------------------

## Геометрия всех портов компонента в мировых координатах.
func world_ports(comp: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := def_of(comp)
	if d == null:
		return out
	for p in d.ports:
		out.append(port_info(comp, String(p.get("name", ""))))
	return out


## Геометрия одного порта.
func port_info(comp: Dictionary, port_name: String) -> Dictionary:
	var d := def_of(comp)
	if d == null:
		return {}
	var p := d.get_port(port_name)
	if p.is_empty():
		return {}
	var rot := int(comp["rot"])
	var local_cell := d.port_cell(p, rot)
	var dir := d.port_dir(p, rot)
	var cell: Vector2i = comp["cell"] + local_cell
	var outward: Vector2i = cell + dir
	var center := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
	var anchor := center + Vector2(dir) * (CELL * 0.5)
	return {
		"comp_id": int(comp["id"]),
		"name": port_name,
		"kind": String(p.get("kind", "")),
		"cell": cell,
		"dir": dir,
		"outward": outward,
		"anchor": anchor,
	}


func links_of_port(comp_id: int, port_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in links:
		if int(l["a"]) == comp_id and String(l["a_port"]) == port_name:
			out.append(l)
		elif int(l["b"]) == comp_id and String(l["b_port"]) == port_name:
			out.append(l)
	return out


func link_exists(a_comp: int, a_port: String, b_comp: int, b_port: String) -> bool:
	for l in links:
		if _link_matches(l, a_comp, a_port, b_comp, b_port):
			return true
	return false


func _link_matches(l: Dictionary, a_comp: int, a_port: String, b_comp: int, b_port: String) -> bool:
	var fwd := int(l["a"]) == a_comp and String(l["a_port"]) == a_port \
		and int(l["b"]) == b_comp and String(l["b_port"]) == b_port
	var rev := int(l["a"]) == b_comp and String(l["a_port"]) == b_port \
		and int(l["b"]) == a_comp and String(l["b_port"]) == a_port
	return fwd or rev


## Проверка совместимости портов и создание связи (путь прокладывается отдельно).
func connect_ports(a_comp: int, a_port: String, b_comp: int, b_port: String) -> Dictionary:
	if a_comp == b_comp:
		return {"ok": false, "error": "Нельзя соединить компонент сам с собой"}
	var ca := get_component(a_comp)
	var cb := get_component(b_comp)
	if ca.is_empty() or cb.is_empty():
		return {"ok": false, "error": "Компонент не найден"}
	var pa := port_info(ca, a_port)
	var pb := port_info(cb, b_port)
	if pa.is_empty() or pb.is_empty():
		return {"ok": false, "error": "Порт не найден"}
	if pa["kind"] != pb["kind"]:
		return {"ok": false, "error": "Несовместимые порты: %s ↔ %s" % [
			ComponentDef.kind_name(pa["kind"]), ComponentDef.kind_name(pb["kind"])]}
	if link_exists(a_comp, a_port, b_comp, b_port):
		return {"ok": false, "error": "Эти порты уже соединены"}
	var link := {
		"id": next_link_id,
		"a": a_comp,
		"a_port": a_port,
		"b": b_comp,
		"b_port": b_port,
		"path": [],
		"blocked": false,
	}
	next_link_id += 1
	links.append(link)
	changed.emit()
	return {"ok": true, "error": "", "link": link}


func remove_link(link_id: int) -> void:
	for i in links.size():
		if int(links[i]["id"]) == link_id:
			links.remove_at(i)
			changed.emit()
			return


func set_link_path(link_id: int, path: Array, blocked: bool) -> void:
	for l in links:
		if int(l["id"]) == link_id:
			l["path"] = path
			l["blocked"] = blocked
			return


func clear_links() -> void:
	links.clear()
	changed.emit()


func clear() -> void:
	components.clear()
	links.clear()
	next_component_id = 1
	next_link_id = 1
	changed.emit()


# ---------------------------------------------------------------------------
# Сохранение / загрузка
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var comps: Array = []
	for c in components:
		comps.append({
			"id": int(c["id"]),
			"def_id": String(c["def_id"]),
			"cell": [int(c["cell"].x), int(c["cell"].y)],
			"rot": int(c["rot"]),
		})
	var out_links: Array = []
	for l in links:
		var path_ser: Array = []
		for cell in l["path"]:
			path_ser.append([int(cell.x), int(cell.y)])
		out_links.append({
			"id": int(l["id"]),
			"a": int(l["a"]),
			"a_port": String(l["a_port"]),
			"b": int(l["b"]),
			"b_port": String(l["b_port"]),
			"path": path_ser,
			"blocked": bool(l.get("blocked", false)),
		})
	return {
		"version": 1,
		"components": comps,
		"links": out_links,
		"next_component_id": next_component_id,
		"next_link_id": next_link_id,
	}


func from_dict(data: Dictionary) -> void:
	components.clear()
	links.clear()
	next_component_id = int(data.get("next_component_id", 1))
	next_link_id = int(data.get("next_link_id", 1))
	for cd in data.get("components", []):
		if typeof(cd) != TYPE_DICTIONARY:
			continue
		var def_id := String(cd.get("def_id", ""))
		if ComponentLibrary.get_def(def_id) == null:
			continue
		var cell_arr: Array = cd.get("cell", [0, 0])
		var cell := Vector2i(int(cell_arr[0]), int(cell_arr[1]))
		var comp := {
			"id": int(cd.get("id", next_component_id)),
			"def_id": def_id,
			"cell": cell,
			"rot": posmod(int(cd.get("rot", 0)), 4),
		}
		components.append(comp)
		next_component_id = maxi(next_component_id, int(comp["id"]) + 1)
	for ld in data.get("links", []):
		if typeof(ld) != TYPE_DICTIONARY:
			continue
		var a := int(ld.get("a", -1))
		var b := int(ld.get("b", -1))
		if get_component(a).is_empty() or get_component(b).is_empty():
			continue
		var link := {
			"id": int(ld.get("id", next_link_id)),
			"a": a,
			"a_port": String(ld.get("a_port", "")),
			"b": b,
			"b_port": String(ld.get("b_port", "")),
			"path": [],
			"blocked": bool(ld.get("blocked", false)),
		}
		var path: Array = []
		for pair in ld.get("path", []):
			if typeof(pair) == TYPE_ARRAY and pair.size() >= 2:
				path.append(Vector2i(int(pair[0]), int(pair[1])))
		link["path"] = path
		links.append(link)
		next_link_id = maxi(next_link_id, int(link["id"]) + 1)
	changed.emit()
