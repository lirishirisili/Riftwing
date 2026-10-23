class_name RunSettlement
extends RefCounted
## Banks a finished run exactly once, at the moment the run ends.
##
## Rewards used to be granted when the Results screen opened, so killing the app
## between the end banner and Results lost the run. Settlement now runs from the
## run host; Results only presents what was banked. Every outcome is stored on
## the RunStats so a rebuilt Results screen (Hangar -> back) shows the same
## numbers instead of recomputing them as "already claimed".

const _RULES_PATH := "res://resources/progression/reward_rules_default.tres"
const _MAP_PATH := "res://resources/stages/nova_sector_map.tres"


## Scores the run, computes rewards, and grants them (deduped by run id).
## Idempotent: a second call on the same stats is a no-op.
static func settle(stats: RunStats) -> void:
	if stats == null or stats.settled:
		return
	var rules := load(_RULES_PATH) as RewardRulesData
	if rules == null:
		rules = RewardRulesData.new()
	stats.finalize_score(rules)
	var stage := resolve_stage(stats)
	# Daily runs reuse a stage's layout but never count as campaign progress.
	var counts_for_campaign := stage != null and not stats.is_daily
	# First clear is decided BEFORE granting so the bonus is only offered once.
	stats.was_first_clear = stats.victory and counts_for_campaign \
		and not SaveManager.is_stage_cleared(stats.stage_id, stats.difficulty)
	stats.rewards = RewardCalculator.calculate(
		stats, rules, stage if counts_for_campaign else null, stats.was_first_clear)
	stats.was_new_best = stats.score > SaveManager.get_best_score()
	stats.granted = SaveManager.grant_run_rewards(stats.run_id, stats.rewards, stats)
	stats.settled = true


## Map node for the run's stage, or null when played outside the map.
static func resolve_stage(stats: RunStats) -> StageNodeData:
	if stats == null or stats.stage_id == "":
		return null
	var map := load(_MAP_PATH) as StageMapData
	return map.find_by_id(stats.stage_id) if map != null else null
