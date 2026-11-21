class_name UITheme
extends RefCounted
## Минималистичная техно/PCB-тема: тёмные панели, неоновые акценты,
## моноширинный шрифт. Собирается кодом, чтобы не тащить .theme-файлы.

const BG := Color("#070d10")
const BG_2 := Color("#0a1216")
const PANEL := Color("#0c161a")
const PANEL_2 := Color("#112027")
const PANEL_3 := Color("#152a31")
const LINE := Color("#1c353b")
const LINE_SOFT := Color("#14262b")
const TEXT := Color("#cfe0dd")
const DIM := Color("#73908f")
const FAINT := Color("#4a6464")
const ACCENT := Color("#39ff88")
const ACCENT_DARK := Color("#0f2c1f")
const CYAN := Color("#33d6e0")
const POWER := Color("#ffb84d")
const VIDEO := Color("#ff66cc")
const WARN := Color("#ffc857")
const ERROR := Color("#ff5c6c")
const OK := Color("#39ff88")

static var _font: Font = null


static func mono_font() -> Font:
	if _font != null:
		return _font
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"JetBrains Mono", "Cascadia Mono", "DejaVu Sans Mono", "Liberation Mono",
		"Consolas", "Menlo", "Courier New", "monospace",
	])
	f.allow_system_fallback = true
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_font = f
	return f


static func box(bg: Color, border_color: Color = Color.TRANSPARENT, radius: int = 6,
		border_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = border_width
	sb.border_width_top = border_width
	sb.border_width_right = border_width
	sb.border_width_bottom = border_width
	sb.border_color = border_color
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.anti_aliasing = true
	return sb


static func build_theme() -> Theme:
	var theme := Theme.new()
	var font := mono_font()
	theme.default_font = font
	theme.default_font_size = 13

	# --- Панели ---
	theme.set_stylebox("panel", "Panel", box(PANEL, LINE, 8))
	theme.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 8))
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.4))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	# --- Кнопки ---
	theme.set_stylebox("normal", "Button", box(PANEL_2, LINE, 5))
	theme.set_stylebox("hover", "Button", box(PANEL_3, Color("#2c5a5f"), 5))
	theme.set_stylebox("pressed", "Button", box(Color("#0f2a22"), ACCENT, 5))
	theme.set_stylebox("disabled", "Button", box(Color("#0a1013"), LINE_SOFT, 5))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Color(0.22, 1.0, 0.53, 0.5), 5))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color("#eafff6"))
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", FAINT)
	theme.set_font_size("font_size", "Button", 12)
	theme.set_constant("h_separation", "Button", 6)

	# --- Поля ввода / код ---
	for type_name in ["LineEdit", "TextEdit", "CodeEdit"]:
		theme.set_stylebox("normal", type_name, box(BG_2, LINE, 4))
		theme.set_stylebox("focus", type_name, box(BG_2, Color(0.22, 0.9, 0.55, 0.55), 4))
		theme.set_color("font_color", type_name, TEXT)
		theme.set_color("caret_color", type_name, ACCENT)
		theme.set_color("selection_color", type_name, Color(0.22, 0.8, 0.5, 0.25))
		theme.set_color("current_line_color", type_name, Color(0.15, 0.35, 0.3, 0.25))
		theme.set_color("line_number_color", type_name, FAINT)
		theme.set_font("font", type_name, font)
		theme.set_font_size("font_size", type_name, 13)

	# --- RichText ---
	theme.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_font("normal_font", "RichTextLabel", font)
	theme.set_font("mono_font", "RichTextLabel", font)
	theme.set_font_size("normal_font_size", "RichTextLabel", 12)
	theme.set_font_size("mono_font_size", "RichTextLabel", 12)

	# --- Скроллбары ---
	theme.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0))
	theme.set_stylebox("grabber", "VScrollBar", box(Color(0.25, 0.45, 0.45, 0.6), Color(0, 0, 0, 0), 4, 0))
	theme.set_stylebox("grabber_highlight", "VScrollBar",
		box(Color(0.3, 0.6, 0.55, 0.8), Color(0, 0, 0, 0), 4, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar",
		box(Color(0.3, 0.7, 0.6, 0.9), Color(0, 0, 0, 0), 4, 0))
	theme.set_stylebox("scroll", "HScrollBar", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0))
	theme.set_stylebox("grabber", "HScrollBar", box(Color(0.25, 0.45, 0.45, 0.6), Color(0, 0, 0, 0), 4, 0))
	theme.set_stylebox("grabber_highlight", "HScrollBar",
		box(Color(0.3, 0.6, 0.55, 0.8), Color(0, 0, 0, 0), 4, 0))
	theme.set_stylebox("grabber_pressed", "HScrollBar",
		box(Color(0.3, 0.7, 0.6, 0.9), Color(0, 0, 0, 0), 4, 0))

	# --- Попапы / тултипы ---
	theme.set_stylebox("panel", "PopupMenu", box(PANEL_2, LINE, 6))
	theme.set_stylebox("hover", "PopupMenu", box(PANEL_3, Color(0, 0, 0, 0), 4, 0))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", ACCENT)
	theme.set_stylebox("panel", "TooltipPanel", box(Color("#0a1519"), Color("#2b555a"), 5))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font("font", "TooltipLabel", font)

	# --- Разделители ---
	theme.set_constant("separation", "HBoxContainer", 8)
	theme.set_constant("separation", "VBoxContainer", 8)
	theme.set_constant("separation", "HSplitContainer", 6)
	theme.set_constant("separation", "VSplitContainer", 6)
	return theme


# ---------------------------------------------------------------------------
# Фабрики элементов
# ---------------------------------------------------------------------------

static func label(text: String, size: int = 13, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func heading(text: String, color: Color = DIM) -> Label:
	var l := label(text.to_upper(), 10, color)
	l.add_theme_constant_override("outline_size", 0)
	return l


static func title(text: String, size: int = 16, color: Color = TEXT) -> Label:
	return label(text, size, color)


static func button(text: String, kind: String = "normal") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	match kind:
		"primary":
			_style_primary(b)
		"danger":
			_style_danger(b)
		"accent":
			_style_accent(b)
	return b


static func _style_primary(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(ACCENT, ACCENT, 5, 1))
	b.add_theme_stylebox_override("hover", box(Color("#6dffab"), Color("#b6ffd4"), 5, 1))
	b.add_theme_stylebox_override("pressed", box(Color("#20cc6a"), ACCENT, 5, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("#04120c"))
	b.add_theme_color_override("font_hover_color", Color("#04120c"))
	b.add_theme_color_override("font_pressed_color", Color("#04120c"))


static func _style_danger(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(Color("#2a1218"), Color("#7c2b37"), 5, 1))
	b.add_theme_stylebox_override("hover", box(Color("#3a1820"), ERROR, 5, 1))
	b.add_theme_stylebox_override("pressed", box(Color("#4a1b24"), ERROR, 5, 1))
	b.add_theme_color_override("font_color", Color("#ff9aa5"))
	b.add_theme_color_override("font_hover_color", Color("#ffd0d6"))


static func _style_accent(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(Color("#0f2a24"), Color("#2a7a5c"), 5, 1))
	b.add_theme_stylebox_override("hover", box(Color("#143b31"), ACCENT, 5, 1))
	b.add_theme_stylebox_override("pressed", box(Color("#0c221d"), ACCENT, 5, 1))
	b.add_theme_color_override("font_color", Color("#9fffc8"))
	b.add_theme_color_override("font_hover_color", Color("#e8fff2"))


static func panel(bg: Color = PANEL, border_color: Color = LINE, radius: int = 8) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border_color, radius))
	return p


static func hbox(separation: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func vbox(separation: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func separator(color: Color = LINE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func dot(color: Color, size: int = 9) -> Label:
	var l := Label.new()
	l.text = "●"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func pill(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(color.r * 0.12, color.g * 0.12, color.b * 0.12, 0.9),
		Color(color.r, color.g, color.b, 0.35), 20, 1)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text, 10, color))
	return p


## Обёртка: панель с заголовком и содержимым.
static func section(title_text: String, content: Control, accent: Color = DIM,
		subtitle: String = "") -> VBoxContainer:
	var outer := vbox(6)
	var head := hbox(6)
	head.add_child(heading(title_text, accent))
	if subtitle != "":
		head.add_child(label(subtitle, 10, FAINT))
	head.add_child(spacer())
	outer.add_child(head)
	outer.add_child(content)
	return outer
