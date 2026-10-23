extends SceneTree
## Builds resources/meta/meta_catalog.tres (missions, achievements, modules +
## the meta balance defaults in MetaCatalogData). Re-run after editing:
## godot --headless --path . --script res://tools/build_meta_content.gd

const ICONS := "res://assets/icons/"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cat := MetaCatalogData.new()

	# --- Daily missions: [id, title, metric, goal, energy, core, activity]
	var daily := [
		["d_kills_150", "Destroy {goal} enemies", "kills", 150, 250, 0, 20],
		["d_kills_400", "Destroy {goal} enemies", "kills", 400, 450, 0, 25],
		["d_elites_3", "Defeat {goal} elites", "elites", 3, 300, 0, 20],
		["d_bosses_2", "Defeat {goal} bosses", "bosses", 2, 350, 0, 20],
		["d_runs_3", "Launch {goal} runs", "runs", 3, 250, 0, 15],
		["d_clears_2", "Clear {goal} stages", "stage_clears", 2, 400, 0, 25],
		["d_chests_2", "Open {goal} Rift Chests", "chests", 2, 300, 0, 20],
		["d_novas_2", "Detonate the Rift Nova {goal} times", "novas", 2, 250, 0, 15],
		["d_combo_40", "Reach a x{goal} kill chain", "combo", 40, 300, 0, 20],
		["d_seconds_600", "Fly for {goal} seconds", "seconds", 600, 300, 0, 20],
		["d_energy_300", "Collect {goal} Rift Energy in runs", "energy", 300, 300, 0, 20],
		["d_evolve_1", "Evolve a weapon", "evolutions", 1, 400, 1, 25],
	]
	var weekly := [
		["w_kills_3000", "Destroy {goal} enemies", "kills", 3000, 1500, 2, 40],
		["w_elites_25", "Defeat {goal} elites", "elites", 25, 1200, 2, 40],
		["w_bosses_15", "Defeat {goal} bosses", "bosses", 15, 1500, 2, 40],
		["w_clears_12", "Clear {goal} stages", "stage_clears", 12, 2000, 3, 50],
		["w_hard_3", "Clear {goal} stages on HARD", "hard_clears", 3, 1500, 3, 50],
		["w_chests_15", "Open {goal} Rift Chests", "chests", 15, 1200, 2, 40],
		["w_evolve_6", "Evolve {goal} weapons", "evolutions", 6, 1500, 3, 50],
		["w_endless_420", "Survive {goal}s in one Endless run", "endless_seconds", 420, 1500, 3, 50],
		["w_combo_120", "Reach a x{goal} kill chain", "combo", 120, 1200, 2, 40],
		["w_runs_20", "Launch {goal} runs", "runs", 20, 1000, 2, 40],
		["w_novas_15", "Detonate the Rift Nova {goal} times", "novas", 15, 1000, 2, 40],
		["w_seconds_3600", "Fly for {goal} seconds", "seconds", 3600, 1200, 2, 40],
	]
	for row in daily:
		cat.missions.append(_mission(row, "daily"))
	for row in weekly:
		cat.missions.append(_mission(row, "weekly"))

	# --- Achievements: [id, title, description, metric, goal, energy, core]
	var achievements := [
		["a_kills_100", "First Blood", "Destroy 100 enemies.", "kills", 100, 300, 1],
		["a_kills_1000", "Swarm Breaker", "Destroy 1,000 enemies.", "kills", 1000, 800, 2],
		["a_kills_10000", "Void Reaper", "Destroy 10,000 enemies.", "kills", 10000, 2500, 5],
		["a_kills_50000", "Extinction Event", "Destroy 50,000 enemies.", "kills", 50000, 6000, 10],
		["a_bosses_1", "Giant Slayer", "Defeat a boss.", "bosses", 1, 300, 1],
		["a_bosses_10", "Titan Hunter", "Defeat 10 bosses.", "bosses", 10, 1000, 2],
		["a_bosses_50", "Colossus Breaker", "Defeat 50 bosses.", "bosses", 50, 3000, 4],
		["a_bosses_200", "Rift Warden", "Defeat 200 bosses.", "bosses", 200, 8000, 8],
		["a_elites_10", "Elite Marked", "Defeat 10 elites.", "elites", 10, 500, 1],
		["a_elites_100", "Elite Hunter", "Defeat 100 elites.", "elites", 100, 2000, 3],
		["a_elites_500", "Gold Standard", "Defeat 500 elites.", "elites", 500, 5000, 6],
		["a_runs_10", "Frequent Flyer", "Launch 10 runs.", "runs", 10, 400, 1],
		["a_runs_100", "Veteran Pilot", "Launch 100 runs.", "runs", 100, 2500, 4],
		["a_wins_5", "Rising Star", "Clear 5 stages.", "victories", 5, 500, 1],
		["a_wins_25", "Ace", "Clear 25 stages.", "victories", 25, 1500, 3],
		["a_wins_100", "Legend of the Rift", "Clear 100 stages.", "victories", 100, 5000, 6],
		["a_chests_10", "Treasure Seeker", "Open 10 Rift Chests.", "chests", 10, 500, 1],
		["a_chests_100", "Hoarder", "Open 100 Rift Chests.", "chests", 100, 3000, 4],
		["a_novas_10", "Supernova", "Detonate the Rift Nova 10 times.", "novas", 10, 500, 1],
		["a_novas_100", "Star Maker", "Detonate the Rift Nova 100 times.", "novas", 100, 3000, 4],
		["a_evolve_1", "Evolution", "Evolve a weapon.", "evolutions", 1, 500, 1],
		["a_evolve_25", "Apex Arsenal", "Evolve 25 weapons.", "evolutions", 25, 3000, 4],
		["a_combo_50", "Chain Reaction", "Reach a x50 kill chain.", "best_combo", 50, 600, 1],
		["a_combo_150", "Unbroken", "Reach a x150 kill chain.", "best_combo", 150, 2500, 3],
		["a_stages_10", "Charted Space", "Clear 10 different stages.", "stages_cleared", 10, 1000, 2],
		["a_stages_30", "Cartographer", "Clear all 30 stages.", "stages_cleared", 30, 6000, 8],
		["a_stars_45", "Star Collector", "Earn 45 stars.", "stars", 45, 1500, 3],
		["a_stars_90", "Perfectionist", "Earn 90 stars.", "stars", 90, 6000, 8],
		["a_sector_1", "Nova Liberated", "Clear the Nova Sector.", "sectors", 1, 1000, 3],
		["a_sector_3", "Rift Sealed", "Clear all three sectors.", "sectors", 3, 8000, 10],
		["a_pilot_10", "Seasoned", "Reach pilot level 10.", "pilot_level", 10, 1500, 2],
		["a_endless_600", "Endurance", "Survive 10 minutes in Endless.", "endless_seconds", 600, 3000, 5],
	]
	for row in achievements:
		var a := AchievementData.new()
		a.id = row[0]
		a.title = row[1]
		a.description = row[2]
		a.metric = row[3]
		a.goal = row[4]
		a.reward_energy = row[5]
		a.reward_core = row[6]
		cat.achievements.append(a)

	# --- Modules: [id, title, stat, values, icon]
	var modules := [
		["overclock_chip", "Overclock Chip", "damage", [0.04, 0.08, 0.13, 0.2], "icon_energy"],
		["hull_plating", "Hull Plating", "hp", [0.06, 0.12, 0.2, 0.3], "icon_health"],
		["targeting_lens", "Targeting Lens", "crit", [0.02, 0.04, 0.07, 0.1], "icon_target"],
		["flux_magnet", "Flux Magnet", "magnet", [0.15, 0.3, 0.5, 0.8], "icon_coin"],
		["neural_uplink", "Neural Uplink", "xp", [0.05, 0.1, 0.16, 0.25], "icon_crystal"],
		["rapid_coupler", "Rapid Coupler", "fire_rate", [0.04, 0.07, 0.11, 0.16], "icon_laser"],
		["ablative_mesh", "Ablative Mesh", "armor", [0.02, 0.04, 0.07, 0.1], "icon_shield"],
		["salvage_drone", "Salvage Drone", "energy_find", [0.06, 0.12, 0.2, 0.3], "icon_drone"],
	]
	for row in modules:
		var m := ModuleData.new()
		m.id = row[0]
		m.title = row[1]
		m.stat = row[2]
		m.values = PackedFloat32Array(row[3])
		m.icon = load(ICONS + String(row[4]) + ".svg")
		cat.modules.append(m)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/meta"))
	var err := ResourceSaver.save(cat, "res://resources/meta/meta_catalog.tres")
	if err != OK:
		printerr("save failed %d" % err)
		quit(1)
		return
	print("BUILD_META_CONTENT_OK missions=%d achievements=%d modules=%d" % [
		cat.missions.size(), cat.achievements.size(), cat.modules.size()])
	quit(0)


func _mission(row: Array, scope: String) -> MissionData:
	var m := MissionData.new()
	m.id = row[0]
	m.title = row[1]
	m.metric = row[2]
	m.goal = row[3]
	m.reward_energy = row[4]
	m.reward_core = row[5]
	m.activity = row[6]
	m.scope = scope
	return m
