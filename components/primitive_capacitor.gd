extends "res://components/component_base.gd"

const FAMILY := {
	"ceramic": {"body": "d0722d", "diameter": 5.0},
	"film":    {"body": "7c5028", "diameter": 5.0},
	"tantalum":{"body": "8a5a1e", "diameter": 3.4},
}

func _init() -> void:
	ports = {"A": "passive", "B": "passive"}
	state = {"v_a": 0.0, "v_b": 0.0}   # Заряд в снимке определяется этими парами.

func size_mm() -> Vector3:
	return Vector3(3.4, 5.6, 2.5)

func pin_layout_mm() -> Dictionary:
	return {"A": Vector3.LEFT * 1.27, "B": Vector3.RIGHT * 1.27}

func make_mesh() -> Node3D:
	return make_capacitor(params)

func make_capacitor(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var tin := stock(SILVER, 0.82)
	for side: float in [-1.0, 1.0]:
		rod(root, Vector3.RIGHT*1.27*side, Vector3(0.76*side, 1.4, 0), 0.62, tin)
	var fam: Dictionary = FAMILY.get(str(p.get("family", "ceramic")), FAMILY.ceramic)
	var disc := CylinderMesh.new()
	disc.top_radius = fam.diameter * MM * 0.5
	disc.bottom_radius = disc.top_radius
	disc.height = 2.4 * MM
	disc.radial_segments = 16
	disc.rings = 0
	var mi := piece(root, disc, Vector3.UP * 3.3, stock(Color(fam.body)))
	mi.rotation.x = PI * 0.5   # Диск стоит вертикально, как у дискового.
	return root

func tick(_at: int) -> void:
	# Конденсатор в установившемся состоянии — разомкнутая ветвь.
	# Единственный «динамический» элемент: он остаётся открытым для постоянного тока.
	SimBus.open_branch(component_id)
	var a := read_pin("A")
	var b := read_pin("B")
	state.v_a = float(a.volts) if a.volts != null else 0.0
	state.v_b = float(b.volts) if b.volts != null else 0.0
