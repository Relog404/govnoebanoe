extends Node

enum Tool { IRON, TWEEZERS, TESTER, LOUPE, CURSOR }
signal tool_changed(tool: int)
signal gesture(action: String, target: Dictionary)
signal probed(pin: String, sample: Dictionary)
signal zoom_changed(factor: int, pivot: Vector3, locked: bool)

var current := Tool.CURSOR
var zoom := 1
var locked := false
var pivot := Vector3.ZERO
var first_pin := ""
var held := ""

func select(tool: int) -> void:
	if tool < Tool.IRON or tool > Tool.CURSOR or tool == current:
		return
	cancel()
	current = tool as Tool
	tool_changed.emit(current)

func cancel() -> void:
	first_pin = ""
	held = ""
	gesture.emit("cancel", {})

func _unhandled_key_input(e: InputEvent) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode >= KEY_1 and e.keycode <= KEY_5:
		select(e.keycode - KEY_1)
		get_viewport().set_input_as_handled()

func set_zoom(factor: int) -> void:
	if factor not in [1, 2, 4, 8]:
		return
	zoom = factor
	zoom_changed.emit(zoom, pivot, locked)

func hover(target: Dictionary) -> void:
	if current == Tool.TESTER:
		var pin: String = str(target.get("pin", ""))
		probed.emit(pin, SimBus.sample(pin))

# Редактор вызывает после raycast, только для мыши, не поглощённой HUD.
# pin — полный id.пин (для дорожки — любой конец), point — мировые метры.
func apply(e: InputEventMouseButton, target: Dictionary) -> void:
	if not e.pressed:
		return
	var key := e.button_index
	var point: Vector3 = target.get("point", Vector3.ZERO)
	var id: String = str(target.get("id", ""))
	var pin: String = str(target.get("pin", ""))
	if current == Tool.LOUPE:
		match key:
			MOUSE_BUTTON_LEFT: locked = true; pivot = point
			MOUSE_BUTTON_RIGHT: locked = false; zoom = 1; pivot = point
			MOUSE_BUTTON_WHEEL_UP: zoom = mini(zoom * 2, 8)
			MOUSE_BUTTON_WHEEL_DOWN: zoom = maxi(zoom >> 1, 1)
			_: return
		if not locked: pivot = point
		zoom_changed.emit(zoom, pivot, locked)
		return  # Лупа ни при каких кнопках не отправляет команд редактирования.
	if key == MOUSE_BUTTON_RIGHT:
		if current == Tool.TWEEZERS and held.is_empty() and not id.is_empty():
			gesture.emit("detach", target)
		else:
			cancel()
	elif key == MOUSE_BUTTON_LEFT:
		match current:
			Tool.IRON:
				if not SimRegistry.has_pin(pin): return
				if first_pin.is_empty():
					first_pin = pin
					gesture.emit("wire_start", target)
				elif SimRegistry.connect_ports(first_pin, pin):
					gesture.emit("wire_end", {"from": first_pin, "to": pin, "point": point})
					first_pin = ""
			Tool.TWEEZERS:
				if held.is_empty() and not id.is_empty():
					held = id
					gesture.emit("take", target)
				elif not held.is_empty() and target.get("can_place", false):
					var drop := target.duplicate()
					drop["id"] = held
					held = ""
					gesture.emit("place", drop)
			Tool.TESTER: hover(target)
			Tool.CURSOR: gesture.emit("inspect", target)
