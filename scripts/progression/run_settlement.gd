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
	if stats.mode == "endless" or stats.mode == "boss_rush":
		stats.rewards.rift_core += maxi(0, stats.bosses_defeated) * rules.rift_core_per_boss
		SaveManager.record_mode_result(stats.mode, stats.score, stats.survival_seconds, stats.bosses_defeated)
	stats.was_new_best = stats.score > SaveManager.get_best_score()
	# Equipped "energy_find" modules boost the Rift Energy payout.
	var find := float(MetaProgress.equipped_bonuses().get("energy_find", 0.0))
	if find > 0.0:
		stats.rewards.rift_energy = int(round(float(stats.rewards.rift_energy) * (1.0 + find)))
	stats.granted = SaveManager.grant_run_rewards(stats.run_id, stats.rewards, stats)
	# Missions, lifetime stats, pilot XP, module drops (once: only on a fresh grant).
	if stats.granted:
		stats.meta_summary = MetaProgress.record_run(stats)
	stats.settled = true


## Map node for the run's stage, or null when played outside the map.
static func resolve_stage(stats: RunStats) -> StageNodeData:
	if stats == null or stats.stage_id == "":
		return null
	return Campaign.find_stage(stats.stage_id)
