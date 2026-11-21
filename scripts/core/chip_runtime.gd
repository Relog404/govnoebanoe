class_name ChipRuntime
extends Node
## Симуляция работающего чипа: температура, троттлинг, частота кадров,
## выполнение программы и передача кадра на экран вывода.

signal metrics_changed(data: Dictionary)

const AMBIENT := 32.0

var board: ChipBoard
var surface: ChipDisplaySurface
var stats: ChipEvaluator.Stats
var vm: ChipVM = null

var running := false
var temperature := AMBIENT
var measured_fps := 0.0
var target_fps := 0.0
var glitch := 0.0
var overload := false
var error_message := ""
var error_line := 0

var _accumulator := 0.0
var _fps_counter := 0
var _fps_time := 0.0
var _metrics_time := 0.0
var _overload_window := 0
var _overload_seen := false
var _last_draw_count := 0


func _ready() -> void:
	set_process(true)


func set_surface(new_surface: ChipDisplaySurface) -> void:
	surface = new_surface
	if surface != null:
		_update_surface_idle()


func apply_stats(new_stats: ChipEvaluator.Stats) -> void:
	stats = new_stats
	if not running:
		_update_surface_idle()


## Запуск программы на текущей сборке.
func begin(prog: ChipProgram, evaluated: ChipEvaluator.Stats) -> bool:
	running = false
	if surface == null:
		push_warning("ChipRuntime: no display surface attached")
		return false
	stats = evaluated
	error_message = ""
	error_line = 0
	var new_vm := ChipVM.new()
	new_vm.set_program(prog)
	new_vm.step_budget = maxi(20000, stats.steps_budget * 2)
	var ok := new_vm.start()
	new_vm.step_budget = stats.steps_budget
	if not ok:
		error_message = new_vm.error
		error_line = new_vm.error_line
		_show_error(new_vm)
		return false
	vm = new_vm
	temperature = minf(temperature, 55.0)
	running = true
	_accumulator = 0.0
	_fps_counter = 0
	_fps_time = 0.0
	target_fps = stats.fps_limit
	overload = false
	_overload_seen = false
	glitch = clampf((1.0 - stats.stability) * 0.7, 0.0, 1.0)
	_push_frame()
	return true


func stop() -> void:
	running = false
	measured_fps = 0.0
	if surface != null:
		surface.signal_state = "stopped"
		surface.status_line = "программа остановлена"
		surface.queue_redraw()
	_emit_metrics(0.0, true)


func restart() -> void:
	if vm == null:
		return
	var new_vm := ChipVM.new()
	new_vm.set_program(vm.program)
	new_vm.step_budget = maxi(20000, stats.steps_budget * 2)
	var ok := new_vm.start()
	new_vm.step_budget = stats.steps_budget
	if not ok:
		_show_error(new_vm)
		return
	vm = new_vm
	error_message = ""
	error_line = 0
	running = true
	_accumulator = 0.0
	_fps_counter = 0
	_fps_time = 0.0
	_push_frame()


func _process(delta: float) -> void:
	if stats == null:
		return

	# Тепловая инерция работает всегда: чип остывает и после остановки.
	if running:
		var target_temp := stats.temp_equilibrium
		temperature = lerpf(temperature, target_temp, clampf(delta * 0.28, 0.0, 1.0))
	else:
		temperature = lerpf(temperature, AMBIENT, clampf(delta * 0.12, 0.0, 1.0))

	if not running:
		glitch = lerpf(glitch, 0.0, clampf(delta * 2.0, 0.0, 1.0))
		_accumulator = 0.0
		_emit_metrics(delta)
		return

	if vm == null:
		return

	# Программа сама завершилась или упала.
	if vm.halted:
		running = false
		if vm.error != "":
			error_message = vm.error
			error_line = vm.error_line
			_show_error(vm)
		elif surface != null:
			surface.signal_state = "stopped"
			surface.status_line = "программа завершилась"
			surface.queue_redraw()
		_emit_metrics(0.0, true)
		return

	var overheat := clampf((temperature - 85.0) / 30.0, 0.0, 1.0)
	var thermal_factor := 1.0
	if temperature > 85.0:
		thermal_factor = clampf(1.0 - (temperature - 85.0) / 55.0, 0.35, 1.0)
	target_fps = maxf(5.0, stats.fps_limit * thermal_factor)
	glitch = clampf((1.0 - stats.stability) * 0.7 + overheat * 0.8
		+ (0.25 if overload else 0.0), 0.0, 1.0)

	var dt_tick := 1.0 / target_fps
	_accumulator += delta
	var guard := 0
	while _accumulator >= dt_tick and guard < 6:
		_run_tick(dt_tick)
		_accumulator -= dt_tick
		guard += 1
		if not running:
			break
	if _accumulator > 0.75:
		_accumulator = 0.75

	# Измеряем реальную частоту тиков.
	_fps_time += delta
	if _fps_time >= 0.4:
		measured_fps = float(_fps_counter) / _fps_time
		_fps_counter = 0
		_fps_time = 0.0

	_overload_window += 1
	if _overload_seen:
		overload = true
	if _overload_window >= 90:
		overload = _overload_seen
		_overload_seen = false
		_overload_window = 0

	_emit_metrics(delta)


func _run_tick(dt_tick: float) -> void:
	if surface == null or vm == null:
		return
	vm.step_budget = stats.steps_budget
	var snapshot := surface.take_input_snapshot()
	vm.tick(dt_tick, snapshot)
	surface.end_tick()
	if vm.budget_exceeded:
		_overload_seen = true
	_fps_counter += 1
	_last_draw_count = vm.draw_commands.size()
	_push_frame()


func _push_frame() -> void:
	if surface == null or vm == null:
		return
	var state := "running"
	if stats != null and not stats.can_output():
		state = "no_signal"
	if vm.error != "":
		state = "error"
		error_message = vm.error
		error_line = vm.error_line
	surface.set_frame(vm.draw_commands, glitch, state,
		"OVR · программа тяжелее чипа" if vm.budget_exceeded else "",
		"%s (строка %d)" % [error_message, error_line])


func _show_error(vm: ChipVM) -> void:
	running = false
	error_message = vm.error
	error_line = vm.error_line
	if surface != null:
		surface.set_frame(vm.draw_commands, 1.0, "error", "", "%s (строка %d)" % [vm.error, vm.error_line])
	_emit_metrics(0.0, true)


func _update_surface_idle() -> void:
	if surface == null:
		return
	if stats == null:
		surface.signal_state = "idle"
	elif not stats.can_output():
		surface.signal_state = "no_signal"
		surface.error_text = ""
	else:
		surface.signal_state = "idle"
	surface.queue_redraw()


func _emit_metrics(delta: float = 0.0, force: bool = false) -> void:
	_metrics_time += delta
	if not force and _metrics_time < 0.08:
		return
	_metrics_time = 0.0
	metrics_changed.emit({
		"running": running,
		"fps": measured_fps,
		"target_fps": target_fps,
		"temperature": temperature,
		"glitch": glitch,
		"overload": overload,
		"error": error_message,
		"draw_calls": _last_draw_count,
		"halted": vm != null and vm.halted,
	})


func get_metrics() -> Dictionary:
	return {
		"running": running,
		"fps": measured_fps,
		"target_fps": target_fps,
		"temperature": temperature,
		"glitch": glitch,
		"overload": overload,
		"error": error_message,
		"draw_calls": _last_draw_count,
	}
