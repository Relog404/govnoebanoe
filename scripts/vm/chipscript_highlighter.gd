class_name ChipScriptHighlighter
extends CodeHighlighter
## Подсветка синтаксиса ChipScript для CodeEdit.

const KEYWORDS := [
	"var", "let", "if", "else", "while", "for", "in", "return", "break",
	"continue", "func", "function", "true", "false", "null", "and", "or", "not",
]

const BUILTINS := [
	"clear", "fill_rect", "rect", "line", "fill_circle", "circle", "pixel", "text", "triangle",
	"mouse_x", "mouse_y", "mouse_down", "mouse_clicked", "mouse_released",
	"key_down", "key_pressed", "key_released", "wheel",
	"dt", "time", "tick", "width", "height",
	"abs", "min", "max", "floor", "ceil", "round", "sqrt", "sin", "cos", "tan", "atan2",
	"pow", "clamp", "lerp", "sign", "rand", "random", "dist", "pi",
	"str", "num", "len", "push", "pop", "range", "lower", "upper", "substr", "has",
	"print", "halt", "start", "update", "draw",
	"on_mouse_down", "on_mouse_up", "on_mouse_move", "on_key_down", "on_key_up", "on_wheel",
]


func _init() -> void:
	number_color = Color("#ffc857")
	symbol_color = Color("#cfe0dd")
	function_color = Color("#33d6e0")
	member_variable_color = Color("#9fe8d0")
	for word in KEYWORDS:
		add_keyword_color(word, Color("#ff79a8"))
	for word in BUILTINS:
		add_keyword_color(word, Color("#33d6e0"))
	add_color_region("\"", "\"", Color("#b6ff9e"), false)
	add_color_region("#", "", Color("#4e6a63"), true)
	add_color_region("//", "", Color("#4e6a63"), true)
