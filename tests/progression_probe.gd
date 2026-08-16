extends SceneTree
## End-to-end progression integrity: live score, stage payout, first-clear once,
## stars + per-stage best persistence, and reward dedupe across reload.
## godot --headless --path . --script res://tests/progression_probe.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("progression_probe: start")
	var failed := 0
	failed += _check_live_score()
	failed += _check_stage_payout_and_stars()
	if failed == 0:
		print("PROGRESSION_PROBE_OK")
		quit(0)
	else:
		printerr("PROGRESSION_PROBE_FAILED count=%d" % failed)
		quit(1)


## Live score must strictly increase as stats accumulate and exclude the victory
## bonus (that is only added at finalize on a win).
func _check_live_score() -> int:
	var fails := 0
	var rules: RewardRulesData = load("res://resources/progression/reward_rules_default.tres")
	var stats := RunStats.new()
	var s0 := stats.live_score(rules)
	stats.enemies_destroyed = 10
	var s1 := stats.live_score(rules)
	stats.survival_seconds = 30.0
	var s2 := stats.live_score(rules)
	stats.best_combo = 8
	stats.rift_energy_collected = 50
	var s3 := stats.live_score(rules)
	if not (s0 < s1 and s1 < s2 and s2 < s3):
		printerr("live_score not monotonic: %d %d %d %d" % [s0, s1, s2, s3])
		fails += 1
	# Live score never includes the victory bonus.
	stats.victory = true
	stats.finalize_score(rules)
	if stats.live_score(rules) >= stats.score:
		printerr("live_score should be below finalized victory score (%d vs %d)" % [stats.live_score(rules), stats.score])
		fails += 1
	if fails == 0:
		print("live_score_ok %d<%d<%d<%d final=%d" % [s0, s1, s2, s3, stats.score])
	return fails


func _check_stage_payout_and_stars() -> int:
	var fails := 0
	var sm := root.get_node("SaveManager")
	sm.call("reset")
	var rules: RewardRulesData = load("res://resources/progression/reward_rules_default.tres")
	var map: StageMapData = load("res://resources/stages/nova_sector_map.tres")
	var stage: StageNodeData = map.find_by_id("1-1")

	# --- First clear of 1-1 (3-star run). ---
	var core_before := int(sm.call("get_rift_core"))
	var win := RunStats.new()
	win.run_id = "probe_prog_win_%d" % Time.get_ticks_msec()
	win.victory = true
	win.sector = 1
	win.stage_id = "1-1"
	win.enemies_destroyed = 60
	win.best_combo = 15
	win.survival_seconds = 120.0
	win.rift_energy_collected = 120
	win.hp_ratio_end = 0.9
	win.finalize_score(rules)

	var is_first := not bool(sm.call("is_stage_cleared", "1-1"))
	if not is_first:
		printerr("fresh save should treat 1-1 as first clear")
		fails += 1
	var rewards: RunRewards = RewardCalculator.calculate(win, rules, stage, is_first)
	# Payout must contain the authored stage energy + first-clear core.
	var base_only: RunRewards = RewardCalculator.calculate(win, rules)
	if rewards.rift_energy != base_only.rift_energy + stage.reward_rift_energy:
		printerr("stage energy not applied: %d vs %d+%d" % [rewards.rift_energy, base_only.rift_energy, stage.reward_rift_energy])
		fails += 1
	if rewards.rift_core != base_only.rift_core + stage.first_clear_rift_core:
		printerr("first-clear core not applied: %d vs %d+%d" % [rewards.rift_core, base_only.rift_core, stage.first_clear_rift_core])
		fails += 1

	var granted := bool(sm.call("grant_run_rewards", win.run_id, rewards, win))
	if not granted:
		printerr("first grant should succeed")
		fails += 1
	if int(sm.call("get_rift_core")) != core_before + rewards.rift_core:
		printerr("rift core bank wrong after first clear")
		fails += 1
	if not bool(sm.call("is_stage_cleared", "1-1")):
		printerr("1-1 not marked cleared")
		fails += 1
	if int(sm.call("get_stage_stars", "1-1")) < 3:
		printerr("expected 3 stars, got %d" % int(sm.call("get_stage_stars", "1-1")))
		fails += 1
	if int(sm.call("get_stage_best_score", "1-1")) != win.score:
		printerr("stage best score not recorded")
		fails += 1
	if int(sm.call("get_best_score")) != win.score:
		printerr("global best score not recorded")
		fails += 1

	# --- Replay 1-1 (already cleared) must NOT re-grant the first-clear core. ---
	var core_after_first := int(sm.call("get_rift_core"))
	var replay := RunStats.new()
	replay.run_id = "probe_prog_replay_%d" % Time.get_ticks_msec()
	replay.victory = true
	replay.sector = 1
	replay.stage_id = "1-1"
	replay.enemies_destroyed = 10
	replay.survival_seconds = 40.0
	replay.finalize_score(rules)
	var replay_first := not bool(sm.call("is_stage_cleared", "1-1"))
	if replay_first:
		printerr("replay wrongly treated as first clear")
		fails += 1
	var replay_rewards: RunRewards = RewardCalculator.calculate(replay, rules, stage, replay_first)
	# Replay payout keeps the base per-victory core but never re-adds first-clear.
	var base_replay: RunRewards = RewardCalculator.calculate(replay, rules)
	if replay_rewards.rift_core != base_replay.rift_core:
		printerr("replay wrongly included the first-clear core bonus")
		fails += 1
	sm.call("grant_run_rewards", replay.run_id, replay_rewards, replay)
	if int(sm.call("get_rift_core")) != core_after_first + replay_rewards.rift_core:
		printerr("replay core bank wrong (first-clear likely granted twice)")
		fails += 1

	# Lower-scoring replay must not lower the recorded best score.
	if int(sm.call("get_stage_best_score", "1-1")) != win.score:
		printerr("stage best score regressed on weaker replay")
		fails += 1

	# --- Dedupe: same run id grants nothing. ---
	var core_dedupe := int(sm.call("get_rift_core"))
	var energy_dedupe := int(sm.call("get_rift_energy"))
	var again := bool(sm.call("grant_run_rewards", win.run_id, rewards, win))
	if again:
		printerr("dedupe failed: same run id granted twice")
		fails += 1
	if int(sm.call("get_rift_core")) != core_dedupe or int(sm.call("get_rift_energy")) != energy_dedupe:
		printerr("dedupe changed the bank")
		fails += 1

	# --- Persistence: reload from disk and confirm everything survived. ---
	var energy_persist := int(sm.call("get_rift_energy"))
	var core_persist := int(sm.call("get_rift_core"))
	var best_persist := int(sm.call("get_best_score"))
	var stage_best_persist := int(sm.call("get_stage_best_score", "1-1"))
	var stars_persist := int(sm.call("get_stage_stars", "1-1"))
	sm.call("load_game")
	if int(sm.call("get_rift_energy")) != energy_persist:
		printerr("rift energy not persisted across reload")
		fails += 1
	if int(sm.call("get_rift_core")) != core_persist:
		printerr("rift core not persisted across reload")
		fails += 1
	if int(sm.call("get_best_score")) != best_persist:
		printerr("best score not persisted across reload")
		fails += 1
	if int(sm.call("get_stage_best_score", "1-1")) != stage_best_persist:
		printerr("stage best score not persisted across reload")
		fails += 1
	if int(sm.call("get_stage_stars", "1-1")) != stars_persist:
		printerr("stars not persisted across reload")
		fails += 1
	if not bool(sm.call("is_stage_cleared", "1-1")):
		printerr("clear flag not persisted across reload")
		fails += 1

	if fails == 0:
		print("stage_payout_ok energy=%d core=%d best=%d stageBest=%d stars=%d" % [
			energy_persist, core_persist, best_persist, stage_best_persist, stars_persist])
	return fails
