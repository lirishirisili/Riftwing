class_name RunRewards
extends RefCounted
## The permanent resources a completed run grants.
##
## v1 uses at most two currencies (docs/00_PRODUCT_VISION.md): Rift Energy is the
## common currency, Rift Core is the rare progression material. This is a plain
## value object produced by RewardCalculator and consumed by SaveManager; it
## holds no behavior of its own.

var rift_energy: int = 0
var rift_core: int = 0


func _init(energy: int = 0, core: int = 0) -> void:
	rift_energy = energy
	rift_core = core


func is_empty() -> bool:
	return rift_energy <= 0 and rift_core <= 0


func to_dictionary() -> Dictionary:
	return {"rift_energy": rift_energy, "rift_core": rift_core}
