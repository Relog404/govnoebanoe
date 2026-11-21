extends SceneTree
## Headless-тесты: запуск
##   godot --headless --path . --script tests/headless_tests.gd
## Проверяют парсер/VM, схему, трассировку, сериализацию, примеры и главную сцену.

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run_tests()


func _check(condition: bool, name: String) -> void:
	_checks += 1
	if condition:
		print("  OK   ", name)
	else:
		_failures += 1
		printerr("  FAIL ", name)


func _section(title: String) -> void:
	print("\n== ", title, " ==")


func _input_state(extra: Dictionary = {}) -> Dictionary:
	var state := {
		"mouse": Vector2(160, 90),
		"down": {},
		"clicked": {},
		"released": {},
		"keys_down": {},
		"keys_pressed": {},
		"keys_released": {},
		"wheel": 0.0,
		"events": [],
	}
	for key in extra:
		state[key] = extra[key]
	return state


func _run_tests() -> void:
	await process_frame

	_section("Component library")
	ComponentLibrary.load_all(true)
	var defs := ComponentLibrary.all()
	_check(defs.size() >= 12, "loaded %d component definitions" % defs.size())
	var ids := {}
	for d in defs:
		ids[d.id] = true
		var port_ok := true
		for p in d.ports:
			var side := String(p.get("side", ""))
			var off := int(p.get("offset", 0))
			var lim: int = d.size.x if side == "N" or side == "S" else d.size.y
			if off < 0 or off >= lim:
				port_ok = false
			if not String(p.get("kind", "")) in ComponentDef.KINDS:
				port_ok = false
		_check(port_ok, "ports of %s are inside the footprint" % d.id)
	_check(ids.size() == defs.size(), "component ids are unique")

	_section("Parser")
	var parser := ChipScriptParser.new()
	var bad := parser.parse("func update(dt) { if { } }")
	_check(not bad.is_valid(), "syntax error is reported")
	var bad2 := parser.parse("var x = ")
	_check(not bad2.is_valid(), "incomplete expression is reported")
	var good := parser.parse("""
var total = 0
func update(dt) {
  var a = [1, 2, 3]
  push(a, 4)
  for v in a { total = total + v }
  if total > 5 and not false { total = total * 2 } else { total = 0 }
  while total > 100 { total = total - 1 }
  return total
}
""")
	_check(good.is_valid(), "valid program compiles: " + good.error_text())
	_check(good.functions.has("update"), "function collected")

	_section("VM: math, arrays, functions")
	var prog := parser.parse("""
var result = 0
var text = ""
func fib(n) {
  if n < 2 { return n }
  return fib(n - 1) + fib(n - 2)
}
func start() {
  result = fib(10)
  text = "a" + 1 + "b"
}
func update(dt) {
  var arr = [3, 1, 2]
  arr[0] = arr[0] + 10
  result = result + arr[0] + len(arr)
  for i in range(0, 3) { result = result + i }
}
""")
	_check(prog.is_valid(), "VM fixture compiles")
	var vm := ChipVM.new()
	vm.set_program(prog)
	vm.step_budget = 20000
	_check(vm.start(), "vm.start()")
	_check(int(vm.globals.get("result", 0)) == 55, "fib(10) = 55, got %s" % str(vm.globals.get("result")))
	_check(String(vm.globals.get("text", "")) == "a1b", "string concat")
	vm.tick(0.016, _input_state())
	_check(not vm.halted, "tick without error: " + vm.error)
	_check(int(vm.globals.get("result", 0)) == 55 + 13 + 3 + 3, "arrays + for loop, got %s"
		% str(vm.globals.get("result")))

	_section("VM: input, callbacks, drawing")
	var input_prog := parser.parse("""
var hits = 0
var keys = 0
var clicks = 0
var draw_count = 0
func update(dt) {
  hits = hits + mouse_x()
  if mouse_down(0) { hits = hits + 1 }
  if key_down("W") { keys = keys + 1 }
  if key_pressed("SPACE") { keys = keys + 10 }
  if mouse_clicked(0) { clicks = clicks + 1 }
  clear("#000000")
  fill_rect(1, 2, 3, 4, "#39ff88")
  text(4, 5, "hi", "red", 8)
  draw_count = draw_count + 1
}
func on_mouse_down(x, y, b) { clicks = clicks + 100 }
func on_key_down(k) { if k == "W" { keys = keys + 1000 } }
""")
	_check(input_prog.is_valid(), "input fixture compiles")
	var vm2 := ChipVM.new()
	vm2.set_program(input_prog)
	vm2.step_budget = 20000
	vm2.start()
	var state := _input_state({
		"mouse": Vector2(100, 50),
		"down": {0: true},
		"clicked": {0: true},
		"keys_down": {"W": true},
		"keys_pressed": {"SPACE": true},
		"events": [
			{"k": "mouse_down", "x": 100.0, "y": 50.0, "button": 0},
			{"k": "key_down", "key": "W"},
		],
	})
	vm2.tick(0.016, state)
	_check(not vm2.halted, "input tick without error: " + vm2.error)
	_check(int(vm2.globals.get("hits", 0)) == 101, "mouse pos + mouse_down, got %s"
		% str(vm2.globals.get("hits")))
	_check(int(vm2.globals.get("keys", 0)) == 1011, "key_down + key_pressed + callback, got %s"
		% str(vm2.globals.get("keys")))
	_check(int(vm2.globals.get("clicks", 0)) == 101, "mouse_clicked + callback, got %s"
		% str(vm2.globals.get("clicks")))
	_check(vm2.draw_commands.size() == 3, "3 draw commands recorded, got %d"
		% vm2.draw_commands.size())

	_section("VM: safety limits")
	var loop_prog := parser.parse("var n = 0\nfunc update(dt) { while true { n = n + 1 } }")
	var vm3 := ChipVM.new()
	vm3.set_program(loop_prog)
	vm3.step_budget = 500
	vm3.start()
	vm3.tick(0.016, _input_state())
	_check(vm3.budget_exceeded, "instruction budget stops an infinite loop")
	_check(not vm3.halted, "budget stop is not a fatal error")

	var recursion := parser.parse("func f(n) { return f(n + 1) }\nfunc start() { f(0) }")
	var vm4 := ChipVM.new()
	vm4.set_program(recursion)
	vm4.step_budget = 5000
	vm4.start()
	_check(vm4.halted and vm4.error != "", "deep recursion is caught: " + vm4.error)

	var undef := parser.parse("func start() { x = unknown + 1 }")
	var vm5 := ChipVM.new()
	vm5.set_program(undef)
	vm5.step_budget = 1000
	vm5.start()
	_check(vm5.halted and vm5.error.contains("unknown"), "unknown variable is a runtime error")

	_section("Wire router")
	var blocked := {}
	for y in range(-2, 3):
		blocked[Vector2i(0, y)] = true
	var from := Vector2i(-3, 0)
	var to := Vector2i(3, 0)
	var route := WireRouter.route(blocked, from, to)
	_check(bool(route.get("ok", false)), "route around a wall found")
	var path: Array = route.get("path", [])
	_check(path.size() >= 2 and path[0] == from and path[path.size() - 1] == to,
		"path endpoints")
	var orthogonal := true
	var avoids := true
	for i in range(1, path.size()):
		var a: Vector2i = path[i - 1]
		var b: Vector2i = path[i]
		if a.x != b.x and a.y != b.y:
			orthogonal = false
		for j in range(1, 10):
			var mid := Vector2i(roundi(lerpf(a.x, b.x, j / 10.0)), roundi(lerpf(a.y, b.y, j / 10.0)))
			if blocked.has(mid):
				avoids = false
	_check(orthogonal, "path segments are orthogonal")
	_check(avoids, "path avoids blocked cells")

	_section("Board model + demo")
	var demo := DemoProjects.demo_board()
	_check(demo.component_count() == 14, "demo has 14 components, got %d" % demo.component_count())
	_check(demo.links.size() == 19, "demo has 19 links, got %d" % demo.links.size())
	var overlap := false
	for i in demo.components.size():
		var a := demo.components[i]
		var da := demo.def_of(a)
		var ra := Rect2i(a["cell"], da.rotated_size(int(a["rot"])))
		for j in range(i + 1, demo.components.size()):
			var b := demo.components[j]
			var db := demo.def_of(b)
			var rb := Rect2i(b["cell"], db.rotated_size(int(b["rot"])))
			if ra.intersects(rb):
				overlap = true
				printerr("    overlap: %s / %s" % [da.id, db.id])
	_check(not overlap, "demo components do not overlap")

	var occupied := demo.occupied_cells()
	var routed := 0
	for link in demo.links:
		var ca := demo.get_component(int(link["a"]))
		var cb := demo.get_component(int(link["b"]))
		var pa := demo.port_info(ca, String(link["a_port"]))
		var pb := demo.port_info(cb, String(link["b_port"]))
		var res := WireRouter.route(occupied, pa["outward"], pb["outward"])
		if bool(res.get("ok", false)):
			routed += 1
		else:
			printerr("    route failed: %s.%s -> %s.%s" % [ca["def_id"], pa["name"],
				cb["def_id"], pb["name"]])
	_check(routed == demo.links.size(), "all demo links route (%d/%d)" % [routed, demo.links.size()])

	var stats := ChipEvaluator.evaluate(demo)
	for e in stats.errors:
		printerr("    evaluator error: ", e)
	for w in stats.warnings:
		printerr("    evaluator warning: ", w)
	_check(stats.errors.is_empty(), "demo board has no errors")
	_check(stats.output_connected, "demo video is connected")
	_check(stats.valid, "demo board is valid")
	_check(stats.fps_limit >= 30.0 and stats.fps_limit <= 60.0,
		"demo fps %.1f is in range" % stats.fps_limit)
	_check(stats.bandwidth_satisfaction >= 0.99, "demo memory bandwidth is enough")
	_check(stats.stability >= 0.9, "demo stability %.2f" % stats.stability)
	_check(stats.node_issues.is_empty(), "demo has no per-component issues")

	_section("Evaluator: broken chips")
	var empty := ChipBoard.new()
	var empty_stats := ChipEvaluator.evaluate(empty)
	_check(not empty_stats.errors.is_empty(), "empty board reports errors")

	var broken := ChipBoard.new()
	broken.add_component("gpu_core", Vector2i.ZERO)
	var broken_stats := ChipEvaluator.evaluate(broken)
	_check(not broken_stats.errors.is_empty(), "bare GPU reports errors")
	_check(not broken_stats.can_output(), "bare GPU has no signal")
	_check(not broken_stats.node_issues.is_empty(), "broken GPU is marked in the field")

	var serialized := demo.to_dict()
	var copy := ChipBoard.new()
	copy.from_dict(serialized)
	_check(copy.component_count() == demo.component_count(), "serialization keeps components")
	_check(copy.links.size() == demo.links.size(), "serialization keeps links")
	var same := true
	for i in demo.components.size():
		if copy.components[i]["cell"] != demo.components[i]["cell"]:
			same = false
		if copy.components[i]["rot"] != demo.components[i]["rot"]:
			same = false
	_check(same, "serialization keeps cells and rotations")
	var copy_stats := ChipEvaluator.evaluate(copy)
	_check(copy_stats.errors.is_empty() and copy_stats.output_connected,
		"deserialized demo is still valid")

	_section("Examples")
	for ex in DemoProjects.examples():
		var code := String(ex.get("code", ""))
		var p := parser.parse(code)
		if not p.is_valid():
			printerr("    ", ex.get("name"), ": ", p.error_text())
		_check(p.is_valid(), "example '%s' compiles" % ex.get("name"))
		if not p.is_valid():
			continue
		var evm := ChipVM.new()
		evm.set_program(p)
		evm.step_budget = 8000
		var started := evm.start()
		_check(started, "example '%s' starts" % ex.get("name"))
		var had_draw := false
		for i in 30:
			var st := _input_state({
				"mouse": Vector2(80 + i, 70 + i),
				"clicked": {0: true} if i == 5 else {},
				"down": {0: true} if i > 5 and i < 9 else {},
				"keys_down": {"D": true} if i % 2 == 0 else {},
				"keys_pressed": {"SPACE": true} if i == 7 else {},
				"events": [{"k": "mouse_down", "x": 80.0, "y": 70.0, "button": 0}] if i == 5 else [],
			})
			evm.tick(0.016, st)
			if evm.draw_commands.size() > 0:
				had_draw = true
			if evm.halted:
				break
		_check(not evm.halted, "example '%s' runs: %s" % [ex.get("name"), evm.error])
		_check(had_draw, "example '%s' draws" % ex.get("name"))
		_check(not evm.budget_exceeded, "example '%s' fits the instruction budget" % ex.get("name"))

	_section("Main scene")
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "main.tscn loads")
	if scene != null:
		var main = scene.instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		_check(main.board != null and main.board.component_count() == 14, "main has demo board")
		_check(main.chip_view != null and main.chip_view.field != null, "chip field built")
		_check(main.output != null and main.output.surface != null, "output surface built")
		_check(main.ide != null and main.ide.code_edit != null, "IDE built")
		_check(main.stats != null, "stats computed")
		main.chip_view.set_issues(main.stats.node_issues)
		_check(main.chip_view.field.issues.is_empty(), "field receives component issues")

		main._on_run()
		await process_frame
		await process_frame
		_check(main.runtime.running, "runtime started from UI: " + main.runtime.error_message)

		# Прямая проверка ввода на экране вывода.
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(100, 100)
		motion.global_position = motion.position
		main.output.surface._input(motion)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = Vector2(100, 100)
		click.global_position = click.position
		main.output.surface._input(click)
		var key := InputEventKey.new()
		key.keycode = KEY_W
		key.pressed = true
		main.output.surface._input(key)
		_check(main.output.surface.input_state["mouse"] != Vector2.ZERO, "surface tracks mouse")
		_check(main.output.surface.input_state["down"].has(MOUSE_BUTTON_LEFT),
			"surface tracks mouse button")
		_check(main.output.surface.input_state["keys_down"].has("W"), "surface tracks keys")

		for i in 5:
			await process_frame
		_check(main.runtime.vm != null, "VM created")

		main._toggle_fullscreen()
		await process_frame
		_check(main.output.get_parent() == main._fullscreen_content, "fullscreen reparent")
		main._toggle_fullscreen()
		await process_frame
		_check(main.output.get_parent() == main._output_page, "fullscreen restored")

		main._toggle_help()
		_check(main._help_overlay.visible, "help overlay opens")
		main._toggle_help()
		_check(not main._help_overlay.visible, "help overlay closes")

		_section("Field input via SubViewport")
		main._do_new_board()
		await process_frame
		var field = main.chip_view.field
		var sv = main.chip_view._sub_viewport
		var center := Vector2(sv.size) * 0.5
		var field_motion := InputEventMouseMotion.new()
		field_motion.position = center
		field_motion.global_position = center
		sv.push_input(field_motion, true)
		field.set_placing("gpu_core")
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = center
		press.global_position = center
		sv.push_input(press, true)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = center
		release.global_position = center
		sv.push_input(release, true)
		_check(main.board.component_count() == 1, "click on the field places a component")
		var placed: Dictionary = main.board.find_component_at(Vector2i.ZERO)
		_check(not placed.is_empty() and String(placed.get("def_id", "")) == "gpu_core",
			"placed GPU at the cursor cell")

		var rot_key := InputEventKey.new()
		rot_key.keycode = KEY_R
		rot_key.pressed = true
		sv.push_input(rot_key, true)
		_check(int(placed.get("rot", 0)) == 1, "R rotates the hovered component")

		var del_key := InputEventKey.new()
		del_key.keycode = KEY_DELETE
		del_key.pressed = true
		sv.push_input(del_key, true)
		_check(main.board.component_count() == 0, "Delete removes the selected component")

		_section("Palette drag and drop")
		main._do_new_board()
		await process_frame
		var drop_area = main.chip_view._field_container
		var data := {"kind": "component_def", "def_id": "capacitor"}
		_check(drop_area._can_drop_data(Vector2.ZERO, data), "drop area accepts component defs")
		_check(not drop_area._can_drop_data(Vector2.ZERO, {"kind": "nope"}), "drop area rejects junk")
		drop_area._drop_data(center, data)
		await process_frame
		_check(main.board.component_count() == 1, "dragging from the palette places a component")
		var dropped: Dictionary = main.board.find_component_at(Vector2i.ZERO)
		_check(not dropped.is_empty() and String(dropped.get("def_id", "")) == "capacitor",
			"dropped component is at the drop cell")

		_section("Output screen input")
		var tex_center: Vector2 = main.output._texture_rect.get_global_rect().get_center()
		var out_motion := InputEventMouseMotion.new()
		out_motion.position = tex_center
		out_motion.global_position = tex_center
		main.output._input(out_motion)
		_check(main.output._hover_area, "output screen notices the cursor")
		var out_key := InputEventKey.new()
		out_key.keycode = KEY_SPACE
		out_key.pressed = true
		main.output._input(out_key)
		_check(main.output.surface.input_state["keys_down"].has("SPACE"),
			"keys are pushed into the chip display")
		var out_click := InputEventMouseButton.new()
		out_click.button_index = MOUSE_BUTTON_LEFT
		out_click.pressed = true
		out_click.position = tex_center
		out_click.global_position = tex_center
		main.output._input(out_click)
		_check(main.output.surface.input_state["down"].has(MOUSE_BUTTON_LEFT),
			"clicks are pushed into the chip display")

		_section("Live simulation")
		main._on_demo_pressed()
		await process_frame
		main._on_run()
		for i in 4:
			main.runtime._process(0.1)
		_check(main.runtime.running, "runtime ticks while running")
		_check(main.runtime.measured_fps > 0.0, "measured fps is positive (%.1f)"
			% main.runtime.measured_fps)
		await process_frame
		_check(main.output.surface.signal_state == "running", "screen shows a running signal")
		_check(main.output.surface.commands.size() > 0, "draw commands reach the screen")

		_section("Broken chip still runs")
		main._on_stop()
		main._do_new_board()
		main.board.add_component("gpu_core", Vector2i.ZERO)
		main._refresh_stats()
		main._on_run()
		main.runtime._process(0.1)
		_check(main.runtime.running, "a broken chip still runs")
		_check(main.output.surface.signal_state == "no_signal", "broken chip shows no signal")
		main._on_stop()

		main._on_demo_pressed()
		await process_frame

		main._on_save_path("user://test_project.json")
		var saved := FileAccess.file_exists("user://test_project.json")
		_check(saved, "project saved to JSON")
		var before_code: String = main.ide.get_code()
		main.board.clear()
		main.ide.set_code("# empty")
		main._on_load_path("user://test_project.json")
		await process_frame
		_check(main.board.component_count() == 14, "project loaded from JSON")
		_check(main.ide.get_code() == before_code, "code restored from JSON")

		main._on_stop()
		_check(not main.runtime.running, "stop works")
		main.queue_free()
		await process_frame

	print("\n------------------------------")
	print("checks: %d, failures: %d" % [_checks, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("TESTS FAILED")
	quit(1 if _failures > 0 else 0)
