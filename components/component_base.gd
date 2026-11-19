class_name CircuitPart
extends Node3D

const Definition = preload("res://components/component_def.gd")
const MM := 0.001
const SILVER := Color("bac4c7")
@export var definition: Definition
@export var component_id := ""  # Пустой id: только модель, без участия в схеме.
@export var ports: Dictionary = {}
@export var params: Dictionary = {}
var state: Dictionary = {}
static var _materials: Dictionary = {}

func _ready() -> void:
	if definition:
		ports.merge(definition.ports, true)
		params.merge(definition.parameters, true)
	var model := make_mesh()
	model.name = "Model"
	add_child(model)
	var bounds := BoxShape3D.new()
	bounds.size = size_mm() * MM
	_pick("Body", bounds, Vector3.UP * size_mm().y * 0.5, 4)
	var pads := pin_layout_mm()
	for p: String in pads:
		var pos: Vector3 = pads[p]
		rod(model, pos, pos + Vector3.UP * 0.18, 1.35, stock(Color("d4ae6b"), 0.76))
		var hit := CylinderShape3D.new()
		hit.radius = 0.85 * MM
		hit.height = 0.65 * MM
		_pick(p, hit, pos + Vector3.UP * 0.325, 8).set_meta("pin", p)
	refresh_visual()
	if not component_id.is_empty() and not ports.is_empty():
		if not SimRegistry.register(self):
			push_error("Некорректный или занятый id: " + component_id)
	# Детали без портов (корпус) — чистый декор, в схему не входят.

func _exit_tree() -> void:
	if not component_id.is_empty():
		SimRegistry.unregister(self)

func _pick(label: String, shape: Shape3D, pos_mm: Vector3, layer: int) -> Area3D:
	var area := Area3D.new()
	area.name = label
	area.collision_layer = layer
	area.collision_mask = 0
	area.monitoring = false
	area.position = pos_mm * MM
	var collider := CollisionShape3D.new()
	collider.shape = shape
	area.add_child(collider)
	add_child(area)
	return area

func endpoint(pin: String) -> String:
	return component_id + "." + pin

func read_pin(pin: String) -> Dictionary:
	return SimBus.sample(endpoint(pin))

func tick(_at: int) -> void:
	pass

func on_signal(_pin: String, _sample: Dictionary) -> void:
	pass  # Реестр уже назначит один tick для всей пачки изменений.

func on_event(kind: String, data: Dictionary = {}) -> void:
	# Датированный внешний стимул; один драйвер на физический порт.
	if kind == "drive" and ports.has(data.get("pin")):
		SimBus.drive(endpoint(data.pin), int(data.get("sig", SimBus.Sig.Z)),
			float(data.get("vcc", 3.3)), float(data.get("ohms", 25.0)))

func refresh_visual() -> void:
	pass  # Вызывается также при откате состояния.

func make_mesh() -> Node3D:
	return Node3D.new()

func size_mm() -> Vector3:
	return Vector3.ONE

func pin_layout_mm() -> Dictionary:
	return {}

# Модели задаются в мм. В движок попадают метры, без scale у коллайдеров.
func stock(color: Color, metal: float = 0.0, rough: float = 0.48) -> StandardMaterial3D:
	var key := [color, metal, rough]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = metal
		m.roughness = rough
		_materials[key] = m
	return _materials[key]

func piece(root: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos * MM
	root.add_child(mi)
	return mi

func rod(root: Node3D, a: Vector3, b: Vector3, diameter: float, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = diameter * MM * 0.5
	c.bottom_radius = c.top_radius
	c.height = a.distance_to(b) * MM
	c.radial_segments = 12
	c.rings = 0
	var mi := piece(root, c, (a + b) * 0.5, mat)
	mi.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return mi
