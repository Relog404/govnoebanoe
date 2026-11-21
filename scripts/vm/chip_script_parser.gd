class_name ChipScriptParser
extends RefCounted
## Рекурсивный парсер ChipScript. На выходе — ChipProgram с AST.
## Язык намеренно простой:
##   var x = 10
##   func update(dt) { if key_down("D") { x = x + 200 * dt } }
##   for i in range(0, 10) { ... }

const RESERVED := [
	"var", "let", "if", "else", "while", "for", "in", "return", "break",
	"continue", "func", "function", "true", "false", "null", "and", "or", "not",
]

var _tokens: Array = []
var _idx := 0
var _error := ""
var _error_line := 0


func parse(source: String) -> ChipProgram:
	var program := ChipProgram.new()
	program.source = source

	var lexer := ChipScriptLexer.new()
	_tokens = lexer.tokenize(source)
	if lexer.error != "":
		program.errors.append({"line": lexer.error_line, "message": lexer.error})
		return program

	_idx = 0
	_error = ""
	_error_line = 0

	while not _check_type("eof"):
		if _check(";"):
			_advance()
			continue
		if _check("func") or _check("function"):
			var fn = _parse_function()
			if fn == null:
				break
			if program.functions.has(fn["name"]):
				_fail(fn["line"], "Функция '%s' уже определена" % fn["name"])
				break
			program.functions[fn["name"]] = fn
			continue
		var stmt = null
		if _check("var") or _check("let"):
			stmt = _parse_var_decl()
		else:
			stmt = _parse_statement()
		if stmt == null:
			break
		program.globals.append(stmt)

	if _error != "":
		program.errors.append({"line": _error_line, "message": _error})
	elif not _check_type("eof"):
		program.errors.append({
			"line": int(_peek()["line"]),
			"message": "Лишний текст: '%s'" % String(_peek()["v"]),
		})
	return program


# ---------------------------------------------------------------------------
# Токены
# ---------------------------------------------------------------------------

func _peek(offset: int = 0) -> Dictionary:
	var i := clampi(_idx + offset, 0, _tokens.size() - 1)
	return _tokens[i]


func _advance() -> Dictionary:
	var t := _peek()
	if _idx < _tokens.size() - 1:
		_idx += 1
	return t


func _check_type(token_type: String) -> bool:
	return String(_peek()["t"]) == token_type


func _check(value: String) -> bool:
	var t := _peek()
	var tt := String(t["t"])
	return (tt == "op" or tt == "id") and String(t["v"]) == value


func _match(value: String) -> bool:
	if _check(value):
		_advance()
		return true
	return false


func _expect(value: String, message: String = "") -> Dictionary:
	if _check(value):
		return _advance()
	var msg := message
	if msg == "":
		msg = "Ожидалось '%s'" % value
	_fail(int(_peek()["line"]), msg)
	return {}


func _fail(line: int, message: String) -> void:
	if _error == "":
		_error = message
		_error_line = line


func _is_reserved(word: String) -> bool:
	return word in RESERVED


# ---------------------------------------------------------------------------
# Функции и блоки
# ---------------------------------------------------------------------------

func _parse_function():
	var line := int(_peek()["line"])
	_advance()  # func
	var name_tok := _peek()
	if _check_type("id") == false or _is_reserved(String(name_tok["v"])):
		_fail(line, "Ожидалось имя функции")
		return null
	_advance()
	var fn_name := String(name_tok["v"])
	if not _expect("(", "Ожидалось '(' после имени функции"):
		return null
	var params: Array[String] = []
	if not _check(")"):
		while true:
			var p := _peek()
			if String(p["t"]) != "id" or _is_reserved(String(p["v"])):
				_fail(int(p["line"]), "Ожидалось имя параметра")
				return null
			_advance()
			if params.has(String(p["v"])):
				_fail(int(p["line"]), "Параметр '%s' повторяется" % p["v"])
				return null
			params.append(String(p["v"]))
			if not _match(","):
				break
	_expect(")", "Ожидалось ')'")
	if _error != "":
		return null
	var body := _parse_block()
	if _error != "":
		return null
	return {"t": "func", "name": fn_name, "params": params, "body": body, "line": line}


func _parse_block() -> Array:
	var stmts: Array = []
	if not _expect("{", "Ожидалось '{'"):
		return stmts
	while not _check("}") and not _check_type("eof"):
		if _match(";"):
			continue
		var s = null
		if _check("var") or _check("let"):
			s = _parse_var_decl()
		else:
			s = _parse_statement()
		if s == null:
			break
		stmts.append(s)
	if _error == "":
		_expect("}", "Ожидалось '}'")
	return stmts


# ---------------------------------------------------------------------------
# Операторы
# ---------------------------------------------------------------------------

func _parse_statement():
	var line := int(_peek()["line"])
	if _check("if"):
		return _parse_if()
	if _check("while"):
		_advance()
		var cond = _expr()
		if cond == null:
			return null
		var body := _parse_block()
		if _error != "":
			return null
		_match(";")
		return {"t": "while", "cond": cond, "body": body, "line": line}
	if _check("for"):
		_advance()
		var name_tok := _peek()
		if String(name_tok["t"]) != "id" or _is_reserved(String(name_tok["v"])):
			_fail(line, "Ожидалось имя переменной после for")
			return null
		_advance()
		if not _expect("in", "Ожидалось 'in': for i in range(0, 10)"):
			return null
		var iter = _expr()
		if iter == null:
			return null
		var fbody := _parse_block()
		if _error != "":
			return null
		_match(";")
		return {"t": "for", "name": String(name_tok["v"]), "iter": iter, "body": fbody, "line": line}
	if _check("return"):
		_advance()
		var value = null
		if not (_check("}") or _check(";") or _check_type("eof")):
			value = _expr()
			if value == null:
				return null
		_match(";")
		return {"t": "return", "expr": value, "line": line}
	if _check("break"):
		_advance()
		_match(";")
		return {"t": "break", "line": line}
	if _check("continue"):
		_advance()
		_match(";")
		return {"t": "continue", "line": line}
	if _check("{"):
		return {"t": "block", "body": _parse_block(), "line": line}
	if _check("func") or _check("function"):
		_fail(line, "Функции объявляются на верхнем уровне, вне других блоков")
		return null
	return _parse_expr_statement()


func _parse_if():
	var line := int(_peek()["line"])
	_advance()
	var cond = _expr()
	if cond == null:
		return null
	var then_body := _parse_block()
	if _error != "":
		return null
	var else_body = null
	if _match("else"):
		if _check("if"):
			var nested = _parse_if()
			if nested == null:
				return null
			else_body = [nested]
		else:
			else_body = _parse_block()
			if _error != "":
				return null
	_match(";")
	return {"t": "if", "cond": cond, "then": then_body, "else": else_body, "line": line}


func _parse_var_decl():
	var line := int(_peek()["line"])
	_advance()  # var / let
	var name_tok := _peek()
	if String(name_tok["t"]) != "id" or _is_reserved(String(name_tok["v"])):
		_fail(line, "Ожидалось имя переменной")
		return null
	_advance()
	var value = {"t": "null", "line": line}
	if _match("="):
		value = _expr()
		if value == null:
			return null
	_match(";")
	return {"t": "var", "name": String(name_tok["v"]), "expr": value, "line": line}


func _parse_expr_statement():
	var line := int(_peek()["line"])
	var expr = _expr()
	if expr == null:
		return null
	var t := _peek()
	if String(t["t"]) == "op" and String(t["v"]) in ["=", "+=", "-=", "*=", "/=", "%="]:
		var op := String(t["v"])
		_advance()
		var rhs = _expr()
		if rhs == null:
			return null
		if not (typeof(expr) == TYPE_DICTIONARY and (expr["t"] == "var" or expr["t"] == "index")):
			_fail(line, "Слева от присваивания должна быть переменная или элемент массива")
			return null
		_match(";")
		return {"t": "assign", "target": expr, "op": op, "expr": rhs, "line": line}
	# x++ / x--
	if String(t["t"]) == "op" and String(t["v"]) in ["++", "--"]:
		var op2 := "+" if String(t["v"]) == "++" else "-"
		_advance()
		if not (expr["t"] == "var" or expr["t"] == "index"):
			_fail(line, "++/-- работают только с переменной")
			return null
		_match(";")
		return {"t": "assign", "target": expr, "op": op2 + "=",
			"expr": {"t": "num", "v": 1.0, "line": line}, "line": line}
	_match(";")
	return {"t": "expr", "expr": expr, "line": line}


# ---------------------------------------------------------------------------
# Выражения
# ---------------------------------------------------------------------------

func _expr():
	return _or()


func _or():
	var node = _and()
	if node == null:
		return null
	while true:
		var t := _peek()
		if String(t["t"]) == "op" and (String(t["v"]) == "||" or String(t["v"]) == "or") \
				or (String(t["t"]) == "id" and String(t["v"]) == "or"):
			var line := int(t["line"])
			_advance()
			var right = _and()
			if right == null:
				return null
			node = {"t": "bin", "op": "or", "l": node, "r": right, "line": line}
		else:
			break
	return node


func _and():
	var node = _equality()
	if node == null:
		return null
	while true:
		var t := _peek()
		if String(t["t"]) == "op" and (String(t["v"]) == "&&" or String(t["v"]) == "and") \
				or (String(t["t"]) == "id" and String(t["v"]) == "and"):
			var line := int(t["line"])
			_advance()
			var right = _equality()
			if right == null:
				return null
			node = {"t": "bin", "op": "and", "l": node, "r": right, "line": line}
		else:
			break
	return node


func _equality():
	var node = _comparison()
	if node == null:
		return null
	while true:
		var t := _peek()
		if String(t["t"]) == "op" and String(t["v"]) in ["==", "!="]:
			var op := String(t["v"])
			var line := int(t["line"])
			_advance()
			var right = _comparison()
			if right == null:
				return null
			node = {"t": "bin", "op": op, "l": node, "r": right, "line": line}
		else:
			break
	return node


func _comparison():
	var node = _term()
	if node == null:
		return null
	while true:
		var t := _peek()
		if String(t["t"]) == "op" and String(t["v"]) in ["<", "<=", ">", ">="]:
			var op := String(t["v"])
			var line := int(t["line"])
			_advance()
			var right = _term()
			if right == null:
				return null
			node = {"t": "bin", "op": op, "l": node, "r": right, "line": line}
		else:
			break
	return node


func _term():
	var node = _factor()
	if node == null:
		return null
	while true:
		var t := _peek()
		if String(t["t"]) == "op" and String(t["v"]) in ["+", "-"]:
			var op := String(t["v"])
			var line := int(t["line"])
			_advance()
			var right = _factor()
			if right == null:
				return null
			node = {"t": "bin", "op": op, "l": node, "r": right, "line": line}
		else:
			break
	return node


func _factor():
	var node = _unary()
	if node == null:
		return null
	while true:
		var t := _peek()
		if String(t["t"]) == "op" and String(t["v"]) in ["*", "/", "%"]:
			var op := String(t["v"])
			var line := int(t["line"])
			_advance()
			var right = _unary()
			if right == null:
				return null
			node = {"t": "bin", "op": op, "l": node, "r": right, "line": line}
		else:
			break
	return node


func _unary():
	var t := _peek()
	if String(t["t"]) == "op" and String(t["v"]) in ["-", "!"]:
		var op := String(t["v"])
		var line := int(t["line"])
		_advance()
		var value = _unary()
		if value == null:
			return null
		return {"t": "un", "op": op, "e": value, "line": line}
	if String(t["t"]) == "id" and String(t["v"]) == "not":
		var line2 := int(t["line"])
		_advance()
		var value2 = _unary()
		if value2 == null:
			return null
		return {"t": "un", "op": "not", "e": value2, "line": line2}
	return _postfix()


func _postfix():
	var node = _primary()
	if node == null:
		return null
	while true:
		if _match("("):
			if node["t"] != "var":
				_fail(int(node["line"]), "Вызов функции возможен только по имени")
				return null
			var args: Array = []
			if not _check(")"):
				while true:
					var arg = _expr()
					if arg == null:
						return null
					args.append(arg)
					if not _match(","):
						break
			if not _expect(")", "Ожидалось ')' в вызове функции"):
				return null
			node = {"t": "call", "name": node["name"], "args": args, "line": node["line"]}
		elif _match("["):
			var index = _expr()
			if index == null:
				return null
			if not _expect("]", "Ожидалось ']'"):
				return null
			node = {"t": "index", "obj": node, "index": index, "line": node["line"]}
		else:
			break
	return node


func _primary():
	var t := _peek()
	var line := int(t["line"])
	match String(t["t"]):
		"num", "str":
			_advance()
			return {"t": String(t["t"]), "v": t["v"], "line": line}
		"id":
			var name := String(t["v"])
			_advance()
			match name:
				"true":
					return {"t": "bool", "v": true, "line": line}
				"false":
					return {"t": "bool", "v": false, "line": line}
				"null":
					return {"t": "null", "line": line}
			if _is_reserved(name):
				_fail(line, "Неожиданное слово '%s'" % name)
				return null
			return {"t": "var", "name": name, "line": line}
		"op":
			if _match("("):
				var inner = _expr()
				if inner == null:
					return null
				if not _expect(")", "Ожидалась ')'"):
					return null
				return inner
			if _match("["):
				var items: Array = []
				if not _check("]"):
					while true:
						var item = _expr()
						if item == null:
							return null
						items.append(item)
						if not _match(","):
							break
						if _check("]"):
							break
				if not _expect("]", "Ожидалась ']'"):
					return null
				return {"t": "array", "items": items, "line": line}
	_fail(line, "Ожидалось выражение" if String(t["t"]) != "eof" else "Неожиданный конец программы")
	return null
