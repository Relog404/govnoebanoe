class_name DemoProjects
extends RefCounted
## Стартовая плата и примеры программ для мини-IDE.
## Демо-чип полностью исправен: питание, шина, видео и охлаждение в порядке.

const CODE_HERO := """# «Герой и монеты» — мышь + WASD одновременно.
# Клик по экрану — идти к точке. Клавиши — ручное управление.

var px = 160
var py = 120
var tx = 160
var ty = 120
var speed = 110
var score = 0
var coin_x = 60
var coin_y = 50
var t = 0
var trail = []

func start() {
  px = 160
  py = 120
  score = 0
  trail = []
  coin_x = rand(30, width() - 30)
  coin_y = rand(35, height() - 25)
}

func update(dt) {
  t = t + dt

  # Мышь: клик и перетаскивание задают цель.
  if mouse_clicked(0) {
    tx = mouse_x()
    ty = mouse_y()
  }
  if mouse_down(0) {
    tx = mouse_x()
    ty = mouse_y()
  }

  # Клавиатура: ручное управление.
  if key_down("A") or key_down("LEFT") {
    px = px - speed * dt
    tx = px
  }
  if key_down("D") or key_down("RIGHT") {
    px = px + speed * dt
    tx = px
  }
  if key_down("W") or key_down("UP") {
    py = py - speed * dt
    ty = py
  }
  if key_down("S") or key_down("DOWN") {
    py = py + speed * dt
    ty = py
  }

  # Плавное движение к цели.
  var dx = tx - px
  var dy = ty - py
  var d = sqrt(dx * dx + dy * dy)
  if d > 2 {
    px = px + dx / d * speed * dt
    py = py + dy / d * speed * dt
  }

  px = clamp(px, 10, width() - 10)
  py = clamp(py, 20, height() - 10)

  if dist(px, py, coin_x, coin_y) < 12 {
    score = score + 1
    coin_x = rand(20, width() - 20)
    coin_y = rand(30, height() - 20)
  }

  push(trail, [px, py])
  if len(trail) > 16 {
    pop(trail)
  }
}

func draw() {
  clear("#061014")

  # Фоновая сетка.
  for i in range(0, 16) {
    line(i * 20, 0, i * 20, height(), "#0c2227")
  }
  for j in range(0, 9) {
    line(0, j * 20, width(), j * 20, "#0c2227")
  }

  # След героя.
  for i in range(0, len(trail)) {
    var p = trail[i]
    fill_circle(p[0], p[1], 2 + i * 0.2, "#0f3b2c")
  }

  # Монета.
  var bob = sin(t * 3) * 2
  circle(coin_x, coin_y + bob, 9, "#ffd166")
  fill_circle(coin_x, coin_y + bob, 7, "#8a6a1a")
  text(coin_x - 3, coin_y + bob - 4, "$", "#ffd166")

  # Герой.
  fill_circle(px, py, 10, "#39ff88")
  fill_circle(px - 3, py - 2, 2, "#03120c")
  fill_circle(px + 3, py - 2, 2, "#03120c")
  line(px - 4, py + 5, px + 4, py + 5, "#03120c")

  # HUD.
  text(6, 5, "SCORE " + str(score), "#39ff88")
  text(6, height() - 13, "клик / WASD — идти", "#4e6a63")
  if dt() > 0 {
    text(width() - 72, 5, "FPS " + str(round(1 / dt())), "#33d6e0")
  }
}
"""

const CODE_PAINT := """# «Painter» — рисуем мышью, цвет и размер с клавиатуры.

var colors = ["#39ff88", "#33d6e0", "#ffd166", "#ff66cc", "#ffffff"]
var color = "#39ff88"
var brush = 5
var strokes = []
var hue = 0

func start() {
  strokes = []
  brush = 5
  color = colors[0]
}

func update(dt) {
  if key_pressed("1") { color = colors[0] }
  if key_pressed("2") { color = colors[1] }
  if key_pressed("3") { color = colors[2] }
  if key_pressed("4") { color = colors[3] }
  if key_pressed("5") { color = colors[4] }
  if key_pressed("SPACE") { brush = brush + 3 }
  if key_pressed("B") { brush = 2 }
  if key_down("C") { strokes = [] }

  if mouse_down(0) {
    push(strokes, [mouse_x(), mouse_y(), color, brush])
    if len(strokes) > 1600 {
      strokes = []
    }
  }
  hue = hue + dt
}

func draw() {
  clear("#0a0a12")
  for i in range(0, len(strokes)) {
    var s = strokes[i]
    fill_circle(s[0], s[1], s[3], s[2])
  }

  # Курсор-кисть.
  var pulse = 2 + sin(hue * 5) * 1.5
  circle(mouse_x(), mouse_y(), brush + pulse, color)

  text(6, 6, "ЛКМ — рисовать · 1-5 цвет · SPACE/B размер · C очистить", "#5f7a7e")
  text(width() - 60, 6, "штрихов: " + str(len(strokes)), "#33d6e0")
}
"""

const CODE_BREAKOUT := """# «Bricks» — мини-аркада: платформа мышью, отбивай мяч.
# R — заново. A/D — тоже управление.

var paddle = 160
var ball_x = 160
var ball_y = 110
var vx = 80
var vy = -70
var bricks = []
var score = 0
var lives = 3
var alive = 1

func start() {
  bricks = []
  for row in range(0, 4) {
    for col in range(0, 10) {
      push(bricks, [18 + col * 29, 26 + row * 12, 1])
    }
  }
  paddle = 160
  ball_x = 160
  ball_y = 110
  vx = 80
  vy = -70
  score = 0
  lives = 3
  alive = 1
}

func update(dt) {
  if key_pressed("R") {
    start()
    return
  }
  if alive == 0 {
    return
  }

  paddle = mouse_x()
  if key_down("A") or key_down("LEFT") { paddle = paddle - 150 * dt }
  if key_down("D") or key_down("RIGHT") { paddle = paddle + 150 * dt }
  paddle = clamp(paddle, 34, width() - 34)

  ball_x = ball_x + vx * dt
  ball_y = ball_y + vy * dt

  if ball_x < 6 { ball_x = 6; vx = -vx }
  if ball_x > width() - 6 { ball_x = width() - 6; vx = -vx }
  if ball_y < 20 { ball_y = 20; vy = -vy }

  if ball_y > height() - 24 and vy > 0 and abs(ball_x - paddle) < 30 {
    vy = -abs(vy)
    vx = (ball_x - paddle) * 4
  }

  if ball_y > height() + 8 {
    lives = lives - 1
    ball_x = paddle
    ball_y = height() - 60
    vy = -70
    vx = 80
    if lives <= 0 {
      alive = 0
    }
  }

  for i in range(0, len(bricks)) {
    var b = bricks[i]
    if b[2] == 1 and ball_x > b[0] and ball_x < b[0] + 24 and ball_y > b[1] and ball_y < b[1] + 8 {
      b[2] = 0
      vy = -vy
      score = score + 10
      break
    }
  }
}

func draw() {
  clear("#081018")

  for i in range(0, len(bricks)) {
    var b = bricks[i]
    if b[2] == 1 {
      fill_rect(b[0], b[1], 24, 8, "#2ee6a8")
      fill_rect(b[0], b[1], 24, 2, "#b6fff0")
    }
  }

  # Платформа.
  fill_rect(paddle - 30, height() - 16, 60, 6, "#33d6e0")
  fill_rect(paddle - 30, height() - 16, 60, 2, "#c9fbff")

  # Мяч.
  fill_circle(ball_x, ball_y, 4, "#ffd166")

  text(6, 6, "SCORE " + str(score), "#39ff88")
  text(width() - 70, 6, "LIVES " + str(lives), "#ff7b8a")

  if alive == 0 {
    fill_rect(60, 64, 200, 52, "#0b1b22")
    rect(60, 64, 200, 52, "#39ff88")
    text(110, 78, "GAME OVER", "#ff7b8a")
    text(92, 96, "нажмите R", "#71888c")
  }
}
"""


static func starter_code() -> String:
	return CODE_HERO


static func examples() -> Array:
	return [
		{
			"name": "Герой и монеты",
			"desc": "Мышь задаёт цель, WASD двигает героя. Собирайте монеты.",
			"code": CODE_HERO,
		},
		{
			"name": "Painter",
			"desc": "Рисование мышью, палитра на клавишах, размер кисти.",
			"code": CODE_PAINT,
		},
		{
			"name": "Bricks",
			"desc": "Аркада: платформа под мышью, мяч, кирпичи, жизни.",
			"code": CODE_BREAKOUT,
		},
	]


## Готовая рабочая плата-пример.
static func demo_board() -> ChipBoard:
	var board := ChipBoard.new()
	var ids := {}
	ids["psu"] = board.add_component("psu_connector", Vector2i(-10, 0))
	ids["vrm"] = board.add_component("vrm", Vector2i(-7, 0))
	ids["cap"] = board.add_component("capacitor", Vector2i(-9, 3))
	ids["gpu"] = board.add_component("gpu_core", Vector2i(0, 0))
	ids["vram1"] = board.add_component("vram", Vector2i(-2, 4))
	ids["vram2"] = board.add_component("vram", Vector2i(-2, 7))
	ids["xon"] = board.add_component("xon_controller", Vector2i(4, 0))
	ids["cool1"] = board.add_component("cooler", Vector2i(0, -4))
	ids["cool2"] = board.add_component("cooler", Vector2i(3, -4))
	ids["nandc"] = board.add_component("nand_controller", Vector2i(4, 4))
	ids["nand"] = board.add_component("nand_flash", Vector2i(7, 4))
	ids["display"] = board.add_component("display_out", Vector2i(0, 5))
	ids["probe"] = board.add_component("debug_probe", Vector2i(-1, 2))
	ids["clock"] = board.add_component("clock_gen", Vector2i(2, 4))

	# Питание.
	_wire(board, ids["psu"], "PWR", ids["vrm"], "IN")
	_wire(board, ids["psu"], "PWR", ids["cap"], "PWR")
	_wire(board, ids["vrm"], "OUT", ids["gpu"], "PWR")
	_wire(board, ids["vrm"], "OUT", ids["xon"], "PWR")
	_wire(board, ids["gpu"], "PWR", ids["cool1"], "PWR")
	_wire(board, ids["xon"], "PWR", ids["cool2"], "PWR")
	_wire(board, ids["gpu"], "PWR", ids["vram1"], "PWR")
	_wire(board, ids["gpu"], "PWR", ids["vram2"], "PWR")
	_wire(board, ids["gpu"], "PWR", ids["probe"], "PWR")
	_wire(board, ids["gpu"], "PWR", ids["clock"], "PWR")
	_wire(board, ids["gpu"], "PWR", ids["display"], "PWR")
	_wire(board, ids["gpu"], "PWR", ids["nandc"], "PWR")
	_wire(board, ids["nandc"], "PWR", ids["nand"], "PWR")

	# Шина памяти.
	_wire(board, ids["gpu"], "BUS", ids["vram1"], "BUS")
	_wire(board, ids["gpu"], "BUS", ids["vram2"], "BUS")
	_wire(board, ids["gpu"], "BUS", ids["xon"], "BUS")
	_wire(board, ids["xon"], "BUS2", ids["nandc"], "BUS")
	_wire(board, ids["nandc"], "BUS2", ids["nand"], "BUS")

	# Видео.
	_wire(board, ids["gpu"], "VID", ids["display"], "VID")
	return board


static func _wire(board: ChipBoard, a: int, a_port: String, b: int, b_port: String) -> void:
	if a < 0 or b < 0:
		push_warning("DemoProjects: missing component while wiring %s/%s" % [a_port, b_port])
		return
	var res := board.connect_ports(a, a_port, b, b_port)
	if not bool(res.get("ok", false)):
		push_warning("DemoProjects: wire %s ↔ %s failed: %s" % [a_port, b_port, res.get("error", "")])
