class_name ChipEvaluator
extends RefCounted
## Проверяет собранную схему и превращает её в числа:
## питание, шина, тепло, стабильность, лимит FPS и бюджет инструкций.
## Ошибки не мешают запуску — они лишь объясняют, почему чип будет глючить.

const AMBIENT_TEMP := 32.0
const MAX_TEMP := 118.0
const BASE_STABILITY := 0.86
const MAX_BONUS := 0.16


class Stats:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	var total_components := 0
	var powered_components := 0
	var power_capacity := 0.0
	var power_load := 0.0
	var power_ratio := 0.0
	var power_satisfaction := 0.0

	var compute_raw := 0.0
	var compute_effective := 0.0
	var bandwidth_provided := 0.0
	var bandwidth_demand := 0.0
	var bandwidth_satisfaction := 1.0
	var storage := 0.0

	var heat_load := 0.0
	var cooling := 0.0
	var temp_equilibrium := 32.0
	var stability := 0.0

	var has_output := false
	var output_connected := false

	var fps_limit := 6.0
	var quality := 0.5
	var steps_budget := 1500

	var valid := false

	## Проблемы конкретных компонентов: id -> короткое сообщение.
	var node_issues := {}

	func add_error(msg: String) -> void:
		errors.append(msg)

	func add_warning(msg: String) -> void:
		warnings.append(msg)

	func can_output() -> bool:
		return has_output and output_connected


static func evaluate(board: ChipBoard) -> Stats:
	var st := Stats.new()
	ComponentLibrary.load_all()
	st.total_components = board.component_count()
	if st.total_components == 0:
		st.add_error("Плата пуста — добавьте компоненты из палитры")
		return st

	var by_id := {}
	var defs := {}
	for comp in board.components:
		var d := board.def_of(comp)
		if d == null:
			st.add_error("Неизвестный компонент: %s" % String(comp.get("def_id", "?")))
			continue
		by_id[int(comp["id"])] = comp
		defs[int(comp["id"])] = d

	# --- Питание -----------------------------------------------------------
	var power_factor := {}   # comp_id -> 0..a
	for id in by_id:
		power_factor[id] = 0.0
	var power_nets := _build_nets(board, by_id, defs, "power")
	var unpowered_names: Array[String] = []
	var source_nets := 0
	for net in power_nets:
		var supply := 0.0
		var load := 0.0
		var has_source := false
		for id in net:
			var d: ComponentDef = defs[id]
			supply += d.power_supply
			load += d.power_draw
			if d.is_power_source:
				has_source = true
		if not has_source:
			for id in net:
				var d: ComponentDef = defs[id]
				if unpowered_names.size() < 6:
					unpowered_names.append(d.display_name)
			continue
		source_nets += 1
		var ratio := 1.0
		if load > 0.001:
			ratio = supply / load
		st.power_capacity += supply
		st.power_load += load
		for id in net:
			power_factor[id] = clampf(ratio, 0.0, 1.0)

	if source_nets == 0:
		st.add_error("Нет питания: добавьте Power In (и VRM, если нужно больше ватт)")
	else:
		for id in by_id:
			if defs[id].has_port_kind("power") and power_factor[id] <= 0.0:
				unpowered_names.append(defs[id].display_name)
		if not unpowered_names.is_empty():
			st.add_error("Без питания: %s" % _join_names(unpowered_names))
	for id in by_id:
		if defs[id].has_port_kind("power") and power_factor[id] <= 0.0:
			st.node_issues[id] = "нет питания"

	if st.power_load > 0.001:
		st.power_ratio = st.power_capacity / st.power_load
		st.power_satisfaction = clampf(st.power_ratio, 0.0, 1.0)
		if st.power_ratio < 1.0:
			st.add_error("Нехватка питания: %.0f%% (нужно %.0f Вт, есть %.0f Вт)" % [
				st.power_ratio * 100.0, st.power_load, st.power_capacity])

	for id in by_id:
		if power_factor[id] > 0.0:
			st.powered_components += 1

	# --- Шина памяти -------------------------------------------------------
	var bus_ratio := {}
	var bus_nets := _build_nets(board, by_id, defs, "bus")
	var compute_components := 0
	for net in bus_nets:
		var bw := 0.0
		var demand := 0.0
		for id in net:
			var d: ComponentDef = defs[id]
			bw += d.bandwidth
			demand += d.compute * 0.85
		var ratio := 1.0
		if demand > 0.001:
			ratio = clampf(bw / demand, 0.0, 1.0)
			if bw <= 0.001:
				st.add_error("Шина без памяти: ядрам нужны VRAM / NAND-контроллер / XON")
		st.bandwidth_provided += bw
		st.bandwidth_demand += demand
		for id in net:
			bus_ratio[id] = ratio

	for id in by_id:
		var d: ComponentDef = defs[id]
		if d.compute > 0.0:
			compute_components += 1
			if not d.has_port_kind("bus"):
				st.add_warning("%s без шины: работает на 15%% мощности" % d.display_name)
				bus_ratio[id] = 0.15
				st.node_issues[id] = "нет шины памяти"
			elif not bus_ratio.has(id):
				st.add_warning("%s не подключён к шине памяти" % d.display_name)
				bus_ratio[id] = 0.15
				st.node_issues[id] = "не подключён к шине"
			if not d.has_port_kind("power") or power_factor[id] <= 0.0:
				st.add_warning("%s без питания — не работает" % d.display_name)

	if st.bandwidth_demand > 0.001:
		st.bandwidth_satisfaction = clampf(st.bandwidth_provided / st.bandwidth_demand, 0.0, 1.0)
		if st.bandwidth_satisfaction < 0.99:
			st.add_warning("Память не успевает: шина загружена на %.0f%%" % (
				st.bandwidth_satisfaction * 100.0))
	if compute_components == 0:
		st.add_error("Нет вычислительных ядер (GPU Core / CPU Core)")

	# --- Тепло -------------------------------------------------------------
	for id in by_id:
		var d: ComponentDef = defs[id]
		var pf: float = power_factor[id]
		st.heat_load += d.heat_output * pf
		st.cooling += d.cooling * pf
		st.storage += d.storage
	st.temp_equilibrium = clampf(AMBIENT_TEMP + maxf(0.0, st.heat_load - st.cooling) * 0.55,
		AMBIENT_TEMP, MAX_TEMP)
	if st.cooling <= 1.0 and st.heat_load > 30.0:
		st.add_warning("Нет охлаждения — чип перегреется и начнёт глючить")

	# --- Стабильность ------------------------------------------------------
	var bonus := 0.0
	for id in by_id:
		if power_factor[id] > 0.0:
			bonus += defs[id].stability_bonus
	bonus = minf(bonus, MAX_BONUS)
	var deficit := maxf(0.0, 1.0 - st.power_satisfaction)
	var starvation := 0.0
	if st.bandwidth_demand > 0.001:
		starvation = maxf(0.0, 1.0 - st.bandwidth_satisfaction)
	var thermal := 0.0
	if st.temp_equilibrium > 90.0:
		thermal = (st.temp_equilibrium - 90.0) / 60.0
	st.stability = clampf(BASE_STABILITY + bonus - deficit * 0.35 - starvation * 0.2 - thermal * 0.25,
		0.3, 1.0)
	if st.temp_equilibrium > 95.0:
		for id in by_id:
			if defs[id].heat_output > 0.0 and power_factor[id] > 0.0:
				if not st.node_issues.has(id):
					st.node_issues[id] = "перегрев: мало охлаждения"
	if st.temp_equilibrium >= MAX_TEMP - 1.0:
		st.add_warning("Критический перегрев: нужен кулер или крио-плита")

	# --- Эффективная мощность ----------------------------------------------
	var perf := 0.0
	for id in by_id:
		var d: ComponentDef = defs[id]
		if d.compute <= 0.0:
			continue
		st.compute_raw += d.compute
		if power_factor[id] <= 0.0:
			continue
		var bf: float = bus_ratio.get(id, 0.15)
		st.compute_effective += d.compute * power_factor[id] * bf
	var thermal_penalty := clampf(1.0 - maxf(0.0, st.temp_equilibrium - 85.0) / 80.0, 0.3, 1.0)
	perf = st.compute_effective * st.stability * thermal_penalty
	st.fps_limit = clampf(6.0 + perf * 0.33, 6.0, 60.0)
	st.steps_budget = int(clampf(1200.0 + perf * 25.0, 1500.0, 8000.0))
	if perf >= 170.0:
		st.quality = 1.25
	elif perf >= 90.0:
		st.quality = 1.0
	elif perf >= 40.0:
		st.quality = 0.75
	else:
		st.quality = 0.5

	# --- Видеовыход --------------------------------------------------------
	_check_video(board, st, by_id, defs, power_factor)

	st.valid = st.errors.is_empty()
	return st


static func _check_video(board: ChipBoard, st: Stats, by_id: Dictionary, defs: Dictionary,
		power_factor: Dictionary) -> void:
	var outputs: Array[int] = []
	for id in by_id:
		if defs[id].category == "output" and defs[id].has_port_kind("video"):
			outputs.append(id)
	st.has_output = not outputs.is_empty()
	for id in by_id:
		if defs[id].has_port_kind("video") and defs[id].compute > 0.0:
			var video_linked := false
			for link in board.links:
				if int(link["a"]) == id or int(link["b"]) == id:
					var pi := board.port_info(board.get_component(id), String(link["a_port"] if int(link["a"]) == id else link["b_port"]))
					if not pi.is_empty() and String(pi["kind"]) == "video":
						video_linked = true
			if not video_linked and not st.node_issues.has(id):
				st.node_issues[id] = "видео-порт не подключён"
	if not st.has_output:
		st.add_error("Нет Display Out — экрану некуда подключаться")
		return

	for link in board.links:
		var a := int(link["a"])
		var b := int(link["b"])
		if not by_id.has(a) or not by_id.has(b):
			continue
		var pa := board.port_info(board.get_component(a), String(link["a_port"]))
		var pb := board.port_info(board.get_component(b), String(link["b_port"]))
		if pa.is_empty() or pb.is_empty() or pa["kind"] != "video":
			continue
		var a_is_out := outputs.has(a)
		var b_is_out := outputs.has(b)
		if a_is_out == b_is_out:
			continue
		var other := b if a_is_out else a
		if defs[other].compute > 0.0:
			if power_factor[other] > 0.0 and power_factor[(a if a_is_out else b)] > 0.0:
				st.output_connected = true
			elif power_factor[other] <= 0.0:
				st.add_error("Видеоядро без питания")
			else:
				st.add_error("Display Out без питания")

	if not st.output_connected:
		for id in outputs:
			if power_factor[id] > 0.0:
				st.node_issues[id] = "нет видеосигнала"
	if not st.output_connected and st.errors.is_empty():
		st.add_error("Видео-порт ядра не подключён к Display Out")
	elif not st.output_connected and not st.errors.is_empty():
		# Не дублируем ошибку, но подсказка полезна.
		var already := false
		for e in st.errors:
			if e.contains("Display Out") or e.contains("Видео"):
				already = true
		if not already:
			st.add_error("Нет видеосигнала на Display Out")


# ---------------------------------------------------------------------------
# Сети (union-find по связям определённого типа)
# ---------------------------------------------------------------------------

static func _build_nets(board: ChipBoard, by_id: Dictionary, defs: Dictionary,
		kind: String) -> Array:
	var parent := {}
	for id in by_id:
		parent[id] = id
	for link in board.links:
		var a := int(link["a"])
		var b := int(link["b"])
		if not by_id.has(a) or not by_id.has(b):
			continue
		var pa := board.port_info(board.get_component(a), String(link["a_port"]))
		var pb := board.port_info(board.get_component(b), String(link["b_port"]))
		if pa.is_empty() or pb.is_empty():
			continue
		if String(pa["kind"]) != kind or String(pb["kind"]) != kind:
			continue
		_union(parent, a, b)

	var groups := {}
	for id in by_id:
		if not defs[id].has_port_kind(kind):
			continue
		var root := _find(parent, id)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(id)

	var nets: Array = []
	for root in groups:
		nets.append(groups[root])
	return nets


static func _find(parent: Dictionary, x: int) -> int:
	var root := x
	while int(parent[root]) != root:
		root = int(parent[root])
	# сжатие путей
	var cur := x
	while int(parent[cur]) != root:
		var nxt := int(parent[cur])
		parent[cur] = root
		cur = nxt
	return root


static func _union(parent: Dictionary, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


static func _join_names(names: Array[String]) -> String:
	var counts := {}
	var order: Array[String] = []
	for n in names:
		if not counts.has(n):
			counts[n] = 0
			order.append(n)
		counts[n] = int(counts[n]) + 1
	var parts := PackedStringArray()
	for n in order:
		if int(counts[n]) > 1:
			parts.append("%s ×%d" % [n, int(counts[n])])
		else:
			parts.append(n)
	return ", ".join(parts)
