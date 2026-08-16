class_name RewardCalculator
extends RefCounted
## Pure, testable conversion from a run's statistics into a reward payout.
##
## No side effects, no persistence, no nodes: given the same RunStats and
## RewardRulesData it always returns the same RunRewards. SaveManager is the only
## place that actually banks the result, and it dedupes by run id so a reward is
## granted exactly once (prompts/07_results_screen.md).

## Returns the rewards a run earns. Never mutates its inputs.
##
## `stage` (optional) adds the authored per-stage payout on victory, and
## `is_first_clear` adds the stage's first-clear Rift Core bonus. Both are pure
## inputs; the caller (results screen) decides first-clear state before granting,
## and SaveManager still dedupes the whole payout by run id.
static func calculate(
		stats: RunStats,
		rules: RewardRulesData,
		stage: StageNodeData = null,
		is_first_clear: bool = false) -> RunRewards:
	if stats == null or rules == null:
		return RunRewards.new(0, 0)

	var energy := float(rules.base_rift_energy)
	energy += float(maxi(0, stats.score)) * rules.rift_energy_per_score
	if stats.victory:
		energy *= rules.victory_energy_multiplier

	var core := rules.rift_core_on_victory if stats.victory else rules.rift_core_on_defeat

	if stats.victory and stage != null:
		energy += float(maxi(0, stage.reward_rift_energy))
		core += maxi(0, stage.reward_rift_core)
		if is_first_clear:
			core += maxi(0, stage.first_clear_rift_core)

	# Difficulty payout multiplier (HARD pays more). Neutral (1.0) on NORMAL.
	var mult := maxf(1.0, stats.reward_mult)
	energy *= mult
	core = int(round(float(core) * mult))

	return RunRewards.new(int(round(maxf(0.0, energy))), maxi(0, core))
