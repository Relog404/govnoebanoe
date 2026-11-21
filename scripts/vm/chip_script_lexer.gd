class_name ChipScriptLexer
extends RefCounted
## Лексер ChipScript — простого встроенного языка для программ чипа.
## Числа, строки, массивы, комментарии # и //, /* ... */.

var error := ""
var error_line := 0

var _src := ""
var _pos := 0
var _line := 1


func tokenize(src: String) -> Array:
	_src = src
	_pos = 0
	_line = 1
	error = ""
	var tokens: Array = []

	while _pos < _src.length():
		var c := _src[_pos]
		if c == "\n":
			_line += 1
			_pos += 1
			continue
		if c == " " or c == "\t" or c == "\r":
			_pos += 1
			continue
		if c == "#":
			_skip_line()
			continue
		if c == "/" and _peek(1) == "/":
			_skip_line()
			continue
		if c == "/" and _peek(1) == "*":
			_skip_block_comment()
			if error != "":
				break
			continue
		if _is_digit(c):
			tokens.append(_read_number())
			continue
		if c == "\"":
			tokens.append(_read_string())
			if error != "":
				break
			continue
		if _is_ident_start(c):
			tokens.append(_read_ident())
			continue
		var op := _read_operator()
		if op == "":
			error = "Неизвестный символ '%s'" % c
			error_line = _line
			break
		tokens.append({"t": "op", "v": op, "line": _line})

	tokens.append({"t": "eof", "v": "", "line": _line})
	error_line = _line if error != "" else error_line
	return tokens


func _peek(offset: int) -> String:
	var i := _pos + offset
	if i < 0 or i >= _src.length():
		return ""
	return _src[i]


func _skip_line() -> void:
	while _pos < _src.length() and _src[_pos] != "\n":
		_pos += 1


func _skip_block_comment() -> void:
	_pos += 2
	while _pos < _src.length():
		if _src[_pos] == "*" and _peek(1) == "/":
			_pos += 2
			return
		if _src[_pos] == "\n":
			_line += 1
		_pos += 1
	error = "Незакрытый комментарий /* ... */"
	error_line = _line


func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


func _is_ident_start(c: String) -> bool:
	if c == "_":
		return true
	# Буквы любого алфавита (пригодится для имён переменных на русском).
	return c.to_lower() != c.to_upper()


func _is_ident_char(c: String) -> bool:
	return _is_ident_start(c) or _is_digit(c)


func _read_number() -> Dictionary:
	var start := _pos
	var line := _line
	while _pos < _src.length() and _is_digit(_src[_pos]):
		_pos += 1
	if _pos < _src.length() and _src[_pos] == "." and _is_digit(_peek(1)):
		_pos += 1
		while _pos < _src.length() and _is_digit(_src[_pos]):
			_pos += 1
	var text := _src.substr(start, _pos - start)
	return {"t": "num", "v": text.to_float(), "line": line}


func _read_string() -> Dictionary:
	var line := _line
	_pos += 1
	var out := ""
	while _pos < _src.length():
		var c := _src[_pos]
		if c == "\\":
			var n := _peek(1)
			_pos += 2
			match n:
				"n":
					out += "\n"
				"t":
					out += "\t"
				"r":
					out += "\r"
				"\"":
					out += "\""
				"\\":
					out += "\\"
				_:
					out += n
			continue
		if c == "\"":
			_pos += 1
			return {"t": "str", "v": out, "line": line}
		if c == "\n":
			error = "Незакрытая строка"
			error_line = line
			return {"t": "str", "v": out, "line": line}
		out += c
		_pos += 1
	error = "Незакрытая строка"
	error_line = line
	return {"t": "str", "v": out, "line": line}


func _read_ident() -> Dictionary:
	var start := _pos
	var line := _line
	while _pos < _src.length() and _is_ident_char(_src[_pos]):
		_pos += 1
	return {"t": "id", "v": _src.substr(start, _pos - start), "line": line}


func _read_operator() -> String:
	var two := _src.substr(_pos, 2)
	if two in ["==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "&&", "||", "++", "--"]:
		_pos += 2
		return two
	var one := _src[_pos]
	if one in "+-*/%<>=!(){}[],;:":
		_pos += 1
		return one
	return ""
