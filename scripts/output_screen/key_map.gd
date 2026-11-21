class_name KeyMap
extends RefCounted
## Превращает InputEventKey в стабильные имена клавиш для программ чипа.
## Программист пишет key_down("W"), key_pressed("SPACE"), key_down("LEFT") и т.д.

static func from_event(event: InputEventKey) -> String:
	var kc: int = event.keycode
	if kc == 0:
		kc = event.physical_keycode
	return from_keycode(kc)


const SPECIAL_KEYS := {
	KEY_SPACE: "SPACE",
	KEY_ENTER: "ENTER",
	KEY_KP_ENTER: "ENTER",
	KEY_ESCAPE: "ESC",
	KEY_TAB: "TAB",
	KEY_BACKSPACE: "BACKSPACE",
	KEY_DELETE: "DELETE",
	KEY_INSERT: "INSERT",
	KEY_LEFT: "LEFT",
	KEY_RIGHT: "RIGHT",
	KEY_UP: "UP",
	KEY_DOWN: "DOWN",
	KEY_SHIFT: "SHIFT",
	KEY_CTRL: "CTRL",
	KEY_ALT: "ALT",
	KEY_META: "META",
	KEY_CAPSLOCK: "CAPSLOCK",
	KEY_HOME: "HOME",
	KEY_END: "END",
	KEY_PAGEUP: "PAGEUP",
	KEY_PAGEDOWN: "PAGEDOWN",
	KEY_PAUSE: "PAUSE",
	KEY_PRINT: "PRINT",
	KEY_MENU: "MENU",
	KEY_F1: "F1",
	KEY_F2: "F2",
	KEY_F3: "F3",
	KEY_F4: "F4",
	KEY_F5: "F5",
	KEY_F6: "F6",
	KEY_F7: "F7",
	KEY_F8: "F8",
	KEY_F9: "F9",
	KEY_F10: "F10",
	KEY_F11: "F11",
	KEY_F12: "F12",
	KEY_MINUS: "MINUS",
	KEY_EQUAL: "EQUAL",
	KEY_COMMA: "COMMA",
	KEY_PERIOD: "PERIOD",
	KEY_SLASH: "SLASH",
	KEY_SEMICOLON: "SEMICOLON",
	KEY_APOSTROPHE: "APOSTROPHE",
	KEY_BRACKETLEFT: "BRACKETL",
	KEY_BRACKETRIGHT: "BRACKETR",
	KEY_BACKSLASH: "BACKSLASH",
	KEY_QUOTELEFT: "GRAVE",
}


static func from_keycode(kc: int) -> String:
	if SPECIAL_KEYS.has(kc):
		return SPECIAL_KEYS[kc]
	if kc >= KEY_A and kc <= KEY_Z:
		return char(kc)
	if kc >= KEY_0 and kc <= KEY_9:
		return char(kc)
	var s := OS.get_keycode_string(kc)
	return normalize(s)


static func normalize(name: String) -> String:
	var s := name.strip_edges().to_upper()
	match s:
		"", "NONE":
			return ""
		"ESCAPE":
			return "ESC"
		"RETURN":
			return "ENTER"
		"SPACEBAR", " ":
			return "SPACE"
		"CONTROL", "LEFTCONTROL", "RIGHTCONTROL", "CMDORCTRL", "COMMANDORCONTROL":
			return "CTRL"
		"LEFTSHIFT", "RIGHTSHIFT":
			return "SHIFT"
		"LEFTARROW", "ARROWLEFT":
			return "LEFT"
		"RIGHTARROW", "ARROWRIGHT":
			return "RIGHT"
		"UPARROW", "ARROWUP":
			return "UP"
		"DOWNARROW", "ARROWDOWN":
			return "DOWN"
		"DEL":
			return "DELETE"
		"INS":
			return "INSERT"
		"PGUP":
			return "PAGEUP"
		"PGDN":
			return "PAGEDOWN"
	return s
