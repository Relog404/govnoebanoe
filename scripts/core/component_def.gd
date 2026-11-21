class_name ComponentDef
extends Resource
## Описание компонента чипа. Всё поведение (питание, тепло, мощность,
## производительность) задаётся данными этого ресурса — код менять не нужно.
##
## Чтобы добавить новый компонент, создайте .tres с этим скриптом в
## res://resources/components/. Он появится в палитре автоматически.

## Какие бывают порты. Совпадающие типы можно соединять между собой.
const KINDS := ["power", "bus", "video"]

## Идентификатор (обычно совпадает с именем файла). Заполняется библиотекой.
@export var id: String = ""
@export var display_name: String = "Component"
@export_multiline var description: String = ""
## Категория влияет только на иконку и группировку в палитре.
@export_enum("power", "compute", "memory", "io", "cooling", "support", "output") var category: String = "support"
## Цвет корпуса на плате.
@export var color: Color = Color(0.29, 0.62, 0.55)
## Размер в клетках (до поворота).
@export var size: Vector2i = Vector2i.ONE

# --- Электрика и производительность -------------------------------------
## Потребление, Вт.
@export var power_draw: float = 0.0
## Сколько ватт компонент отдаёт в сеть (БП, VRM). 0 — не источник.
@export var power_supply: float = 0.0
## Тепловыделение, Вт.
@export var heat_output: float = 0.0
## Отводит тепла, Вт (кулеры, радиаторы).
@export var cooling: float = 0.0
## Вычислительные очки (GPU/CPU).
@export var compute: float = 0.0
## Пропускная способность шины памяти.
@export var bandwidth: float = 0.0
## Объём хранилища (флейвор + лёгкий бонус к стабильности).
@export var storage: float = 0.0
## Бонус к стабильности (конденсаторы, отладка, кондиционирование).
@export var stability_bonus: float = 0.0
## Является ли компонент первичным источником питания (разъём БП).
@export var is_power_source: bool = false

## Порты: {"name": String, "side": "N"/"E"/"S"/"W", "kind": "power"/"bus"/"video",
##         "offset": int (позиция вдоль стороны)}
@export var ports: Array[Dictionary] = []

## Теги для подсказок/фильтров.
@export var tags: PackedStringArray = []

const _SIDE_DIRS := {
	"N": Vector2i(0, -1),
	"S": Vector2i(0, 1),
	"E": Vector2i(1, 0),
	"W": Vector2i(-1, 0),
}


## Размер с учётом поворота (0..3, по часовой стрелке).
func rotated_size(rot: int) -> Vector2i:
	if posmod(rot, 4) % 2 == 1:
		return Vector2i(size.y, size.x)
	return size


## Поворот клетки на 90° по часовой стрелке внутри прямоугольника base.
static func rotate_cell_cw(cell: Vector2i, base: Vector2i) -> Vector2i:
	return Vector2i(base.y - 1 - cell.y, cell.x)


## Позиция порта в локальных клетках компонента (до поворота).
func port_base_cell(port: Dictionary) -> Vector2i:
	var off: int = int(port.get("offset", 0))
	match String(port.get("side", "E")):
		"N":
			return Vector2i(off, 0)
		"S":
			return Vector2i(off, size.y - 1)
		"W":
			return Vector2i(0, off)
		"E":
			return Vector2i(size.x - 1, off)
	return Vector2i.ZERO


## Позиция порта в клетках с учётом поворота.
func port_cell(port: Dictionary, rot: int) -> Vector2i:
	var base := size
	var cell := port_base_cell(port)
	for i in posmod(rot, 4):
		cell = rotate_cell_cw(cell, base)
		base = Vector2i(base.y, base.x)
	return cell


## Направление «наружу» от порта (в клетках).
func port_dir(port: Dictionary, rot: int) -> Vector2i:
	var dir: Vector2i = _SIDE_DIRS.get(String(port.get("side", "E")), Vector2i.RIGHT)
	for i in posmod(rot, 4):
		dir = Vector2i(-dir.y, dir.x)  # поворот на 90° по часовой (ось Y вниз)
	return dir


func get_port(port_name: String) -> Dictionary:
	for p in ports:
		if String(p.get("name", "")) == port_name:
			return p
	return {}


func has_port_kind(kind: String) -> bool:
	for p in ports:
		if String(p.get("kind", "")) == kind:
			return true
	return false


func cell_count() -> int:
	return maxi(1, size.x) * maxi(1, size.y)


## Краткая сводка для палитры и тултипов.
func stat_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("Размер: %d×%d" % [size.x, size.y])
	if power_supply > 0.0:
		out.append("Питание: +%.0f Вт%s" % [power_supply, "  (источник)" if is_power_source else "  (VRM)"])
	if power_draw > 0.0:
		out.append("Потребление: %.0f Вт" % power_draw)
	if compute > 0.0:
		out.append("Вычисления: %.0f" % compute)
	if bandwidth > 0.0:
		out.append("Пропускная способность: %.0f" % bandwidth)
	if cooling > 0.0:
		out.append("Охлаждение: %.0f Вт" % cooling)
	if heat_output > 0.0:
		out.append("Тепло: %.0f Вт" % heat_output)
	if storage > 0.0:
		out.append("Хранилище: %.0f" % storage)
	if stability_bonus > 0.0:
		out.append("Стабильность: +%.2f" % stability_bonus)
	for p in ports:
		out.append("Порт %s (%s)" % [String(p.get("name", "?")), String(p.get("kind", "?"))])
	return out


func tooltip_text() -> String:
	var lines := PackedStringArray([display_name])
	if description != "":
		lines.append(description)
	lines.append("")
	lines.append_array(stat_lines())
	return "\n".join(lines)


static func kind_color(kind: String) -> Color:
	match kind:
		"power":
			return Color(1.0, 0.72, 0.33)
		"bus":
			return Color(0.30, 0.85, 0.95)
		"video":
			return Color(0.98, 0.40, 0.78)
	return Color(0.7, 0.7, 0.7)


static func kind_name(kind: String) -> String:
	match kind:
		"power":
			return "Питание"
		"bus":
			return "Шина"
		"video":
			return "Видео"
	return kind
