class_name ComponentLibrary
extends RefCounted
## Автоматически собирает все ComponentDef из res://resources/components/.
## Благодаря этому новый .tres сразу появляется в палитре — без правки кода.

const COMPONENTS_DIR := "res://resources/components"

static var _defs: Dictionary = {}        # id -> ComponentDef
static var _order: Array[String] = []    # стабильный порядок для UI
static var _loaded := false

const CATEGORY_ORDER := ["power", "compute", "memory", "io", "cooling", "support", "output"]


static func load_all(force_reload: bool = false) -> void:
	if _loaded and not force_reload:
		return
	_defs.clear()
	_order.clear()
	_loaded = true

	var files := _list_component_files()
	for file_name in files:
		var path := COMPONENTS_DIR + "/" + file_name
		var res: Resource = load(path)
		if res == null or not (res is ComponentDef):
			push_warning("ComponentLibrary: %s is not a ComponentDef" % path)
			continue
		var def := res as ComponentDef
		if def.id.strip_edges() == "":
			def.id = file_name.get_basename()
		if _defs.has(def.id):
			push_warning("ComponentLibrary: duplicate component id '%s'" % def.id)
			continue
		_defs[def.id] = def
		_order.append(def.id)

	# Сортируем по категории, затем по имени — предсказуемая палитра.
	_order.sort_custom(func(a: String, b: String) -> bool:
		var da: ComponentDef = _defs[a]
		var db: ComponentDef = _defs[b]
		var ca := CATEGORY_ORDER.find(da.category)
		var cb := CATEGORY_ORDER.find(db.category)
		if ca == cb:
			return da.display_name.naturalnocasecmp_to(db.display_name) < 0
		return ca < cb
	)

	if _order.is_empty():
		push_error("ComponentLibrary: no components found in %s" % COMPONENTS_DIR)


static func _list_component_files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(COMPONENTS_DIR)
	if dir == null:
		push_error("ComponentLibrary: cannot open %s" % COMPONENTS_DIR)
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			out.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func ids() -> Array[String]:
	load_all()
	return _order.duplicate()


static func all() -> Array:
	load_all()
	var out: Array = []
	for id in _order:
		out.append(_defs[id])
	return out


static func get_def(id: String) -> ComponentDef:
	load_all()
	return _defs.get(id, null)


static func has_def(id: String) -> bool:
	load_all()
	return _defs.has(id)


static func by_category(category: String) -> Array:
	var out: Array = []
	for def in all():
		if def.category == category:
			out.append(def)
	return out
