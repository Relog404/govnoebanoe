extends RefCounted

# «Кремний» — сценарий генерации платы. Пишется в окне «Сценарий платы».
# Скрипт строит плату ТОЛЬКО из внутриигровых компонентов: все place проходят
# через ту же машинную библиотеку (TYPE_MAP), что и ручная работа игрока.
#
# Синтаксис (построчно, «#» — комментарий вне строк):
#   board 16x10            — размер платы в клетках (клетка = 10 мм)
#   board 160x100mm        — то же в миллиметрах (кратно 10, 20…400)
#   clear                  — стереть плату и провода (сохраняет размер)
#   place <тип> <ID> at <x>,<y> [rot=N] [ключ=значение …]
#   erase <ID>
#   wire <ID.пин> -> <ID.пин>
#   unwire <ID.пин> -> <ID.пин>
#   asm <ID> … end         — ассемблер MINI-8 (или другой ISA чипа) для прошивки
#   flash <ID>             — собрать asm для чипа, прошить и запустить
#   start <ID> / reset <ID>
#   note "текст"           — тост в HUD
#
# Значения: числа (10, 3.3, 0x1F, $1F, %101, 0b101), строки "…", true/false,
# массивы [a,b], объекты {ключ=значение, …}; голые слова — строки.
# Пример: place chip_dip16 GFX at 4,2 rot=0 pins=16 io_map={0=[P1..P8]}

const TYPES := ["transistor", "resistor", "capacitor", "led", "diode",
	"chip_dip8", "chip_dip16", "oled", "matrix", "7seg",
	"button", "switch", "slot", "power",
	"trace_straight", "trace_corner", "trace_t", "trace_cross", "case"]

var _editor: Node
var _log: Array[String] = []
var _asm: Dictionary = {}   # id → Array[String] исходника
var _line_no := 0

func run(source: String, editor: Node) -> Dictionary:
	_editor = editor
	_log.clear()
	_asm.clear()
	_line_no = 0
	var lines := source.split("\n")
	var i := 0
	while i < lines.size():
		_line_no = i + 1
		var raw := lines[i]
		var line := _strip_comment(raw).strip_edges()
		if line.is_empty():
			i += 1
			continue
		if line.begins_with("asm ") or line == "asm":
			var id := line.substr(3).strip_edges()
			if not id.is_valid_identifier():
				return _fail("asm: неверный id чипа: «%s»" % id)
			var buf: Array[String] = []
			i += 1
			var closed := false
			while i < lines.size():
				var body := lines[i]
				if body.strip_edges() == "end":
					closed = true
					break
				buf.append(body)
				i += 1
			_line_no = i + 1
			if not closed:
				return _fail("asm %s: блок не закрыт «end»" % id)
			var prev: Array = _asm.get(id, [])
			prev.append_array(buf)
			_asm[id] = prev
			_say("Ассемблер для %s: %d строк" % [id, buf.size()])
			i += 1
			continue
		var err := _exec_line(line)
		if not err.is_empty():
			return _fail(err)
		i += 1
	_say("Готово.")
	return {"ok": true, "log": _log, "error": "", "line": 0}

# ---------- Внутреннее ----------

func _fail(message: String) -> Dictionary:
	var msg := "Строка %d: %s" % [_line_no, message]
	_log.append("ОШИБКА » " + msg)
	return {"ok": false, "log": _log, "error": msg, "line": _line_no}

func _say(message: String) -> void:
	_log.append(message)

func _editor_call(method: StringName, args: Array = []) -> Variant:
	if _editor == null or not _editor.has_method(method):
		return null
	return _editor.callv(method, args)

# ---------- Лексер ----------

func _strip_comment(raw: String) -> String:
	var out := ""
	var in_string := false
	var i := 0
	while i < raw.length():
		var ch := raw[i]
		if ch == '"':
			in_string = not in_string
			out += ch
		elif ch == "#" and not in_string:
			break
		else:
			out += ch
		i += 1
	return out

func _lex(text: String) -> Dictionary:
	var tokens: Array[Dictionary] = []
	var i := 0
	var n := text.length()
	var depth := 0  # глубина скобок: запятые-разделители только внутри них
	while i < n:
		var ch := text[i]
		if ch == ' ' or ch == '\t' or (ch == ',' and depth > 0):
			i += 1
			continue
		if ch == '"':
			var j := i + 1
			var buf := ""
			while j < n and text[j] != '"':
				if text[j] == '\\' and j + 1 < n:
					j += 1
					match text[j]:
						"n": buf += "\n"
						"t": buf += "\t"
						'"': buf += '"'
						"\\": buf += "\\"
						_: buf += text[j]
				else:
					buf += text[j]
				j += 1
			if j >= n:
				return {"ok": false, "error": "строка не закрыта кавычкой", "tokens": []}
			tokens.append({"t": "string", "v": buf})
			i = j + 1
			continue
		match ch:
			"=":
				tokens.append({"t": "eq"})
				i += 1
				continue
			"[":
				tokens.append({"t": "open", "v": "["})
				depth += 1
				i += 1
				continue
			"]":
				tokens.append({"t": "close", "v": "["})
				depth = maxi(0, depth - 1)
				i += 1
				continue
			"{":
				tokens.append({"t": "open", "v": "{"})
				depth += 1
				i += 1
				continue
			"}":
				tokens.append({"t": "close", "v": "{"})
				depth = maxi(0, depth - 1)
				i += 1
				continue
		var j := i
		while j < n:
			var c2 := text[j]
			if c2 == ' ' or c2 == '\t' or c2 == '=' or c2 == '[' or c2 == ']' or c2 == '{' or c2 == '}' or c2 == '"':
				break
			if c2 == ',' and depth > 0:
				break
			j += 1
		if j == i:
			return {"ok": false, "error": "неожиданный символ «%s»" % ch, "tokens": []}
		tokens.append({"t": "word", "v": text.substr(i, j - i)})
		i = j
	return {"ok": true, "tokens": tokens}

# ---------- Парсер значений ----------

func _number_or_null(word: String) -> Variant:
	var w := word.strip_edges()
	var lower := w.to_lower()
	if lower.begins_with("$"):
		var h := lower.substr(1)
		return h.hex_to_int() if h.is_valid_hex_number(false) else null
	if lower.begins_with("0x"):
		var h2 := lower.substr(2)
		return h2.hex_to_int() if h2.is_valid_hex_number(false) else null
	if lower.begins_with("%"):
		var b := lower.substr(1)
		return b.bin_to_int() if b.replace("0", "").replace("1", "") == "" and b != "" else null
	if lower.begins_with("0b"):
		var b2 := lower.substr(2)
		return b2.bin_to_int() if b2.replace("0", "").replace("1", "") == "" and b2 != "" else null
	if w.is_valid_int():
		return w.to_int()
	if w.is_valid_float():
		return w.to_float()
	return null

func _value_at(tokens: Array, state: Dictionary) -> Dictionary:
	if state.i >= tokens.size():
		return {"ok": false, "error": "неожиданный конец строки"}
	var tok: Dictionary = tokens[state.i]
	match tok.t:
		"string":
			state.i += 1
			return {"ok": true, "value": tok.v}
		"open":
			if tok.v == "[":
				state.i += 1
				var arr: Array = []
				while true:
					if state.i >= tokens.size():
						return {"ok": false, "error": "массив не закрыт «]»"}
					var t2: Dictionary = tokens[state.i]
					if t2.t == "close" and t2.v == "[":
						state.i += 1
						return {"ok": true, "value": arr}
					var item := _value_at(tokens, state)
					if not item.ok:
						return item
					arr.append(item.value)
			else:
				state.i += 1
				var obj := {}
				while true:
					if state.i >= tokens.size():
						return {"ok": false, "error": "объект не закрыт «}»"}
					var key_tok: Dictionary = tokens[state.i]
					if key_tok.t == "close" and key_tok.v == "{":
						state.i += 1
						return {"ok": true, "value": obj}
					if key_tok.t != "word":
						return {"ok": false, "error": "ключ объекта должен быть словом"}
					var key := str(key_tok.v)
					state.i += 1
					if state.i >= tokens.size() or (tokens[state.i] as Dictionary).t != "eq":
						return {"ok": false, "error": "в объекте нужен «ключ=значение»"}
					state.i += 1
					var item2 := _value_at(tokens, state)
					if not item2.ok:
						return item2
					obj[key] = item2.value
		"eq":
			return {"ok": false, "error": "ожидалось значение перед «=»"}
		_:
			state.i += 1
			var word := str(tok.v)
			var lower := word.to_lower()
			if lower == "true":
				return {"ok": true, "value": true}
			if lower == "false":
				return {"ok": true, "value": false}
			if lower == "null":
				return {"ok": true, "value": null}
			var num: Variant = _number_or_null(word)
			if num != null:
				return {"ok": true, "value": num}
			return {"ok": true, "value": word}  # голое слово = строка
	return {"ok": false, "error": "не разобран токен"}

# Пары ключ=значение из остатка строки; ключ может быть «rot» без «=» и числа-значения.
func _parse_args(tokens: Array, start: int) -> Dictionary:
	var out := {"ok": true, "params": {}, "rot": 0}
	var state := {"i": start}
	while state.i < tokens.size():
		var key_tok: Dictionary = tokens[state.i]
		if key_tok.t != "word":
			return {"ok": false, "error": "ожидался ключ параметра"}
		var key := str(key_tok.v)
		var lower := key.to_lower()
		state.i += 1
		# Форма «rot 1» (без знака равенства) — для удобства.
		if (state.i < tokens.size()) and (tokens[state.i] as Dictionary).t == "word" and (lower == "rot"):
			var n: Variant = _number_or_null(str((tokens[state.i] as Dictionary).v))
			if n == null:
				return {"ok": false, "error": "rot ждёт целое 0…3"}
			out.rot = int(n)
			state.i += 1
			continue
		if state.i >= tokens.size() or (tokens[state.i] as Dictionary).t != "eq":
			return {"ok": false, "error": "после «%s» нужен «=»" % key}
		state.i += 1
		var item := _value_at(tokens, state)
		if not item.ok:
			return {"ok": false, "error": str(item.error)}
		if lower == "rot":
			out.rot = int(item.value)
		else:
			(out.params as Dictionary)[key] = item.value
	return out

# ---------- Команды ----------

func _exec_line(line: String) -> String:
	var lexed := _lex(line)
	if not lexed.ok:
		return str(lexed.error)
	var tokens: Array = lexed.tokens
	if tokens.is_empty():
		return ""
	var head := str((tokens[0] as Dictionary).v).to_lower() if (tokens[0] as Dictionary).t == "word" else ""
	match head:
		"board":
			return _cmd_board(tokens)
		"clear":
			_editor_call("clear_all")
			_editor_call("clear_debris")
			_say("Плата очищена.")
			return ""
		"place":
			return _cmd_place(tokens)
		"erase":
			if tokens.size() != 2 or (tokens[1] as Dictionary).t != "word":
				return "erase ждёт id детали"
			var id := str((tokens[1] as Dictionary).v)
			_say("erase %s: %s" % [id, "ок" if bool(_editor_call("erase_part", [id])) else "не найдена"])
			return ""
		"wire":
			return _cmd_wire(tokens, true)
		"unwire":
			return _cmd_wire(tokens, false)
		"asm":
			return "asm — блочная команда: asm <ID> … end"
		"flash":
			if tokens.size() != 2 or (tokens[1] as Dictionary).t != "word":
				return "flash ждёт id чипа"
			return _cmd_flash(str((tokens[1] as Dictionary).v))
		"start":
			if tokens.size() != 2 or (tokens[1] as Dictionary).t != "word":
				return "start ждёт id чипа"
			return _cmd_call_chip("start", tokens)
		"reset":
			if tokens.size() != 2 or (tokens[1] as Dictionary).t != "word":
				return "reset ждёт id чипа"
			return _cmd_call_chip("reset", tokens)
		"note":
			var parts: Array[String] = []
			for t: Dictionary in tokens.slice(1):
				parts.append(str(t.get("v", "")))
			_say("«%s»" % " ".join(parts))
			return ""
		_:
			return "неизвестная команда: «%s» (board, clear, place, erase, wire, unwire, asm, flash, start, reset, note)" % head

func _cmd_board(tokens: Array) -> String:
	var text := ""
	for i in tokens.size() - 1:
		var t: Dictionary = tokens[i + 1]
		var word := str(t.get("v", ""))
		text += word + " "
	text = text.strip_edges().to_lower().replace(" ", "")
	var mm := text.ends_with("mm")
	if mm:
		text = text.substr(0, text.length() - 2)
	var pieces := text.split("x", false)
	if pieces.size() != 2:
		return "board: жди «board 16x10» или «board 160x100mm»"
	var a: Variant = _number_or_null(pieces[0])
	var b: Variant = _number_or_null(pieces[1])
	if a == null or b == null:
		return "board: размеры должны быть числами"
	var w_mm := float(a) * (10.0 if not mm else 1.0)
	var h_mm := float(b) * (10.0 if not mm else 1.0)
	var ok: Variant = _editor_call("resize_board", [w_mm, h_mm])
	if ok == null or not bool(ok):
		return "board: не вышло (20…400 мм, кратно 10)"
	_say("Плата: %d×%d мм" % [int(w_mm), int(h_mm)])
	return ""

func _cmd_place(tokens: Array) -> String:
	if tokens.size() < 5:
		return "place: жди «place <тип> <ID> at <x>,<y> [ключ=значение …]»"
	var type_tok := tokens[1] as Dictionary
	var id_tok := tokens[2] as Dictionary
	if type_tok.t != "word" or id_tok.t != "word":
		return "place: тип и id должны быть словами"
	var kind := str(type_tok.v).to_lower()
	if not TYPES.has(kind):
		return "place: неизвестный тип «%s». Доступно: %s" % [kind, ", ".join(TYPES)]
	var id := str(id_tok.v)
	if not id.is_valid_identifier():
		return "place: id «%s» не является идентификатором" % id
	var at_tok := tokens[3] as Dictionary
	if at_tok.t != "word" or str(at_tok.v).to_lower() != "at":
		return "place: нужен «at»"
	var cell_tok := tokens[4] as Dictionary
	if cell_tok.t != "word":
		return "place: клетка вида «x,y»"
	var cell_parts := str(cell_tok.v).split(",", false)
	if cell_parts.size() != 2:
		return "place: клетка вида «x,y», например at 3,4"
	var cx: Variant = _number_or_null(cell_parts[0])
	var cy: Variant = _number_or_null(cell_parts[1])
	if cx == null or cy == null:
		return "place: координаты клетки должны быть целыми"
	var arg_result := _parse_args(tokens, 5)
	if not arg_result.ok:
		return "place: " + str(arg_result.error)
	var rot := clampi(int(arg_result.rot), 0, 3)
	var params: Dictionary = arg_result.params
	var ok: Variant = _editor_call("place_typed", [kind, id, Vector2i(int(cx), int(cy)), rot, params])
	if ok == null or not bool(ok):
		return "place: не вышло разместить %s в (%d, %d) — клетка занята или деталь уже есть" % [id, int(cx), int(cy)]
	_say("place %s %s at %d,%d rot=%d" % [kind, id, int(cx), int(cy), rot])
	return ""

func _cmd_wire(tokens: Array, is_wire: bool) -> String:
	if tokens.size() < 4:
		return "%s: жди «%s <ID.пин> -> <ID.пин>»" % (["wire", "wire"] if is_wire else ["unwire", "unwire"])
	var sep := -1
	for idx in tokens.size():
		var t: Dictionary = tokens[idx]
		if t.t == "word" and str(t.v) == "->":
			sep = idx
			break
	if sep != 2 or tokens.size() != 4:
		return "%s: жди ровно «<ID.пин> -> <ID.пин>»" % ("wire" if is_wire else "unwire")
	var a := str((tokens[1] as Dictionary).v)
	var b := str((tokens[3] as Dictionary).v)
	if not _valid_pin(a) or not _valid_pin(b):
		return "%s: пин в форме <ID>.<пин>, например GFX.P9" % ("wire" if is_wire else "unwire")
	var method := "wire_pins" if is_wire else "unwire_pins"
	var ok: Variant = _editor_call(method, [a, b])
	if ok == null:
		return "%s: редактор не отвечает" % method
	if bool(ok):
		_say("%s %s — %s" % [("Припаяно" if is_wire else "Отпаяно"), a, b])
		return ""
	return "%s %s — %s: не получилось (нет пина или уже соединены)" % [("wire" if is_wire else "unwire"), a, b]

func _cmd_call_chip(action: String, tokens: Array) -> String:
	var id := str((tokens[1] as Dictionary).v)
	var node: Node = _editor_call("get_part_node", [id])
	if node == null:
		return "чип %s не найден" % id
	node.on_event(action)
	_say("%s %s" % [action, id])
	return ""

func _valid_pin(pin: String) -> bool:
	var at := pin.find(".")
	if at <= 0 or at >= pin.length() - 1 or at != pin.rfind("."):
		return false
	if not pin.left(at).is_valid_identifier():
		return false
	var suffix := pin.substr(at + 1)
	for ch in suffix:
		if not (ch.is_valid_identifier() or (ch >= "0" and ch <= "9")):
			return false
	return true

func _cmd_flash(id: String) -> String:
	# Собираем ассемблер, который ушёл в asm <id> … end
	if not _asm.has(id):
		return "flash: у чипа %s нет блока asm %s … end" % [id, id]
	var source := "\n".join(_asm[id]) + "\n"
	var node: Node = _editor_call("get_part_node", [id])
	if node == null:
		return "flash: чип %s не найден на плате" % id
	var isa_path := ""
	if node.get("params") is Dictionary:
		isa_path = str((node.get("params") as Dictionary).get("isa", ""))
	if isa_path.is_empty():
		return "flash: у чипа %s в params нет «isa» (путь к .json)" % id
	var tree := Engine.get_main_loop() as SceneTree
	var loader: Node = tree.root.get_node_or_null("IsaLoader") if tree else null
	if loader == null:
		return "flash: IsaLoader недоступен (автозагрузка)"
	var isa: Dictionary = loader.load_isa(isa_path)
	if not isa.get("ok", false):
		return "flash: ISA не собралась: %s" % str(isa.get("error", "?"))
	var assembled: Dictionary = loader.assemble(source, isa)
	if not assembled.get("ok", false):
		return "flash: ассемблер упал: %s (строка %s)" % [str(assembled.get("error", "?")), str(assembled.get("line", "?"))]
	var bytes: Array = assembled.get("bytes", [])
	node.on_event("flash", {"bytes": bytes})
	node.on_event("start")
	_say("flash %s: %d байт, чип запущен" % [id, bytes.size()])
	return ""
