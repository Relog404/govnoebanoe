extends Node

# Каждому чипу можно передать свою таблицу. JSON описывает байты, операнды
# и последовательность микроопераций; никакого eval и загрузки скриптов.
const OPS := {"mov":"rv", "add":"rv", "sub":"rv", "and":"rv", "or":"rv", "xor":"rv",
	"ld":"rv", "st":"vv", "jmp":"v", "jz":"vv", "jnz":"vv",
	"in":"rv", "out":"vv", "ldi":"rvv", "halt":"", "nop":""}

func _bad(message: String, line: int = 0) -> Dictionary:
	return {"ok": false, "error": message, "line": line}

func _uint(v: Variant, maximum: int) -> bool:
	return (v is int or v is float) and v >= 0 and v <= maximum and int(v) == v

# Убирает «;» вне кавычек: комментарий обрезается, строки остаются целыми.
func _strip_comment(raw: String) -> String:
	var out := ""
	var in_string := false
	var i := 0
	while i < raw.length():
		var ch := raw[i]
		if ch == '"':
			in_string = not in_string
			out += ch
		elif ch == ";" and not in_string:
			break
		else:
			out += ch
		i += 1
	return out

# Верхний регистр вне строк (строки для DB должны сохранять UTF-8 как есть).
func _upper_outside_strings(raw: String) -> String:
	var out := ""
	var in_string := false
	for ch in raw:
		if ch == '"':
			in_string = not in_string
			out += ch
		elif in_string:
			out += ch
		else:
			out += ch.to_upper()
	return out

# Индекс «:» вне кавычек?
func _colon_in_string(text: String, idx: int) -> bool:
	var in_string := false
	for i in text.length():
		if i >= idx:
			break
		if text[i] == '"':
			in_string = not in_string
	return in_string

# Токенизатор операндов DB: слова и строки в кавычках.
func _db_tokens(text: String) -> Array:
	var tokens := []
	var cur := ""
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		if ch == '"':
			if cur.strip_edges() != "":
				tokens.append({"t": "word", "v": cur.strip_edges()})
			cur = ""
			var j := i + 1
			var buf := ""
			while j < n and text[j] != '"':
				if text[j] == '\\' and j + 1 < n:
					j += 1
					match text[j]:
						"n": buf += "\n"
						"0": buf += char(0)
						'"': buf += '"'
						"\\": buf += "\\"
						_: buf += text[j]
				else:
					buf += text[j]
				j += 1
			tokens.append({"t": "str", "v": buf})
			i = j + 1
			continue
		elif ch == "," or ch == " " or ch == "\t":
			if cur.strip_edges() != "":
				tokens.append({"t": "word", "v": cur.strip_edges()})
			cur = ""
		else:
			cur += ch
		i += 1
	if cur.strip_edges() != "":
		tokens.append({"t": "word", "v": cur.strip_edges()})
	return tokens

func _parse_db_word(token: String) -> Dictionary:
	# Возвращает {"byte": int} или {"label": String} или {} при ошибке.
	var t := token.strip_edges()
	var lower := t.to_lower()
	var hex_digits := ""
	if lower.begins_with("$"):
		hex_digits = lower.substr(1)
	elif lower.begins_with("0x"):
		hex_digits = lower.substr(2)
	if not hex_digits.is_empty():
		if hex_digits.is_valid_hex_number(false):
			return {"byte": hex_digits.hex_to_int()}
		return {}
	if lower.begins_with("%"):
		var bin := lower.substr(1)
		if bin.is_valid_int() and bin.replace("0", "").replace("1", "") == "":
			return {"byte": bin.bin_to_int()}
		return {}
	elif lower.begins_with("0b"):
		var bin2 := lower.substr(2)
		if bin2.replace("0", "").replace("1", "") == "":
			return {"byte": bin2.bin_to_int()}
		return {}
	elif t.is_valid_int():
		return {"byte": t.to_int()}
	elif t.is_valid_identifier():
		return {"label": t.to_upper()}
	return {}

func load_isa(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	return compile_isa(f.get_as_text()) if f else _bad("Не открыть ISA: " + path)

func compile_isa(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _bad(json.get_error_message(), json.get_error_line() + 1)
	var doc: Variant = json.data
	if not doc is Dictionary or not doc.get("instructions") is Array or doc.instructions.is_empty():
		return _bad("Нужен непустой массив instructions")
	var count: Variant = doc.get("registers", 8)
	if not _uint(count, 16) or count < 1:
		return _bad("Число регистров: 1…16")
	var names := {}
	var codes := {}
	for item: Variant in doc.instructions:
		if not item is Dictionary or not item.get("name") is String or not _uint(item.get("code"), 255):
			return _bad("Неверное имя или код инструкции")
		var name_uc := str(item.name).to_upper()
		var code := int(item.code)
		if not name_uc.is_valid_identifier() or names.has(name_uc) or codes.has(code):
			return _bad("Повтор или неверное имя: " + name_uc)
		var args: Variant = item.get("args", [])
		var ops: Variant = item.get("do")
		if not args is Array or args.size() > 8 or not ops is Array or ops.is_empty() or ops.size() > 64:
			return _bad("Неверная сигнатура: " + name_uc)
		for arg: Variant in args:
			if arg not in ["r", "u8", "addr"]:
				return _bad("Тип операнда: r, u8 или addr")
		for op: Variant in ops:
			if not op is Array or op.is_empty() or not OPS.has(op[0]):
				return _bad("Неизвестная микрооперация: " + name_uc)
			var spec: String = OPS[op[0]]
			if op.size() != 1 + spec.length():
				return _bad("Арность микрооперации: " + name_uc)
			for i in spec.length():
				if not _uint(op[i + 1], args.size() - 1):
					return _bad("Нет такого операнда: " + name_uc)
				if spec[i] == "r" and args[int(op[i + 1])] != "r":
					return _bad("Запись разрешена только в регистр")
		var desc := {"name": name_uc, "code": code, "args": args, "do": ops}
		names[name_uc] = desc
		codes[code] = desc
	return {"ok": true, "registers": int(count), "names": names, "codes": codes}

# Первый проход считает байтовые адреса меток, второй проверяет и кодирует.
func assemble(source: String, isa: Dictionary) -> Dictionary:
	if not isa.get("ok", false):
		return _bad("ISA не скомпилирована")
	var rows := []
	var labels := {}
	var pc := 0
	var line := 0
	for raw: String in source.split("\n"):
		line += 1
		var clean := _strip_comment(raw)
		var s := _upper_outside_strings(clean).strip_edges()
		var colon := s.find(":")
		if colon >= 0 and _colon_in_string(s, colon):
			colon = -1
		if colon >= 0:
			var label := s.get_slice(":", 0).strip_edges()
			if not label.is_valid_identifier() or labels.has(label):
				return _bad("Неверная или повторная метка", line)
			labels[label] = pc
			s = s.substr(colon + 1).strip_edges()
		if s.is_empty():
			continue
		var words := s.replace("\t", " ").replace(",", " ").split(" ", false)
		if words[0] == "DB":
			var bytes := []
			var pending := []  # ссылки на метки (в т.ч. вперёд), адрес = 1 байт
			var joined := clean.substr(clean.find("DB") + 2) if clean.find("DB") >= 0 else s.substr(2)
			for tok: Dictionary in _db_tokens(joined):
				if tok.t == "str":
					var buf := str(tok.v).to_utf8_buffer()
					for b in buf:
						bytes.append(b)
						pending.append(null)
					continue
				var parsed := _parse_db_word(str(tok.v))
				if parsed.has("byte"):
					var b2 := int(parsed.byte)
					if b2 < 0 or b2 > 255:
						return _bad("Неверный байт в DB: " + str(tok.v), line)
					bytes.append(b2)
					pending.append(null)
				elif parsed.has("label"):
					bytes.append(0)  # плейсхолдер, адрес метки запишем во втором проходе
					pending.append(str(parsed.label))
				else:
					return _bad("Неверный байт в DB: " + str(tok.v), line)
			rows.append([line, {"name": "DB", "bytes": bytes, "pending": pending}, []])
			pc += bytes.size()
			if pc > 256:
				return _bad("Программа больше 256 байт", line)
			continue
		if not isa.names.has(words[0]):
			return _bad("Неизвестная инструкция: " + words[0], line)
		var desc: Dictionary = isa.names[words[0]]
		if words.size() != desc.args.size() + 1:
			return _bad("Неверное число операндов", line)
		rows.append([line, desc, words])
		pc += words.size()
		if pc > 256:
			return _bad("Программа больше 256 байт", line)
	var image := []
	for row: Array in rows:
		var desc: Dictionary = row[1]
		if desc.get("name") == "DB":
			var db_bytes: Array = desc.bytes
			var pending: Array = desc.get("pending", [])
			for i in db_bytes.size():
				var label: Variant = pending[i] if i < pending.size() else null
				if label != null:
					if not labels.has(str(label)):
						return _bad("Неизвестная метка в DB: " + str(label), row[0])
					db_bytes[i] = int(labels[str(label)])
			image.append_array(db_bytes)
			continue
		image.append(desc.code)
		for i in desc.args.size():
			var token: String = row[2][i + 1]
			var n := -1
			if desc.args[i] == "r":
				if token.begins_with("R") and token.substr(1).is_valid_int():
					n = token.substr(1).to_int()
				if n >= int(isa.registers):
					n = -1
			elif labels.has(token) and desc.args[i] == "addr":
				n = labels[token]
			elif token.to_lower().is_valid_hex_number(true):
				n = token.hex_to_int()
			elif token.is_valid_int():
				n = token.to_int()
			if n < 0 or n > 255:
				return _bad("Неверный операнд: " + token, row[0])
			image.append(n)
	return {"ok": true, "bytes": image}

func _decode(bytes: Array, pc: int, isa: Dictionary) -> Dictionary:
	if pc < 0 or pc >= bytes.size() or not _uint(bytes[pc], 255) or not isa.codes.has(int(bytes[pc])):
		return _bad("Адрес или опкод вне ISA: %02X" % pc)
	var d: Dictionary = isa.codes[int(bytes[pc])]
	var end: int = pc + 1 + d.args.size()
	if end > bytes.size():
		return _bad("Неполная инструкция по адресу %02X" % pc)
	var operands := bytes.slice(pc + 1, end)
	for i in operands.size():
		if not _uint(operands[i], int(isa.registers) - 1 if d.args[i] == "r" else 255):
			return _bad("Операнд вне диапазона по адресу %02X" % pc)
	return {"ok": true, "d": d, "operands": operands, "end": end}

func disassemble(bytes: Array, isa: Dictionary) -> Dictionary:
	if not isa.get("ok", false):
		return _bad("ISA не скомпилирована")
	var lines := PackedStringArray()
	var pc := 0
	while pc < bytes.size():
		var ins := _decode(bytes, pc, isa)
		if not ins.ok:
			return ins
		var args := PackedStringArray()
		for i in ins.operands.size():
			args.append(("R%d" if ins.d.args[i] == "r" else "0x%02X") % int(ins.operands[i]))
		lines.append((str(ins.d.name) + " " + ", ".join(args)).strip_edges())
		pc = ins.end
	return {"ok": true, "source": "\n".join(lines)}

func flash(image: Array, isa: Dictionary) -> Dictionary:
	if image.is_empty() or image.size() > 256 or not isa.get("ok", false):
		return _bad("Нужны ISA и 1…256 байт прошивки")
	for byte: Variant in image:
		if not _uint(byte, 255):
			return _bad("В прошивке не байт")
	var ram := []
	ram.resize(256)
	ram.fill(0)
	for i in image.size():
		ram[i] = int(image[i])
	var regs := []
	regs.resize(isa.registers)
	regs.fill(0)
	return {"ok": true, "ram": ram, "regs": regs, "pc": 0, "halted": false, "fault": "", "inputs": {}, "outputs": {}}

# Одна инструкция по явному запросу чипа. Карта I/O принадлежит игроку.
func execute(vm: Dictionary, isa: Dictionary, chip: String) -> bool:
	if not vm.get("ok", false) or vm.halted or not isa.get("ok", false):
		return false
	var pc := int(vm.pc)
	var ins := _decode(vm.ram, pc, isa)
	if not ins.ok:
		vm.fault = ins.error
		vm.halted = true
		return false
	vm.pc = ins.end
	for op: Array in ins.d["do"]:
		var dst := 0
		var values := [0, 0, 0]
		for i in range(1, op.size()):
			var arg := int(op[i])
			var raw := int(ins.operands[arg])
			if i == 1:
				dst = raw
			values[i - 1] = int(vm.regs[raw]) if ins.d.args[arg] == "r" else raw
		var a := int(values[0])
		var b := int(values[1])
		match op[0]:
			"mov": vm.regs[dst] = b
			"add": vm.regs[dst] = (a + b) & 255
			"sub": vm.regs[dst] = (a - b) & 255
			"and": vm.regs[dst] = a & b
			"or": vm.regs[dst] = a | b
			"xor": vm.regs[dst] = a ^ b
			"ld": vm.regs[dst] = int(vm.ram[b])
			"st": vm.ram[a] = b
			"jmp": vm.pc = a
			"jz":
				if a == 0: vm.pc = b
			"jnz":
				if a != 0: vm.pc = b
			"not": vm.regs[dst] = (~b) & 255
			"ldi": vm.regs[dst] = int(vm.ram[(int(values[1]) + int(values[2])) & 255])
			"in": vm.regs[dst] = int(vm.inputs.get(str(b), 0)) & 255
			"out": vm.outputs[str(a)] = b
			"halt":
				vm.halted = true
				break
	DebugHooks.on_instruction.emit(SimClock.now, chip, pc, ins.d.name, vm.regs.duplicate())
	return true
