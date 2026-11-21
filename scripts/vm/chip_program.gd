class_name ChipProgram
extends RefCounted
## Скомпилированная программа чипа: глобальные объявления, функции, ошибки.

var source := ""
var globals: Array = []
var functions: Dictionary = {}
var errors: Array[Dictionary] = []


func is_valid() -> bool:
	return errors.is_empty()


func error_text() -> String:
	var parts := PackedStringArray()
	for e in errors:
		parts.append("Строка %d: %s" % [int(e.get("line", 0)), String(e.get("message", "?"))])
	return "\n".join(parts)


func function_names() -> Array[String]:
	var out: Array[String] = []
	for name in functions:
		out.append(String(name))
	out.sort()
	return out
