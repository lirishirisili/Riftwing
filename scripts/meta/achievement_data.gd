class_name AchievementData
extends Resource
## A lifetime achievement. Progress reads a lifetime counter (save `lifetime`)
## or a derived value: stages_cleared, stars, sectors, pilot_level,
## endless_seconds, boss_rush_bosses.

@export var id: String = ""
@export var title: String = "Achievement"
@export var description: String = ""
@export var metric: String = "kills"
@export_range(1, 1000000) var goal: int = 100
@export_range(0, 100000) var reward_energy: int = 0
@export_range(0, 100) var reward_core: int = 1
