class_name ComponentDef
extends Resource

# Пользовательское описание, общее для любого количества экземпляров.
@export var display_name := ""
@export var ports: Dictionary = {}
@export var parameters: Dictionary = {}
@export var isa_path := ""
@export var io_map: Dictionary = {}
@export_enum("1-bit", "RGB565", "Palette") var framebuffer_format: String = "1-bit"
@export var icon: Texture2D
