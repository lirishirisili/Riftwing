class_name HexChip
extends PanelContainer
## Compact currency / status chip with neon chrome styling.

@onready var _icon: TextureRect = %Icon
@onready var _value: Label = %Value


func set_icon(tex: Texture2D) -> void:
	if _icon != null:
		_icon.texture = tex


func set_value_text(text: String) -> void:
	if _value != null:
		_value.text = text
