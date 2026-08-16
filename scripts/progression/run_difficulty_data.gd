class_name RunDifficultyData
extends Resource
## Data-driven difficulty profile for a run.
##
## Difficulty raises pressure through enemy/boss durability, spawn density, and
## earlier boss timing — never by removing telegraphs or dealing unfair hits
## (docs/02_GAMEPLAY_SPEC.md). RunController reads these and applies them at run
## start via runtime scaling (no shared EnemyData/BossData is mutated).

## Stable id used for save keys and payloads ("normal" / "hard").
@export var id: String = "normal"

## Human-readable label for HUD / results.
@export var display_name: String = "NORMAL"

## Multiplies every enemy's hit points.
@export_range(0.5, 4.0, 0.05) var enemy_hp_mult: float = 1.0

## Multiplies enemy contact damage (kept modest so danger stays fair).
@export_range(0.5, 3.0, 0.05) var enemy_contact_damage_mult: float = 1.0

## Extra enemies added to each wave event (density pressure).
@export_range(0, 6) var enemy_count_add: int = 0

## Multiplies boss hit points.
@export_range(0.5, 4.0, 0.05) var boss_hp_mult: float = 1.0

## Multiplies the final energy + core payout for the run.
@export_range(1.0, 4.0, 0.05) var reward_mult: float = 1.0

## Scales the boss/mini-boss arrival clock (<1 = bosses come sooner).
@export_range(0.4, 1.0, 0.01) var timing_scale: float = 1.0

## Multiplies the stage's 3-star score threshold (harder to master).
@export_range(1.0, 3.0, 0.05) var star_score_mult: float = 1.0
