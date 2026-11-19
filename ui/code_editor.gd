extends PanelContainer

# CodeEdit + подсветка из ISA + «Прошить» (образ → RAM чипа → «Старт»).
signal image_flashed(chip_id: String, image: Array)
var _asm: CodeEdit
var _isa_path: LineEdit
var _chip_id: LineEdit
var _status: Label
var _state_label: Label
var _isa: Dictionary = {}
var _last_image: Array = []
const DEFAULT_ASM := "; MINI-8: сумма порта 0 и 5, результат на порт 1\nstart:\n    IN  R0, 0\n    LIT R1, 5\n    ADD R0, R1\n    ST  0x80, R0\n    LD  R2, 0x80\n    OUT 1, R2\n    HALT\n"

func _ready() -> void:
	var box: VBoxContainer = $VBox
	# Выбор и загрузка ISA
	var isa_row := HBoxContainer.new()
	_isa_path = LineEdit.new()
	_isa_path.text = "res://data/isa/mini_isa.json"
	_isa_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	isa_row.add_child(_isa_path)
	var isa_btn := Button.new()
	isa_btn.text = "ISA"
	isa_btn.tooltip_text = "Загрузить и скомпилировать ISA"
	isa_btn.pressed.connect(_load_isa)
	isa_row.add_child(isa_btn)
	box.add_child(isa_row)
	_asm = CodeEdit.new()
	_asm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asm.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_asm.text = DEFAULT_ASM
	_asm.gutters_draw_line_numbers = true
	box.add_child(_asm)
	# Чип и транспорт
	var chip_row := HBoxContainer.new()
	var chip_label := Label.new()
	chip_label.text = "Чип:"
	chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_row.add_child(chip_label)
	_chip_id = LineEdit.new()
	_chip_id.text = "U1"
	_chip_id.custom_minimum_size = Vector2(70, 0)
	chip_row.add_child(_chip_id)
	for pair in [["Проверить", _on_check], ["Собрать", _on_check], ["Прошить", _on_flash], ["Старт", _on_start], ["Сброс", _on_reset_chip]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		chip_row.add_child(b)
	box.add_child(chip_row)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 20)
	box.add_child(_status)
	_state_label = Label.new()
	_state_label.add_theme_color_override("font_color", Color(0.62, 1.0, 0.83))
	box.add_child(_state_label)
	var poll := Timer.new()
	poll.wait_time = 0.25
	poll.autostart = true
	poll.timeout.connect(_poll_state)
	add_child(poll)
	_load_isa()

func _load_isa() -> void:
	_isa = IsaLoader.load_isa(_isa_path.text.strip_edges())
	if not _isa.get("ok", false):
		_status.text = "Ошибка ISA: %s" % _isa.get("error", "?")
		return
	_status.text = "ISA «%s» загружена." % JSON.parse_string(FileAccess.get_file_as_string(_isa_path.text.strip_edges())).get("name", "?")
	var hl := CodeHighlighter.new()
	for mnemonic: String in _isa.names:
		hl.add_keyword_color(mnemonic, Color(0.55, 0.85, 1.0))
	for i in int(_isa.registers):
		hl.add_keyword_color("R%d" % i, Color(1.0, 0.85, 0.45))
	hl.add_keyword_color("HALT", Color(1.0, 0.55, 0.5))
	hl.add_color_region(";", "", Color(0.42, 0.50, 0.46), true)
	_asm.syntax_highlighter = hl

func _assemble() -> Dictionary:
	if not _isa.get("ok", false):
		_load_isa()
		if not _isa.get("ok", false):
			return _isa
	return IsaLoader.assemble(_asm.text, _isa)

func _on_check() -> void:
	var res := _assemble()
	if res.get("ok", false):
		_last_image = res.bytes
		_status.text = "Собрано: %d байт." % res.bytes.size()
		_status.add_theme_color_override("font_color", Color(0.55, 1.0, 0.75))
	else:
		_status.text = "Ошибка (строка %d): %s" % [int(res.get("line", 0)), res.get("error", "?")]
		_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))

func _on_flash() -> void:
	_on_check()
	if _last_image.is_empty():
		return
	var part: Node3D = SimRegistry.get_part(_chip_id.text.strip_edges())
	if part == null:
		_status.text = "Чипа «%s» нет на плате (проверь id в inspect)." % _chip_id.text
		return
	part.on_event("flash", {"bytes": _last_image})
	image_flashed.emit(_chip_id.text.strip_edges(), _last_image)
	part.on_event("start")
	_status.text += " Прошито и запущено на %s." % part.component_id

func _on_start() -> void:
	var part: Node3D = SimRegistry.get_part(_chip_id.text.strip_edges())
	if part:
		part.on_event("start")
		_status.text = "Старт."

func _on_reset_chip() -> void:
	var part: Node3D = SimRegistry.get_part(_chip_id.text.strip_edges())
	if part:
		part.on_event("reset")
		_status.text = "Сброс."

func _poll_state() -> void:
	var part: Node3D = SimRegistry.get_part(_chip_id.text.strip_edges())
	if part == null or not part.get("state") is Dictionary:
		_state_label.text = ""
		return
	var s: Dictionary = part.state
	if not s.has("pc"):
		_state_label.text = ""
		return
	_state_label.text = "PC=%d  циклов=%d  регистры=%s%s" % [int(s.pc), int(s.get("cycles", 0)), str(s.get("reg", [])),
		("  ·  СТОП: " + str(s.get("fault"))) if not str(s.get("fault", "")).is_empty() else ""]

func last_image() -> Array:
	return _last_image
