extends "res://components/component_base.gd"

# Одноразрядный семисегментный индикатор. Каждый сегмент — светодиод:
# порты a…g и dp, легим по напряжению > 1.65 В (или sig == ONE).
var _segs: Dictionary = {}
var _digits := {
		0: 0b0111111, 1: 0b0000110, 2: 0b1011011, 3: 0b1001111, 4: 0b1100110,
		5: 0b1101101, 6: 0b1111101, 7: 0b0000111, 8: 0b1111111, 9: 0b1101111,
		10: 0b1110111, 11: 0b1111100, 12: 0b0111001, 13: 0b1011110, 14: 0b1111001, 15: 0b1110001,
}

func _init() -> void:
	ports = {"a":"in","b":"in","c":"in","d":"in","e":"in","f":"in","g":"in","dp":"in"}
	state = {"mask": 0}

func size_mm() -> Vector3:
	return Vector3(19.0, 3.0, 12.7)

func pin_layout_mm() -> Dictionary:
	var names := ["a","b","c","d","e","f","g","dp"]
	var out := {}
	for i in names.size():
		out[names[i]] = Vector3((i - 3.5) * 2.54, 0, 6.6)
	return out

func make_mesh() -> Node3D:
	var root := Node3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(19.0, 2.6, 12.7) * MM
	piece(root, body, Vector3.UP * 1.3, stock(Color("14171a"), 0.15, 0.5))
	# Семь сегментов + точка, плюс тонкий рефлектор.
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color("ff3b30")
	lit.emission_enabled = true
	lit.emission = Color("ff3b30")
	lit.emission_energy_multiplier = 2.4
	lit.roughness = 0.35
	var off := stock(Color("241a19"), 0.0, 0.6)
	var seg_defs := {
		"a": [Vector3(0, 2.78, -4.45), Vector3(9.6, 0.75, 1.5)],
		"g": [Vector3(0, 2.78, 0),    Vector3(9.6, 0.75, 1.5)],
		"d": [Vector3(0, 2.78, 4.45), Vector3(9.6, 0.75, 1.5)],
		"f": [Vector3(-5.05, 2.78, -2.25), Vector3(1.5, 0.75, 5.6)],
		"b": [Vector3(5.05, 2.78, -2.25),  Vector3(1.5, 0.75, 5.6)],
		"e": [Vector3(-5.05, 2.78, 2.25),  Vector3(1.5, 0.75, 5.6)],
		"c": [Vector3(5.05, 2.78, 2.25),   Vector3(1.5, 0.75, 5.6)],
	}
	for seg_name: String in seg_defs:
		var def: Array = seg_defs[seg_name]
		var m := BoxMesh.new()
		m.size = def[1] * MM
		_segs[seg_name] = piece(root, m, def[0], off)
		_segs[seg_name].set_meta("on_mat", lit)
		_segs[seg_name].set_meta("off_mat", off)
	var dp := BoxMesh.new()
	dp.size = Vector3(1.5, 0.75, 1.5) * MM
	_segs["dp"] = piece(root, dp, Vector3(7.2, 2.78, 4.45), off)
	_segs["dp"].set_meta("on_mat", lit)
	_segs["dp"].set_meta("off_mat", off)
	return root

func refresh_visual() -> void:
	var mask := int(state.get("mask", 0))
	var names := ["a","b","c","d","e","f","g","dp"]
	for i in names.size():
		var on: bool = (mask & (1 << i)) != 0
		_segs[names[i]].material_override = _segs[names[i]].get_meta("on_mat" if on else "off_mat")

func tick(_at: int) -> void:
	var mask := 0
	var names := ["a","b","c","d","e","f","g","dp"]
	for i in names.size():
		var s := read_pin(names[i])
		var on: bool = (float(s.volts) > 1.65) if s.volts != null else (s.sig == SimBus.Sig.ONE)
		if on:
			mask |= 1 << i
	state.mask = mask
	refresh_visual()

func set_digit(d: int, dp: bool = false) -> void:
	var mask: int = int(_digits.get(d & 0xff, 0))
	if dp:
		mask |= 0x80
	state.mask = mask
	refresh_visual()
