extends PanelContainer

# Редактор пользовательской ISA: JSON → IsaLoader.compile_isa.
var _source: TextEdit
var _report: Label
var _path: LineEdit
var _current_isa: Dictionary = {}

func _ready() -> void:
	var box: VBoxContainer = $VBox
	var path_row := HBoxContainer.new()
	_path = LineEdit.new()
	_path.text = "res://data/isa/mini_isa.json"
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.tooltip_text = "Куда сохранить/откуда загрузить (res:// или user://)"
	path_row.add_child(_path)
	var load_btn := Button.new()
	load_btn.text = "Загрузить"
	load_btn.pressed.connect(_on_load)
	path_row.add_child(load_btn)
	var reset_btn := Button.new()
	reset_btn.text = "Пример MINI-8"
	reset_btn.pressed.connect(_on_reset)
	path_row.add_child(reset_btn)
	box.add_child(path_row)
	_source = TextEdit.new()
	_source.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_source.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_source.tooltip_text = '{ "name": "…", "registers": 8, "instructions": [ {"name":"NOP","code":0,"args":[],"do":[["nop"]]} ] }'
	box.add_child(_source)
	var actions := HBoxContainer.new()
	var compile_btn := Button.new()
	compile_btn.text = "Скомпилировать ISA"
	compile_btn.pressed.connect(_on_compile)
	actions.add_child(compile_btn)
	var save_btn := Button.new()
	save_btn.text = "Сохранить"
	save_btn.pressed.connect(_on_save)
	actions.add_child(save_btn)
	box.add_child(actions)
	_report = Label.new()
	_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report.custom_minimum_size = Vector2(0, 34)
	box.add_child(_report)
	_on_reset()

func _on_reset() -> void:
	var f := FileAccess.open("res://data/isa/mini_isa.json", FileAccess.READ)
	_source.text = f.get_as_text() if f else "{\n  \"instructions\": []\n}"

func _on_load() -> void:
	var f := FileAccess.open(_path.text.strip_edges(), FileAccess.READ)
	if f:
		_source.text = f.get_as_text()
		_report.text = "Загружено: " + _path.text
	else:
		_report.text = "Не открыть: " + _path.text

func _on_compile() -> void:
	_current_isa = IsaLoader.compile_isa(_source.text)
	if _current_isa.get("ok", false):
		_report.text = "ISA «%s» скомпилирована: регистров %d, инструкций %d." % [
			JSON.parse_string(_source.text).get("name", "?"), int(_current_isa.registers),
			_current_isa.names.size()]
		_report.add_theme_color_override("font_color", Color(0.55, 1.0, 0.75))
	else:
		_report.text = "Ошибка (строка %d): %s" % [int(_current_isa.get("line", 0)), _current_isa.get("error", "?")]
		_report.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))

func _on_save() -> void:
	_on_compile()
	if not _current_isa.get("ok", false):
		return
	var path := _path.text.strip_edges()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(_source.text)
		_report.text += " Сохранено: " + path
	else:
		_report.text += " Сохранить не удалось: " + path

func current_isa() -> Dictionary:
	return _current_isa
