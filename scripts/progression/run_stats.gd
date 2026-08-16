class_name RunStats
extends RefCounted
## A snapshot of a single run's outcome and the numbers it earned.
##
## Statistics are accumulated live during play by the run host (survival time,
## enemies destroyed, best combo, rift energy) and never fabricated on the
## results screen. `score_for` is a pure static function so scoring is testable
## in isolation and produces the same value from the same inputs
## (docs/04_ARCHITECTURE.md: run statistics live in save data; behavior here,
## balance in RewardRulesData).

## Unique id for this run instance, used to grant rewards exactly once.
var run_id: String = ""
## True when the boss was defeated; false on player death / abort.
var victory: bool = false
## 1-based sector index the run was played in.
var sector: int = 1
## Galaxy-map stage id (e.g. "1-5"). Empty when launched outside the map.
var stage_id: String = ""
## Difficulty id this run was played on ("normal" / "hard"). Keys per-difficulty save.
var difficulty: String = "normal"
## Payout multiplier from the difficulty profile (applied by RewardCalculator).
var reward_mult: float = 1.0
## 3-star score threshold multiplier from the difficulty profile.
var star_score_mult: float = 1.0

## Daily Challenge run flags. When is_daily is true and the run is a victory,
## SaveManager grants daily_reward_core Rift Cores once per daily_date.
var is_daily: bool = false
var daily_date: String = ""
var daily_reward_core: int = 0

## Live-accumulated statistics.
var enemies_destroyed: int = 0
var best_combo: int = 0
var survival_seconds: float = 0.0
var rift_energy_collected: int = 0
## Remaining HP ratio at run end (0..1). Used for stage star objective 2.
var hp_ratio_end: float = 0.0

## Derived at finalize from the fields above (cached so the results screen and
## the reward calculator read one consistent value).
var score: int = 0


## Pure scoring function. Deterministic: identical inputs yield identical output.
## Weights are supplied by the caller (from RewardRulesData) so no balance number
## is hard-coded here.
static func score_for(
		enemies: int,
		combo: int,
		seconds: float,
		energy: int,
		is_victory: bool,
		per_kill: int,
		per_combo: int,
		per_second: int,
		per_energy: int,
		victory_bonus: int) -> int:
	var total := 0
	total += maxi(0, enemies) * per_kill
	total += maxi(0, combo) * per_combo
	total += int(maxf(0.0, seconds)) * per_second
	total += maxi(0, energy) * per_energy
	if is_victory:
		total += victory_bonus
	return total


## Live in-run score (victory bonus intentionally excluded) using the same
## weights as `finalize_score`. Lets the HUD show one consistent value without
## duplicating the scoring formula.
func live_score(rules: RewardRulesData) -> int:
	if rules == null:
		return 0
	return score_for(
		enemies_destroyed,
		best_combo,
		survival_seconds,
		rift_energy_collected,
		false,
		rules.score_per_kill,
		rules.score_per_combo,
		rules.score_per_second,
		rules.score_per_energy,
		rules.score_victory_bonus)


## Fills `score` from the current statistics using the given rules.
func finalize_score(rules: RewardRulesData) -> void:
	score = score_for(
		enemies_destroyed,
		best_combo,
		survival_seconds,
		rift_energy_collected,
		victory,
		rules.score_per_kill,
		rules.score_per_combo,
		rules.score_per_second,
		rules.score_per_energy,
		rules.score_victory_bonus)


## A plain dictionary for the results screen / debug readout.
func to_dictionary() -> Dictionary:
	return {
		"run_id": run_id,
		"victory": victory,
		"sector": sector,
		"stage_id": stage_id,
		"difficulty": difficulty,
		"enemies_destroyed": enemies_destroyed,
		"best_combo": best_combo,
		"survival_seconds": survival_seconds,
		"rift_energy_collected": rift_energy_collected,
		"hp_ratio_end": hp_ratio_end,
		"score": score,
	}
