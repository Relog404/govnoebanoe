extends PanelContainer

# Список компонентов с drag&drop на плату. Источник истины — PART_LIBRARY в board_editor.
const EDITOR_PATH := "res://board/board_editor.gd"
signal item_selected(scene_path: String)
var _items: Array[Dictionary] = []

func _ready() -> void:
	var editor_script: Script = load(EDITOR_PATH)
	var library: Dictionary = editor_script.get_script_constant_map().get("PART_LIBRARY", {})
	var box := $VBox
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for name: String in library:
		var item_script: Script = load("res://ui/library_item.gd")
		var b: Button = item_script.new(name, library[name])
		b.custom_minimum_size = Vector2(118, 40)
		b.pressed.connect(_on_item.bind(library[name]))
		grid.add_child(b)
		_items.append({"name": name, "path": library[name]})
	var scroll := ScrollContainer.new()
	scroll.name = "List"
	scroll.custom_minimum_size = Vector2(260, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	box.add_child(scroll)
	box.move_child(scroll, 1)
	$VBox/Tip.text = "Кликни — деталь в руке (ПКМ — отмена).\nИли перетащи на плату."

func _on_item(path: String) -> void:
	item_selected.emit(path)
