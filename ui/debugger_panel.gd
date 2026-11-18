extends PanelContainer

# Отладка: Signals (waveform) / Trace / Memory / Breakpoints / Snapshots(JSON).
const Wave = preload("res://ui/waveform.gd")
var _wave: Control
var _net_row: LineEdit
var _trace: Tree
var _memory: GridContainer
var _mem_title: Label
var _breaks: LineEdit
var _breaks_on: CheckButton
var _snap_status: Label
var _breakpoints: Array[int] = []
signal breakpoint_hit(pc: int)

func _ready() -> void:
	var tabs := TabContainer.new()
	add_child(tabs)
	_build_signals(tabs)
	_build_trace(tabs)
	_build_memory(tabs)
	_build_breakpoints(tabs)
	_build_snapshots(tabs)
	DebugHooks.on_instruction.connect(_on_instruction)
	var first := [true]
	DebugHooks.on_signal_change.connect(func(_t: int, net: String, _s: Dictionary) -> void:
		if first[0]:
			first[0] = false
			_wave.track(net))

func _build_signals(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Signals"
	tabs.add_child(tab)
	var row := HBoxContainer.new()
	_net_row = LineEdit.new()
	_net_row.placeholder_text = "R1.B, Q1.C, U1.P3…"
	_net_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_net_row.text_submitted.connect(func(_t: String) -> void: _on_add_net())
	row.add_child(_net_row)
	var add := Button.new()
	add.text = "Смотреть"
	add.pressed.connect(_on_add_net)
	row.add_child(add)
	tab.add_child(row)
	_wave = Wave.new()
	_wave.custom_minimum_size = Vector2(360, 220)
	_wave.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(_wave)

func _on_add_net() -> void:
	_wave.track(_net_row.text.strip_edges())
	_net_row.text = ""

func _build_trace(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Trace"
	tabs.add_child(tab)
	_trace = Tree.new()
	_trace.columns = 5
	_trace.set_column_title(0, "Такт")
	_trace.set_column_title(1, "Чип")
	_trace.set_column_title(2, "PC")
	_trace.set_column_title(3, "Инстр.")
	_trace.set_column_title(4, "Регистры")
	_trace.column_titles_visible = true
	_trace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(_trace)
	var clear := Button.new()
	clear.text = "Очистить"
	clear.pressed.connect(func() -> void: _trace.clear())
	tab.add_child(clear)

func _on_instruction(tick: int, chip: String, pc: int, mnemonic: String, registers: Array) -> void:
	var item := _trace.create_item(null, 0) if _trace.get_root() == null else _trace.create_item(_trace.get_root())
	item.set_text(0, str(tick))
	item.set_text(1, chip)
	item.set_text(2, "0x%02X" % pc)
	item.set_text(3, mnemonic)
	var regs := PackedStringArray()
	for i in registers.size():
		regs.append("R%d=%d" % [i, int(registers[i])])
	item.set_text(4, ", ".join(regs))
	# Ограничение истории
	var root := _trace.get_root()
	if root:
		var count := 0
		var child := root.get_first_child()
		while child:
			count += 1
			child = child.get_next()
		if count > 300:
			var first := root.get_first_child()
			first.free()
	if _breaks_on.button_pressed and pc in _breakpoints:
		SimClock.playing = false
		breakpoint_hit.emit(pc)

func _build_memory(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Memory"
	tabs.add_child(tab)
	_mem_title = Label.new()
	_mem_title.text = "Последний прошитый образ (16 байт на колонку)"
	_mem_title.add_theme_color_override("font_color", Color(0.62, 0.68, 0.63))
	tab.add_child(_mem_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(scroll)
	_memory = GridContainer.new()
	_memory.columns = 17
	scroll.add_child(_memory)

func show_image(chip_id: String, image: Array) -> void:
	_mem_title.text = "Образ «%s», %d байт" % [chip_id, image.size()]
	for child in _memory.get_children():
		child.free()
	var header := Label.new()
	header.text = "   "
	_memory.add_child(header)
	for col in 16:
		var col_label := Label.new()
		col_label.text = "%02X" % col
		col_label.add_theme_color_override("font_color", Color(0.52, 0.68, 0.63))
		_memory.add_child(col_label)
	for row in ceili(256.0 / 16.0):
		var row_label := Label.new()
		row_label.text = "%02X" % (row * 16)
		row_label.add_theme_color_override("font_color", Color(0.52, 0.68, 0.63))
		_memory.add_child(row_label)
		for col in 16:
			var i := row * 16 + col
			var cell := Label.new()
			cell.text = "%02X" % int(image[i]) if i < image.size() else "··"
			cell.add_theme_color_override("font_color", Color(0.75, 0.9, 0.82) if i < image.size() else Color(0.3, 0.36, 0.33))
			_memory.add_child(cell)

func _build_breakpoints(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Breakpoints"
	tabs.add_child(tab)
	_breaks = LineEdit.new()
	_breaks.placeholder_text = "PC: 0x08, 0x0C, 12 …"
	tab.add_child(_breaks)
	_breaks_on = CheckButton.new()
	_breaks_on.text = "Останавливать симуляцию на breakpoint"
	_breaks_on.button_pressed = true
	_breaks_on.toggled.connect(func(_on: bool) -> void: _reparse_breaks())
	tab.add_child(_breaks_on)
	var note := Label.new()
	note.text = "Сработает на следующей же инструкции с указанным PC."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.52, 0.68, 0.63))
	tab.add_child(note)
	_breaks.text_changed.connect(func(_t: String) -> void: _reparse_breaks())

func _reparse_breaks() -> void:
	_breakpoints.clear()
	for token in _breaks.text.split(","):
		var t := token.strip_edges().to_lower()
		var v := -1
		if t.begins_with("0x"):
			v = t.hex_to_int()
		elif t.is_valid_int():
			v = t.to_int()
		if v >= 0 and v <= 255:
			_breakpoints.append(v)

func _build_snapshots(tabs: TabContainer) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Snapshots"
	tabs.add_child(tab)
	var save_btn := Button.new()
	save_btn.text = "Снимок → user://sim_snapshot.json"
	save_btn.pressed.connect(_on_save)
	tab.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Откатить user://sim_snapshot.json"
	load_btn.pressed.connect(_on_restore)
	tab.add_child(load_btn)
	var hint := Label.new()
	hint.text = "Снимок привязан к текущей сборке платы: после правки топологии откат будет отклонён."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.52, 0.68, 0.63))
	tab.add_child(hint)
	_snap_status = Label.new()
	tab.add_child(_snap_status)

func _on_save() -> void:
	var f := FileAccess.open("user://sim_snapshot.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(SimClock.snapshot(), "", true, true))
		_snap_status.text = "Сохранено, такт %d." % SimClock.now

func _on_restore() -> void:
	var f := FileAccess.open("user://sim_snapshot.json", FileAccess.READ)
	if f == null:
		_snap_status.text = "Нет файла снимка."
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary and SimClock.restore(data):
		_snap_status.text = "Откачено к такту %d." % SimClock.now
	else:
		_snap_status.text = "Откат отклонён: сборка платы не совпадает со снимком или файл повреждён."
