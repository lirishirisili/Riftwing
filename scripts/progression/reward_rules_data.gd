class_name RewardRulesData
extends Resource
## Authored weights for run scoring and reward payout.
##
## Every number that turns a run's statistics into a score or a currency payout
## lives here, never in code (docs/04_ARCHITECTURE.md: gameplay configuration
## uses custom Resources). RunStats.score_for and RewardCalculator read these.

## --- Score weights ---------------------------------------------------------
@export var score_per_kill: int = 100
@export var score_per_combo: int = 25
@export var score_per_second: int = 5
@export var score_per_energy: int = 10
@export var score_victory_bonus: int = 5000

## --- Reward payout ---------------------------------------------------------
## Rift Energy (common currency) earned per point of score, plus a flat base and
## a victory multiplier applied to the whole energy payout.
@export var base_rift_energy: int = 50
@export var rift_energy_per_score: float = 0.05
@export var victory_energy_multiplier: float = 1.5

## Rift Core (rare material) is only meaningfully earned by clearing the sector.
@export var rift_core_on_victory: int = 1
@export var rift_core_on_defeat: int = 0
