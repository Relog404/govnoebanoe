extends Node3D

# Мир: верстак процедурный, камера, свет, HUD, палитра, автосохранение.
var editor: Node3D
var _yaw := -0.55
var _pitch := 0.74
var _base_dist := 0.34   # Долли обычным колесом вне лупы.
var _focus := Vector3.ZERO # Точка, вокруг которой работает лупа (игнорируется при ×1).
var _drag := false

const PANEL_NODES := ["IsaEditor", "CodeEditor", "DebuggerPanel"]

func _ready() -> void:
	editor = get_node("BoardEditor")
	var library: Control = $Studio/ComponentLibrary
	$Hud.set_library(library)
	library.item_selected.connect(_on_library_selected)
	$Studio/DropCatcher.dropped.connect(_on_drop)
	var code: Control = $Studio/CodeEditor
	code.image_flashed.connect(func(chip_id: String, image: Array) -> void: $Studio/DebuggerPanel.show_image(chip_id, image))
	_wire_panel_toggles()
	ToolManager.zoom_changed.connect(_on_zoom_changed)
	_make_board_plate()
	_restore_autosave()
	var autosave := Timer.new()
	autosave.wait_time = 60.0
	autosave.autostart = true
	autosave.timeout.connect(_autosave)
	add_child(autosave)
	_update_camera()
	$Hud.toast("1…5 — инструменты · ЛКМ — применить · ПКМ — отмена · R — поворот")

# ---------- Плита платы ----------

func _make_board_plate() -> void:
	var w := 12 * 10
	var h := 8 * 10
	var img := Image.create(w * 4, h * 4, false, Image.FORMAT_RGB8)
	var base := Color("0f5142")
	var line := Color("2a6b58")
	var drill := Color("0a382d")
	for y in img.get_height():
		for x in img.get_width():
			var c := base
			if x % 40 < 2 or y % 40 < 2:
				c = line
			var cx := x % 40
			var cy := y % 40
			if (cx == 20 and cy == 20) or (x % 80 == 10 and cy == 20):
				c = drill
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.12, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.55
	mat.metallic = 0.05
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0, -0.0008, 0)
	add_child(mi)
	var back := BoxMesh.new()
	back.size = Vector3(0.121, 0.0012, 0.081)
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color("0b3d31")
	back_mat.roughness = 0.7
	var back_mi := MeshInstance3D.new()
	back_mi.mesh = back
	back_mi.material_override = back_mat
	back_mi.position = Vector3(0, -0.0015, 0)
	add_child(back_mi)

# ---------- Панели ISA / код / отладка ----------

func _wire_panel_toggles() -> void:
	var studio := $Studio
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	bar.offset_left = -260.0
	bar.offset_right = -12.0
	bar.offset_top = 8.0
	bar.add_theme_constant_override("separation", 6)
	studio.add_child(bar)
	for pair: Array in [["IsaEditor", "ISA"], ["CodeEditor", "Код"], ["DebuggerPanel", "Отладка"]]:
		var panel: Control = studio.get_node(pair[0])
		panel.visible = false
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.anchor_top = 0.5
		panel.anchor_bottom = 0.5
		panel.offset_left = -530.0
		panel.offset_right = -10.0
		panel.offset_top = -260.0
		panel.offset_bottom = 260.0
		var toggle := Button.new()
		toggle.text = pair[1]
		toggle.toggle_mode = true
		toggle.custom_minimum_size = Vector2(78, 34)
		toggle.toggled.connect(func(on: bool) -> void:
			panel.visible = on
			if on:
				for other: String in PANEL_NODES:
					if other != pair[0]:
						studio.get_node(other).visible = false)
		bar.add_child(toggle)

# ---------- Палитра ----------

func _on_library_selected(scene_path: String) -> void:
	editor.start_carry_scene(scene_path)

func _on_drop(scene_path: String, mouse: Vector2) -> void:
	editor.place_scene_immediately(scene_path, mouse)

# ---------- Камера ----------

# Лупа: то же колесо, но с якорем на точке под курсором и ступенями ×1/2/4/8.
func _on_zoom_changed(factor: int, pivot: Vector3, locked: bool) -> void:
	if factor == 1 and not locked:
		_focus = Vector3.ZERO
	elif pivot != Vector3.ZERO:
		_focus = pivot
	_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = event.pressed
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and ToolManager.current != ToolManager.Tool.LOUPE:
			_base_dist = clampf(_base_dist * 0.88, 0.16, 0.85)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and ToolManager.current != ToolManager.Tool.LOUPE:
			_base_dist = clampf(_base_dist * 1.14, 0.16, 0.85)
			_update_camera()
	elif event is InputEventMouseMotion and _drag:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch + event.relative.y * 0.004, 0.25, 1.25)
		_update_camera()

func _update_camera() -> void:
	var camera: Camera3D = $CameraRig/Camera3D
	var dist := _base_dist / float(ToolManager.zoom if ToolManager.zoom >= 1 else 1)
	var focus := _focus if ToolManager.zoom > 1 or ToolManager.locked else Vector3(0, -0.004, 0)
	var offset := Vector3(
		dist * cos(_pitch) * sin(_yaw),
		dist * sin(_pitch),
		dist * cos(_pitch) * cos(_yaw))
	camera.global_position = focus + offset
	camera.look_at(focus, Vector3.UP)

# ---------- Автосохранение ----------

func _autosave() -> void:
	editor.save_board("user://autosave.board.tres")
	var f := FileAccess.open("user://autosave_sim.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(SimClock.snapshot(), "", true, true))

func _restore_autosave() -> void:
	if FileAccess.file_exists("user://autosave.board.tres"):
		editor.load_board("user://autosave.board.tres")
		$Hud.toast("Автосохранение загружено.")
