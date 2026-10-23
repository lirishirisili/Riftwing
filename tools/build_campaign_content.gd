extends SceneTree
## Builds the 3-sector campaign content as Resources (reproducible source of
## truth for the campaign pass). Re-run after changing any number here:
## godot --headless --path . --script res://tools/build_campaign_content.gd
##
## Writes: new bosses (+ inline patterns), hostile projectiles, spawn profiles,
## stage timelines, the Ember / Abyss sector maps, Nova 1-9 / 1-10, and
## resources/stages/campaign.tres. Existing Nova stages 1-1..1-8 keep their ids,
## numbers, and timelines (save compatibility).

const BOSS_DIR := "res://resources/bosses/"
const STAGE_DIR := "res://resources/stages/"
const SPAWN_DIR := "res://resources/spawning/"
const WEAPON_DIR := "res://resources/weapons/"

## Map node layout shared by every sector (zig-zag down the canvas).
const POSITIONS := [
	Vector2(200, 100), Vector2(520, 220), Vector2(220, 360), Vector2(540, 500), Vector2(240, 640),
	Vector2(560, 780), Vector2(260, 920), Vector2(500, 1060), Vector2(240, 1200), Vector2(520, 1340),
]

var _fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var radial: ProjectileData = load(WEAPON_DIR + "boss_radial_projectile.tres")
	var orb := _projectile("enemy_orb_homing", 330.0, 5.0, 10.0, 20.0, Color(1, 0.4, 0.9), 2.2, 2.4)
	var wall := _projectile("enemy_wall_projectile", 380.0, 6.5, 10.0, 18.0, Color(1, 0.35, 0.3))

	var wisp: BossData = load(BOSS_DIR + "void_wisp.tres")
	var titan: BossData = load(BOSS_DIR + "void_titan.tres")
	var lancer: EnemyData = load("res://resources/enemies/lancer.tres")
	var swarmling: EnemyData = load("res://resources/enemies/swarmling.tres")
	var spawn: EnemyData = load("res://resources/enemies/void_spawn.tres")

	# --- Patterns (inline sub-resources of each boss) -----------------------------
	var P := {}
	P.spiral3 = _pat(3, "Ember Spiral", 1.0, 3.0, 0.9, {spiral_arms = 3, spiral_rate = 6.0, spiral_turn_degrees = 9.0, radial_projectile = radial})
	P.spiral2 = _pat(3, "Twin Spiral", 1.0, 2.4, 0.9, {spiral_arms = 2, spiral_rate = 7.0, spiral_turn_degrees = 13.0, radial_projectile = radial})
	P.spiral4 = _pat(3, "Inferno Spiral", 0.9, 3.0, 0.8, {spiral_arms = 4, spiral_rate = 9.0, spiral_turn_degrees = 12.0, radial_projectile = radial})
	P.spiral5 = _pat(3, "Abyss Bloom", 0.9, 3.0, 0.8, {spiral_arms = 5, spiral_rate = 8.0, spiral_turn_degrees = -10.0, radial_projectile = radial})
	P.volley = _pat(4, "Fang Volley", 0.9, 2.2, 0.8, {volley_count = 4, volley_bullets = 5, volley_spread_degrees = 44.0, radial_projectile = radial})
	P.volley_dense = _pat(4, "Fang Storm", 0.8, 2.4, 0.7, {volley_count = 6, volley_bullets = 7, volley_spread_degrees = 60.0, radial_projectile = radial})
	P.walls = _pat(5, "Firewall", 1.1, 3.0, 1.0, {wall_count = 3, wall_gap_width = 240.0, wall_spacing = 72.0, falling_projectile = wall})
	P.walls_hard = _pat(5, "Crushing Walls", 1.0, 3.2, 0.9, {wall_count = 4, wall_gap_width = 210.0, wall_spacing = 68.0, falling_projectile = wall})
	P.orbs6 = _pat(6, "Seeker Orbs", 1.0, 1.0, 1.4, {orb_count = 6, falling_projectile = orb})
	P.orbs8 = _pat(6, "Seeker Swarm", 1.0, 1.0, 1.3, {orb_count = 8, falling_projectile = orb})
	P.rain4 = _pat(7, "Meteor Rain", 1.2, 2.4, 0.8, {rain_columns = 4, rain_bullets_per_column = 6, falling_projectile = wall})
	P.rain6 = _pat(7, "Starfall", 1.1, 2.6, 0.8, {rain_columns = 6, rain_bullets_per_column = 6, falling_projectile = wall})
	P.radial = _pat(0, "Nova Ring", 1.0, 1.8, 0.9, {radial_bullets = 24, radial_gaps = 2, radial_gap_slots = 3, radial_rings = 2, radial_spin_degrees = 9.0, radial_projectile = radial})
	P.radial_hard = _pat(0, "Void Corona", 1.0, 2.0, 0.8, {radial_bullets = 32, radial_gaps = 3, radial_gap_slots = 3, radial_rings = 3, radial_spin_degrees = 7.0, radial_projectile = radial})
	P.laser = _pat(1, "Solar Lance", 1.3, 2.4, 0.9, {laser_sweep_degrees = 140.0, laser_half_width = 26.0, laser_damage = 20.0})
	P.laser_return = _pat(1, "Abyss Lance", 1.2, 3.0, 0.9, {laser_sweep_degrees = 150.0, laser_half_width = 28.0, laser_damage = 22.0, laser_return_sweep = true})
	P.summon_lancers = _pat(2, "Lancer Brood", 1.0, 2.4, 1.0, {summon_enemy = lancer, summon_waves = 2, summon_per_wave = 3, summon_spacing = 200.0})
	P.summon_swarm = _pat(2, "Swarm Call", 1.0, 2.4, 1.0, {summon_enemy = swarmling, summon_waves = 2, summon_per_wave = 5, summon_spacing = 140.0})
	P.summon_spawn = _pat(2, "Spawn Call", 1.0, 2.0, 1.0, {summon_enemy = spawn, summon_waves = 2, summon_per_wave = 4, summon_spacing = 150.0})

	# --- Bosses ---------------------------------------------------------------------
	var ascended := _boss("void_titan_ascended", "TITAN ASCENDED", 2600.0, titan.sprite, titan.sprite_scale, 190.0, 24,
		titan.phase1_patterns, titan.phase2_patterns, [P.spiral4, P.volley_dense, P.laser_return],
		0.45, 0.2, BossData.Visual.SPRITE, Color(1.1, 0.9, 1.25), 110.0, 0.22)
	var warden := _boss("cinder_warden", "CINDER WARDEN", 650.0, wisp.sprite, wisp.sprite_scale, 140.0, 12,
		[P.volley, P.radial], [P.walls, P.spiral2], [],
		0.45, 0.0, BossData.Visual.SPRITE, Color(1.35, 0.62, 0.38), 160.0, 0.3)
	var hydra := _boss("ember_hydra", "EMBER HYDRA", 3000.0, titan.sprite, 0.62, 180.0, 24,
		[P.spiral3, P.volley, P.summon_lancers], [P.rain4, P.radial, P.laser], [P.spiral4, P.walls_hard, P.volley_dense],
		0.6, 0.25, BossData.Visual.HYDRA, Color(1.4, 0.58, 0.32), 90.0, 0.2)
	var sentinel := _boss("abyss_sentinel", "ABYSS SENTINEL", 900.0, wisp.sprite, wisp.sprite_scale, 140.0, 12,
		[P.orbs6, P.radial], [P.laser_return, P.orbs8], [],
		0.45, 0.0, BossData.Visual.SPRITE, Color(0.5, 1.2, 1.25), 200.0, 0.35)
	var leviathan := _boss("rift_leviathan", "RIFT LEVIATHAN", 3800.0, wisp.sprite, 0.42, 120.0, 24,
		[P.rain4, P.spiral2], [P.walls, P.orbs8, P.summon_swarm], [P.spiral5, P.laser_return, P.volley_dense],
		0.6, 0.25, BossData.Visual.LEVIATHAN, Color(0.45, 1.15, 1.05), 340.0, 0.18)
	var overmind := _boss("abyss_overmind", "ABYSS OVERMIND", 5000.0, null, 0.5, 170.0, 30,
		[P.radial_hard, P.orbs8], [P.spiral3, P.walls, P.laser], [P.rain6, P.spiral5, P.volley_dense, P.summon_swarm],
		0.65, 0.3, BossData.Visual.OVERMIND, Color(0.55, 1.0, 1.0), 60.0, 0.15)

	# --- Spawn profiles -------------------------------------------------------------------
	var e := func(id: String) -> EnemyData: return load("res://resources/enemies/%s.tres" % id)
	var nova_late: SpawnProfileData = load(SPAWN_DIR + "nova_late.tres")
	var ember_early := _profile("ember_early", [e.call("weaver"), e.call("swarmling"), e.call("lancer"), e.call("striker"), e.call("shooter"), e.call("spinner")],
		[2.0, 2.0, 1.6, 1.4, 1.0, 0.6], 1.6, 3.4, 80.0, 18, 0.06, 0.15)
	var ember_late := _profile("ember_late", [e.call("swarmling"), e.call("lancer"), e.call("striker"), e.call("spinner"), e.call("sniper"), e.call("tank"), e.call("carrier")],
		[1.6, 1.6, 1.5, 1.2, 1.0, 0.7, 0.5], 2.2, 4.6, 90.0, 22, 0.1, 0.2)
	var abyss_early := _profile("abyss_early", [e.call("weaver"), e.call("sniper"), e.call("bulwark"), e.call("swarmling"), e.call("spinner"), e.call("lancer")],
		[2.0, 1.4, 1.0, 1.6, 1.0, 1.2], 2.2, 4.4, 90.0, 22, 0.1, 0.2)
	var abyss_late := _profile("abyss_late", [e.call("weaver"), e.call("sniper"), e.call("bulwark"), e.call("carrier"), e.call("spinner"), e.call("striker"), e.call("lancer")],
		[1.6, 1.4, 1.1, 0.8, 1.2, 1.2, 1.2], 2.8, 5.2, 90.0, 26, 0.12, 0.24)
	var endless_enemies: Array[EnemyData] = []
	for id in ["scout", "weaver", "swarmling", "diver", "shooter", "lancer", "striker", "sniper", "splitter", "tank", "spinner", "bulwark", "carrier"]:
		endless_enemies.append(e.call(id))
	_profile("endless", endless_enemies, [2.5, 2.0, 2.0, 1.5, 1.5, 1.3, 1.2, 1.0, 1.0, 0.8, 0.8, 0.6, 0.4],
		1.0, 7.0, 420.0, 30, 0.03, 0.3)

	# --- Timelines ------------------------------------------------------------------------
	var early_wave: WaveData = load("res://resources/waves/slice_wave_early.tres")
	var mid_wave: WaveData = load("res://resources/waves/slice_wave_mid.tres")
	var tank_line: WaveData = load("res://resources/waves/nova_wave_tank_line.tres")
	var diver_split: WaveData = load("res://resources/waves/nova_wave_diver_split.tres")
	var nova_finale := _timeline("nova_finale_timeline", "Nova Sector Finale", diver_split, tank_line, wisp, ascended, nova_late, nova_late, 50.0, 130.0)
	var ember_early_tl := _timeline("ember_early_timeline", "Ember Nebula Ignition", early_wave, mid_wave, warden, hydra, ember_early, ember_early, 55.0, 140.0)
	var ember_late_tl := _timeline("ember_late_timeline", "Ember Nebula Inferno", diver_split, tank_line, warden, hydra, ember_early, ember_late, 50.0, 130.0)
	var abyss_early_tl := _timeline("abyss_early_timeline", "Abyss Rift Descent", early_wave, mid_wave, sentinel, leviathan, abyss_early, abyss_early, 55.0, 140.0)
	var abyss_mid_tl := _timeline("abyss_mid_timeline", "Abyss Rift Depths", diver_split, tank_line, sentinel, leviathan, abyss_early, abyss_late, 50.0, 130.0)
	var abyss_final_tl := _timeline("abyss_finale_timeline", "Abyss Rift Heart", diver_split, tank_line, sentinel, overmind, abyss_late, abyss_late, 50.0, 125.0)

	# --- Sectors ----------------------------------------------------------------------------
	var nova: StageMapData = load(STAGE_DIR + "nova_sector_map.tres")
	nova.sector_index = 1
	nova.run_music = "run"
	nova.boss_music = "boss"
	nova.map_height = 1480.0
	if nova.find_by_id("1-9") == null:
		nova.stages.append(_stage("1-9", 9, "SHATTERED HALO", "VOID ELITES", "Break through the shattered halo around the Titan's throne.",
			4400, 560, 1, 2, Color(0.6, 0.45, 1), 1.7, 7500, nova_finale))
		nova.stages.append(_stage("1-10", 10, "TITAN THRONE", "TITAN ASCENDED", "Topple the ascended Void Titan and open the Ember route.",
			4800, 620, 1, 3, Color(1, 0.35, 0.6), 1.8, 8000, nova_finale))
	_save(nova, STAGE_DIR + "nova_sector_map.tres")

	var ember := StageMapData.new()
	ember.sector_id = "ember"
	ember.sector_code = "02"
	ember.sector_name = "EMBER NEBULA"
	ember.sector_index = 2
	ember.background_tint = Color(1.0, 0.84, 0.78)
	ember.nebula_modulate = Color(1.45, 0.62, 0.38)
	ember.run_music = "run_ember"
	ember.boss_music = "boss_ember"
	ember.map_height = 1480.0
	var ember_titles := ["CINDER GATE", "FLARE DRIFT", "MAGMA REEF", "SOLAR FORGE", "ASH CATHEDRAL",
		"BURNING VEIL", "PYRE ARRAY", "CRUCIBLE", "EMBER CROWN", "HYDRA NEST"]
	var ember_threats := ["EMBER SWARM", "LANCER PACKS", "STRIKER WINGS", "CINDER WARDEN", "SPINNERS",
		"EMBER ELITES", "CARRIER FLEET", "SNIPER NEST", "EMBER HYDRA", "EMBER HYDRA"]
	var ember_colors := [Color(1, 0.5, 0.25), Color(1, 0.7, 0.3), Color(0.95, 0.3, 0.2), Color(1, 0.85, 0.35), Color(0.8, 0.4, 0.3),
		Color(1, 0.45, 0.5), Color(1, 0.6, 0.2), Color(0.9, 0.25, 0.3), Color(1, 0.75, 0.4), Color(1, 0.4, 0.2)]
	for i in 10:
		var n := i + 1
		var tl := ember_early_tl if n <= 5 else ember_late_tl
		var st := _stage("2-%d" % n, n, ember_titles[i], ember_threats[i], "Push through the Ember Nebula: %s." % ember_titles[i].capitalize(),
			int(lerpf(5200, 8400, i / 9.0)), int(lerpf(680, 980, i / 9.0)), 1 if n < 10 else 2, 2 if n < 10 else 3,
			ember_colors[i], snappedf(lerpf(1.9, 2.75, i / 9.0), 0.05), int(lerpf(8500, 12500, i / 9.0)), tl)
		if n == 1:
			st.requires_stage_id = "1-10"
		ember.stages.append(st)
	_save(ember, STAGE_DIR + "ember_sector_map.tres")

	var abyss := StageMapData.new()
	abyss.sector_id = "abyss"
	abyss.sector_code = "03"
	abyss.sector_name = "ABYSS RIFT"
	abyss.sector_index = 3
	abyss.background_tint = Color(0.78, 0.95, 1.0)
	abyss.nebula_modulate = Color(0.4, 1.25, 1.1)
	abyss.run_music = "run_abyss"
	abyss.boss_music = "boss_abyss"
	abyss.map_height = 1480.0
	var abyss_titles := ["DROWNED LIGHT", "SILENT TRENCH", "HOLLOW REACH", "LEVIATHAN WAKE", "GRAVITY WELL",
		"STATIC ABYSS", "DEEP LATTICE", "OVERMIND GAZE", "EVENT HORIZON", "RIFT HEART"]
	var abyss_threats := ["WEAVER SHOALS", "SNIPER LINES", "BULWARKS", "RIFT LEVIATHAN", "SPINNER FIELDS",
		"CARRIER FLEET", "ABYSS ELITES", "ABYSS OVERMIND", "ABYSS OVERMIND", "ABYSS OVERMIND"]
	var abyss_colors := [Color(0.3, 0.9, 1), Color(0.25, 0.6, 0.9), Color(0.4, 1, 0.8), Color(0.2, 0.75, 0.75), Color(0.5, 0.6, 1),
		Color(0.3, 1, 0.95), Color(0.45, 0.45, 1), Color(0.7, 0.4, 1), Color(0.2, 0.95, 0.7), Color(0.9, 0.3, 0.9)]
	for i in 10:
		var n := i + 1
		var tl := abyss_early_tl if n <= 4 else (abyss_mid_tl if n <= 7 else abyss_final_tl)
		var st := _stage("3-%d" % n, n, abyss_titles[i], abyss_threats[i], "Descend the Abyss Rift: %s." % abyss_titles[i].capitalize(),
			int(lerpf(9000, 14000, i / 9.0)), int(lerpf(1040, 1480, i / 9.0)), 2 if n < 10 else 3, 3 if n < 10 else 5,
			abyss_colors[i], snappedf(lerpf(2.85, 3.8, i / 9.0), 0.05), int(lerpf(13000, 18000, i / 9.0)), tl)
		if n == 1:
			st.requires_stage_id = "2-10"
		abyss.stages.append(st)
	_save(abyss, STAGE_DIR + "abyss_sector_map.tres")

	var campaign := CampaignData.new()
	campaign.sectors = [load(STAGE_DIR + "nova_sector_map.tres"), load(STAGE_DIR + "ember_sector_map.tres"), load(STAGE_DIR + "abyss_sector_map.tres")]
	_save(campaign, STAGE_DIR + "campaign.tres")

	if _fails == 0:
		print("BUILD_CAMPAIGN_CONTENT_OK")
		quit(0)
	else:
		printerr("BUILD_CAMPAIGN_CONTENT_FAILED %d" % _fails)
		quit(1)


func _projectile(name: String, speed: float, lifetime: float, damage: float, radius: float, color: Color,
		homing: float = 0.0, homing_duration: float = 0.0) -> ProjectileData:
	var p := ProjectileData.new()
	p.speed = speed
	p.lifetime = lifetime
	p.damage = damage
	p.radius = radius
	p.length = radius
	p.color = color
	p.homing_turn_rate = homing
	p.homing_duration = homing_duration
	var path := WEAPON_DIR + name + ".tres"
	_save(p, path)
	return load(path)


func _pat(kind: int, title: String, telegraph: float, active: float, recover: float, fields: Dictionary) -> BossPatternData:
	var p := BossPatternData.new()
	p.kind = kind
	p.display_name = title
	p.telegraph_seconds = telegraph
	p.active_seconds = active
	p.recover_seconds = recover
	for key in fields:
		p.set(key, fields[key])
	return p


func _boss(id: String, title: String, hp: float, sprite: Texture2D, sprite_scale: float, hit_radius: float, segments: int,
		p1: Array, p2: Array, p3: Array, phase2: float, phase3: float, visual: int, tint: Color,
		sway: float, sway_speed: float) -> BossData:
	var b := BossData.new()
	b.display_name = title
	b.max_health = hp
	b.sprite = sprite
	b.sprite_scale = sprite_scale
	b.hit_radius = hit_radius
	b.contact_damage = 24.0
	b.health_segments = segments
	b.warning_seconds = 2.2
	b.entry_seconds = 1.6
	b.hold_ratio = Vector2(0.5, 0.24)
	b.phase2_threshold = phase2
	b.phase3_threshold = phase3
	b.phase1_patterns.assign(p1)
	b.phase2_patterns.assign(p2)
	b.phase3_patterns.assign(p3)
	b.visual = visual
	b.tint = tint
	b.sway_amplitude = sway
	b.sway_speed = sway_speed
	b.loot_pickups = 30
	var path := BOSS_DIR + id + ".tres"
	_save(b, path)
	return load(path)


func _profile(id: String, enemies: Array, weights: Array, b0: float, b1: float, ramp: float, max_alive: int,
		elite0: float, elite1: float) -> SpawnProfileData:
	var p := SpawnProfileData.new()
	p.enemies.assign(enemies)
	p.weights = PackedFloat32Array(weights)
	p.budget_per_second_start = b0
	p.budget_per_second_end = b1
	p.ramp_seconds = ramp
	p.max_alive = max_alive
	p.elite_chance_start = elite0
	p.elite_chance_end = elite1
	var path := SPAWN_DIR + id + ".tres"
	_save(p, path)
	return load(path)


func _timeline(id: String, title: String, early: WaveData, mid: WaveData, mini: BossData, final: BossData,
		early_amb: SpawnProfileData, mid_amb: SpawnProfileData, mini_at: float, boss_at: float) -> StageTimelineData:
	var t := StageTimelineData.new()
	t.display_name = title
	t.early_wave = early
	t.mid_wave = mid
	t.mini_boss = mini
	t.final_boss = final
	t.early_ambient = early_amb
	t.mid_ambient = mid_amb
	t.mini_boss_at = mini_at
	t.boss_warning_at = boss_at
	t.guaranteed_level_up_at = 14.0
	t.guaranteed_level_up_xp = 10
	var path := STAGE_DIR + id + ".tres"
	_save(t, path)
	return load(path)


func _stage(id: String, index: int, title: String, threat: String, objective: String, power: int, energy: int,
		core: int, first_core: int, color: Color, scalar: float, stars3: int, timeline: StageTimelineData) -> StageNodeData:
	var s := StageNodeData.new()
	s.id = id
	s.index = index
	s.label = id
	s.title = title
	s.enemy_label = threat
	s.objective = objective
	s.recommended_power = power
	s.reward_rift_energy = energy
	s.reward_rift_core = core
	s.first_clear_rift_core = first_core
	s.map_position = POSITIONS[index - 1]
	s.planet_modulate = color
	s.starts_unlocked = false
	s.difficulty_scalar = scalar
	s.stars_hp_ratio_for_2 = 0.5
	s.stars_score_for_3 = stars3
	s.timeline = timeline
	return s


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		printerr("save failed %s (%d)" % [path, err])
		_fails += 1
	else:
		print("saved %s" % path)
