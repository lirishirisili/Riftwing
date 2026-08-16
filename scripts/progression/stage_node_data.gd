class_name StageNodeData
extends Resource
## One mission node on the galaxy map.
##
## Display copy, recommended power, reward previews, and map layout live here.
## Unlock / clear / star state is owned by SaveManager — this Resource is never
## mutated at runtime (docs/04_ARCHITECTURE.md).

@export var id: String = ""

## 1-based order in the sector path (drives connections and unlock chain).
@export_range(1, 99) var index: int = 1

## Short node badge shown on the map (e.g. "1-5").
@export var label: String = "1-1"

@export var title: String = "Mission"

## Enemy faction / threat line for the detail panel.
@export var enemy_label: String = "VOID SWARM"

@export_multiline var objective: String = ""

@export var recommended_power: int = 1000

## Preview rewards shown on the map (actual run payout still uses RewardRulesData).
@export var reward_rift_energy: int = 200
@export var reward_rift_core: int = 0
@export var first_clear_rift_core: int = 1

## Position inside the map canvas (logical 1080-wide composition).
@export var map_position: Vector2 = Vector2(200, 200)

## Placeholder planet tint so nodes stay visually distinct.
@export var planet_modulate: Color = Color(0.4, 0.75, 1.0, 1.0)

## Fresh saves unlock these without any clears (prompt: first three for testing).
@export var starts_unlocked: bool = false

## Graded difficulty for this node: multiplies enemy/boss durability on top of the
## selected RunDifficultyData so later stages ramp up even on NORMAL. 1.0 = base.
@export_range(0.5, 3.0, 0.05) var difficulty_scalar: float = 1.0

## Optional per-stage clock/wave/boss authoring. When null the RunController falls
## back to the shared vertical-slice timeline so early stages keep the baseline.
@export var timeline: StageTimelineData

## Star objectives on victory (additive): clear / HP ratio / score. Pure data.
@export_range(0.0, 1.0, 0.05) var stars_hp_ratio_for_2: float = 0.5
@export var stars_score_for_3: int = 4000

## Legacy combo threshold kept for older map resources; unused when HP ratio is set.
@export var stars_combo_for_2: int = 5
