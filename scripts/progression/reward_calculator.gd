class_name RewardCalculator
extends RefCounted
## Pure, testable conversion from a run's statistics into a reward payout.
##
## No side effects, no persistence, no nodes: given the same RunStats and
## RewardRulesData it always returns the same RunRewards. SaveManager is the only
## place that actually banks the result, and it dedupes by run id so a reward is
## granted exactly once (prompts/07_results_screen.md).

## Returns the rewards a run earns. Never mutates its inputs.
static func calculate(stats: RunStats, rules: RewardRulesData) -> RunRewards:
	if stats == null or rules == null:
		return RunRewards.new(0, 0)

	var energy := float(rules.base_rift_energy)
	energy += float(maxi(0, stats.score)) * rules.rift_energy_per_score
	if stats.victory:
		energy *= rules.victory_energy_multiplier

	var core := rules.rift_core_on_victory if stats.victory else rules.rift_core_on_defeat

	return RunRewards.new(int(round(maxf(0.0, energy))), maxi(0, core))
