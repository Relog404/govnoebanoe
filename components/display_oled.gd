extends "res://components/component_base.gd"

# 0.96" OLED 128×64. Формат кадра задаёт игрок в ComponentDef.framebuffer_format:
# "1-bit"  — 1 бит на пиксель, монохром;
# "RGB565" — 16 бит на пиксель (хранится как uint16, рисуется побитово);
# "Palette"— индекс в 256-цветной палитре (палитра по умолчанию серая).
# Рендер — обычная CPU-заливка Image; эмиссия через ViewportTexture на плоскости экрана.
enum Fmt { ONE_BIT, RGB565, PALETTE }
const W := 128
const H := 64
var _fb: PackedByteArray = PackedByteArray()
var _palette: PackedByteArray = PackedByteArray()   # 256*4 (RGBA)
var _viewport: SubViewport
var _screen: TextureRect
var _image: Image
var _format := Fmt.ONE_BIT

func _init() -> void:
	ports = {"SDA": "in", "SCK": "in", "CS": "in", "RES": "in"}
	state = {"width": W, "height": H, "bytes": 0, "fmt": "1-bit"}

func size_mm() -> Vector3:
	return Vector3(26.0, 3.0, 26.0)

func pin_layout_mm() -> Dictionary:
	return {
		"GND": Vector3(-7.62, 0, 13.5), "VCC": Vector3(-5.08, 0, 13.5), "SCK": Vector3(-2.54, 0, 13.5), "SDA": Vector3(0, 0, 13.5),
		"RES": Vector3(2.54, 0, 13.5), "DC": Vector3(5.08, 0, 13.5), "CS": Vector3(7.62, 0, 13.5),
	}

func make_mesh() -> Node3D:
	var root := Node3D.new()
	var pcb := BoxMesh.new()
	pcb.size = Vector3(26.0, 1.6, 26.0) * MM
	piece(root, pcb, Vector3.UP * 0.9, stock(Color("12222b"), 0.2, 0.62))
	var bezel := BoxMesh.new()
	bezel.size = Vector3(24.0, 0.9, 16.4) * MM
	piece(root, bezel, Vector3.UP * 2.05, stock(Color("050708")))
	return root

func _ready() -> void:
	# Порты OLED совпадают со стандартными SPI-пинами пользовательского чипа.
	ports.merge({"GND":"optional", "VCC":"optional", "SCK":"clock_in", "SDA":"in", "CS":"in", "RES":"in", "DC":"optional"}, true)
	super._ready()
	var fmt := "1-bit"
	if definition and not definition.framebuffer_format.is_empty():
		fmt = definition.framebuffer_format
	state.fmt = fmt
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
	# Viewport + TextureRect: обычная 2D-сцена, затем выносим на 3D-плоскость.
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

func fb_bytes() -> int:
	match _format:
		Fmt.ONE_BIT: return W * H / 8
		Fmt.RGB565:  return W * H * 2
		_:           return W * H

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
	var tex := ImageTexture.create_from_image(_image)
	_screen.texture = tex

func _attach_screen() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(23.0, 13.2) * MM
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 1.6
	if _screen and _screen.texture:
		mat.albedo_texture = _screen.texture
		mat.emission_texture = _screen.texture
	var mi := MeshInstance3D.new()
	mi.name = "Screen"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0, 2.55, 0) * MM
	mi.rotation.x = -PI / 2
	add_child(mi)
