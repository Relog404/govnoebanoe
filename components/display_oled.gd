extends "res://components/component_base.gd"

# 0.96" OLED 128×64, протокол «параллельная шина + защёлка» (мой вымышленный SSD1306-like):
#   D0..D7 — байт по фронту спада WR (1→0);
#   CD = 0 (команда): 0x00–0x7F — установить колонку, 0x80 — питание выкл (пустой экран), 0x81 — питание вкл;
#   CD = 1 (данные): байт = 8 вертикальных пикселей страницы 0 в колонке, колонка++;
# Формат кадра задаёт ComponentDef.framebuffer_format: "1-bit" | "RGB565" | "Palette".
enum Fmt { ONE_BIT, RGB565, PALETTE }
const W := 128
const H := 64
var _fb: PackedByteArray = PackedByteArray()
var _palette: PackedByteArray = PackedByteArray()
var _viewport: SubViewport
var _screen: TextureRect
var _image: Image
var _format := Fmt.ONE_BIT

func _init() -> void:
	ports = {}
	for i in 8:
		ports["D%d" % i] = "in"
	ports["WR"] = "in"
	ports["CD"] = "in"
	state = {"power": true, "col": 0, "page": 0, "width": W, "height": H, "bytes": 0, "fmt": "1-bit", "wr_prev": 1}

func size_mm() -> Vector3:
	return Vector3(26.0, 3.2, 26.0)

func pin_layout_mm() -> Dictionary:
	var names := ["GND", "VCC", "D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "CD", "WR"]
	var out := {}
	for i in names.size():
		out[names[i]] = Vector3((i - 5.5) * 2.4, 0, 12.7)
	return out

func make_mesh() -> Node3D:
	return make_oled(params)

func make_oled(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var pcb := BoxMesh.new()
	pcb.size = Vector3(26.0, 1.6, 26.0) * MM
	piece(root, pcb, Vector3.UP * 0.9, stock(Color("12222b"), 0.2, 0.62))
	var bezel := BoxMesh.new()
	bezel.size = Vector3(24.0, 0.9, 17.0) * MM
	piece(root, bezel, Vector3.UP * 2.05, stock(Color("050708")))
	return root

func _ready() -> void:
	ports.merge({"GND": "optional", "VCC": "optional"}, true)
	super._ready()
	var fmt := "1-bit"
	if definition and not definition.framebuffer_format.is_empty():
		fmt = definition.framebuffer_format
	state.fmt = fmt
	state.bytes = fb_bytes()
	_format = {"1-bit": Fmt.ONE_BIT, "RGB565": Fmt.RGB565, "Palette": Fmt.PALETTE}.get(fmt, Fmt.ONE_BIT)
	_fb.resize(fb_bytes())
	_fb.fill(0)
	_image = Image.create(W, H, false, Image.FORMAT_RGB8)
	_palette.resize(256 * 4)
	for i in 256:
		_palette[i * 4] = i
		_palette[i * 4 + 1] = i
		_palette[i * 4 + 2] = i
		_palette[i * 4 + 3] = 255
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(W, H)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	var bg := ColorRect.new()
	bg.color = Color("060b10")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(bg)
	_screen = TextureRect.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewport.add_child(_screen)
	add_child(_viewport)
	_render()
	_attach_screen()

# ---------- Протокол на выводах ----------

func _bus_value() -> int:
	var v := 0
	for i in 8:
		var s := read_pin("D%d" % i)
		var bit: int = 1 if ((s.volts != null and float(s.volts) > 1.65) or int(s.sig) == SimBus.Sig.ONE) else 0
		v |= bit << i
	return v

func on_signal(pin: String, sample: Dictionary) -> void:
	if pin != "WR":
		return
	var high: bool = (float(sample.volts) > 1.65) if sample.volts != null else int(sample.sig) == SimBus.Sig.ONE
	if int(state.get("wr_prev", 1)) == 1 and not high:
		_latch_bus()
	state.wr_prev = 1 if high else 0

func _latch_bus() -> void:
	var value := _bus_value()
	var cd_s := read_pin("CD")
	var cd: bool = (float(cd_s.volts) > 1.65) if cd_s.volts != null else int(cd_s.sig) == SimBus.Sig.ONE
	if not cd:
		# Команда
		if value <= 0x7F:
			state.col = value
		elif value == 0x80 or value == 0xAE:
			set_power(false)
		elif value == 0x81 or value == 0xAF:
			set_power(true)
		elif value >= 0xC0 and value <= 0xC7:
			state.page = value & 7
		return
	# Данные: вертикальный столбец 8 px текущей страницы (0xC0–0xC7), колонка++
	var col := int(state.get("col", 0))
	var page := int(state.get("page", 0))
	_defer_render = true
	for row in 8:
		set_pixel(col, page * 8 + row, (value >> row) & 1)
	_defer_render = false
	_render()
	state.col = (col + 1) % W

func set_power(on: bool) -> void:
	state.power = on
	if on:
		_render()
	else:
		_image.fill(Color("060b10"))
		_screen.texture = ImageTexture.create_from_image(_image)
	if _screen_mat != null:
		_screen_mat.emission_enabled = on

var _screen_mat: StandardMaterial3D

# ---------- Кадр ----------

func fb_bytes() -> int:
	match _format:
		Fmt.ONE_BIT: return W * H / 8
		Fmt.RGB565:  return W * H * 2
		_:           return W * H

var _defer_render := false

func set_pixel(x: int, y: int, value: int) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	match _format:
		Fmt.ONE_BIT:
			var i := (y * W + x) >> 3
			var bit := 1 << (x & 7)
			_fb[i] = (_fb[i] & ~bit) | (bit if value != 0 else 0)
		Fmt.RGB565:
			var i := (y * W + x) * 2
			_fb[i] = value & 0xff
			_fb[i + 1] = (value >> 8) & 0xff
		Fmt.PALETTE:
			_fb[y * W + x] = value & 0xff
	if state.get("power", true) and not _defer_render:
		_render()

func get_pixel(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return 0
	match _format:
		Fmt.ONE_BIT: return (_fb[(y * W + x) >> 3] >> (x & 7)) & 1
		Fmt.RGB565: return _fb[(y * W + x) * 2] | (_fb[(y * W + x) * 2 + 1] << 8)
		_: return _fb[y * W + x]

func clear_fb(value: int = 0) -> void:
	_fb.fill(value)
	_render()

func set_palette(index: int, rgba: Color) -> void:
	if index < 0 or index > 255:
		return
	_palette[index * 4] = int(clampf(rgba.r, 0, 1) * 255)
	_palette[index * 4 + 1] = int(clampf(rgba.g, 0, 1) * 255)
	_palette[index * 4 + 2] = int(clampf(rgba.b, 0, 1) * 255)
	_palette[index * 4 + 3] = int(clampf(rgba.a, 0, 1) * 255)
	_render()

func _rgb565(v: int) -> Color:
	return Color(((v >> 11) & 0x1f) / 31.0, ((v >> 5) & 0x3f) / 63.0, (v & 0x1f) / 31.0, 1.0)

func _render() -> void:
	for y in H:
		for x in W:
			var i := y * W + x
			var c: Color
			match _format:
				Fmt.ONE_BIT:
					c = Color("bfe9ff") if get_pixel(x, y) != 0 else Color("060b10")
				Fmt.PALETTE:
					var p := get_pixel(x, y) * 4
					c = Color8(_palette[p], _palette[p + 1], _palette[p + 2], _palette[p + 3])
				_:
					c = _rgb565(get_pixel(x, y))
			_image.set_pixel(x, y, c)
	if _screen:
		_screen.texture = ImageTexture.create_from_image(_image)
	if _screen_mat:
		_screen_mat.albedo_texture = _screen.texture
		_screen_mat.emission_texture = _screen.texture
		_screen_mat.emission_enabled = state.get("power", true)

func _attach_screen() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(23.0, 14.8) * MM
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mat.albedo_color = Color.WHITE
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color.WHITE
	_screen_mat.emission_energy_multiplier = 1.7
	if _screen and _screen.texture:
		_screen_mat.albedo_texture = _screen.texture
		_screen_mat.emission_texture = _screen.texture
	var mi := MeshInstance3D.new()
	mi.name = "Screen"
	mi.mesh = plane
	mi.material_override = _screen_mat
	mi.position = Vector3(0, 2.55, 0) * MM
	mi.rotation.x = -PI / 2
	add_child(mi)
