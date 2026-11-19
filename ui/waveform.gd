extends Control

# Ленточная диаграмма цифровых уровней: до 8 сетей, 256 последних отсчётов.
var nets: Array[String] = []
var hist: Dictionary = {}
const MAX_SAMPLES := 256
const COLORS := {
	0: Color("1f6b52"),   # 0
	1: Color("5cffc0"),   # 1
	2: Color("5d6b66"),   # Z
	3: Color("ff5d5d"),   # X
}

func _init() -> void:
	custom_minimum_size = Vector2(360, 190)

func _ready() -> void:
	DebugHooks.on_signal_change.connect(_on_signal)

func track(net: String) -> void:
	if net.is_empty() or net in nets:
		return
	if nets.size() >= 8:
		hist.erase(nets[0])
		nets.remove_at(0)
	nets.append(net)
	hist[net] = PackedInt32Array()
	queue_redraw()

func _on_signal(_tick: int, net: String, sample: Dictionary) -> void:
	if not hist.has(net):
		return
	var arr: PackedInt32Array = hist[net]
	arr.append(int(sample.get("sig", 2)))
	if arr.size() > MAX_SAMPLES:
		arr = arr.slice(arr.size() - MAX_SAMPLES)
	hist[net] = arr
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var row := size.y / maxf(1.0, float(nets.size()))
	for i in nets.size():
		var net := nets[i]
		var y0 := i * row
		draw_rect(Rect2(0, y0, size.x, row), Color(0.05, 0.10, 0.09, 0.55 if i % 2 == 0 else 0.35))
		draw_string(font, Vector2(4, y0 + 12), net, HORIZONTAL_ALIGNMENT_LEFT, 120, 10, Color(0.62, 1.0, 0.83))
		var arr: PackedInt32Array = hist[net]
		if arr.is_empty():
			continue
		var x0 := 126.0
		var w := (size.x - x0 - 4.0) / MAX_SAMPLES
		var mid := y0 + row * 0.58
		var amp := row * 0.26
		for j in arr.size():
			var level: int = arr[j]
			var yv := mid
			if level == 1: yv = mid - amp
			elif level == 2: yv = mid
			elif level == 3: yv = mid - amp * 0.5
			draw_rect(Rect2(x0 + j * w, yv - 2.0, maxf(w, 1.0), 4.0), COLORS.get(level, Color.MAGENTA))
	if nets.is_empty():
		draw_string(font, Vector2(10, size.y * 0.5), "Добавь сеть кнопкой ниже или дождись изменения сигнала", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.63, 0.58))
