class_name UpgradeManager
extends Node
## Owns the upgrade catalog, the run loadout, and choice generation.
##
## On level-up the run flow asks for three choices (roll_choices), shows them,
## and calls apply() with the picked UpgradeData. The manager tracks per-upgrade
## levels, enforces prerequisites and max levels, and routes each effect to the
## right runtime system. All offered content and every applied number come from
## UpgradeData resources; no balance lives here.
##
## Weapon cards level their weapon when picked again (Lv 1 -> 5). Evolution
## cards become eligible once their recipe is met (`requires_max` at max level +
## `requires_owned` owned) and are always offered in the first slot. Banished
## cards never return this run. Luck tilts rolls toward rarer cards.

## Effects that belong to the run host (XP gain, HUD ability cooldowns) are
## re-emitted here instead of being routed to a combat system.
signal run_effect(kind: int, target: String, value: float)
## An evolution card was applied (presentation hook for the run host).
signal evolved(upgrade: UpgradeData)

## Catalog of every upgrade that can be offered this run.
@export var catalog: Array[UpgradeData] = []

## Weapon ids considered "owned" at run start (the base loadout). The plasma
## cannon is always equipped, so its upgrades' prerequisites resolve.
@export var starting_loadout: PackedStringArray = PackedStringArray(["plasma"])

## Hard cap on simultaneously equipped weapons (docs/02_GAMEPLAY_SPEC.md: four).
@export_range(1, 8) var max_weapons: int = 4

## Rarity weight multipliers by run level band (balance data, not code):
## [legendary <=3, legendary <=6, epic <=3, epic <=5].
@export var early_rarity_bias: PackedFloat32Array = PackedFloat32Array([0.22, 0.55, 0.5, 0.8])
## Per point of luck: weight multiplier added to EPIC / LEGENDARY cards.
@export_range(0.0, 2.0, 0.05) var luck_rarity_bonus: float = 0.35

## Weapon ids acquired via ACQUIRE_WEAPON effects (a subset of the loadout).
var _weapons: Dictionary = {}
## id -> chosen level for every upgrade picked so far.
var _levels: Dictionary = {}
## Generic ownership set (weapons + base loadout) used for prerequisite checks.
var _owned: Dictionary = {}
## Ids removed from this run's pool by the banish action.
var _banished: Dictionary = {}
var _luck: float = 0.0

var _rng := RandomNumberGenerator.new()
var _plasma: PlasmaWeapon = null
var _secondary: SecondaryWeaponSystem = null
var _player: PlayerShip = null


func _ready() -> void:
	_rng.randomize()
	for id in starting_loadout:
		_owned[id] = true
		_weapons[id] = 1


## The live plasma weapon whose runtime modifiers plasma upgrades adjust.
func bind_plasma_weapon(weapon: PlasmaWeapon) -> void:
	_plasma = weapon


## Binds the secondary weapon host and player so weapon acquisitions, secondary
## boosts, and defensive/utility upgrades take real runtime effect.
func bind_combat(player: PlayerShip, secondary: SecondaryWeaponSystem) -> void:
	_player = player
	_secondary = secondary


## Deterministic seeding so a probe/test can reproduce a specific roll.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Current chosen level of an upgrade (0 = never picked).
func level_of(id: String) -> int:
	return int(_levels.get(id, 0))


## Number of equipped weapons (base + acquired).
func weapon_count() -> int:
	return _weapons.size()


func get_luck() -> float:
	return _luck


func find_upgrade(id: String) -> UpgradeData:
	for upgrade in catalog:
		if upgrade != null and upgrade.id == id:
			return upgrade
	return null


## Removes an upgrade from this run's pool (the card never returns).
func banish(id: String) -> void:
	if id != "":
		_banished[id] = true


func is_banished(id: String) -> bool:
	return _banished.has(id)


## True when the upgrade is currently offerable: below its max level, all
## prerequisites owned, recipe met (evolutions), not banished, and — for weapon
## acquisitions — under the weapon cap.
func is_eligible(upgrade: UpgradeData) -> bool:
	if upgrade == null or _banished.has(upgrade.id):
		return false
	if level_of(upgrade.id) >= upgrade.max_level:
		return false
	for prereq in upgrade.prerequisites:
		if not _owned.has(prereq):
			return false
	if upgrade.is_evolution and not _recipe_met(upgrade):
		return false
	if _acquires_new_weapon(upgrade) and _weapons.size() >= max_weapons:
		return false
	return true


func _recipe_met(upgrade: UpgradeData) -> bool:
	for id in upgrade.requires_max:
		var base := find_upgrade(id)
		if base == null or level_of(id) < base.max_level:
			return false
	for id in upgrade.requires_owned:
		if level_of(id) <= 0 and not _owned.has(id):
			return false
	return true


## Every catalog entry currently eligible.
func eligible_upgrades() -> Array[UpgradeData]:
	var out: Array[UpgradeData] = []
	for upgrade in catalog:
		if is_eligible(upgrade):
			out.append(upgrade)
	return out


## Picks up to `count` distinct eligible upgrades, weighted by UpgradeData.weight,
## early-run rarity bias, and luck. An eligible evolution always takes slot 1.
func roll_choices(count: int = 3, run_level: int = 1) -> Array[UpgradeData]:
	var pool := eligible_upgrades()
	var chosen: Array[UpgradeData] = []
	for upgrade in pool:
		if upgrade.is_evolution:
			chosen.append(upgrade)
			pool.erase(upgrade)
			break
	while chosen.size() < count and pool.size() > 0:
		var pick := _weighted_take(pool, run_level)
		if pick == null:
			break
		chosen.append(pick)
		pool.erase(pick)
	return chosen


## Rolls `count` upgrades for a chest (may repeat stacking upgrades, never an
## evolution). Luck shifts toward rarer picks.
func roll_chest(count: int, run_level: int) -> Array[UpgradeData]:
	var out: Array[UpgradeData] = []
	for i in count:
		var pool: Array[UpgradeData] = []
		for upgrade in eligible_upgrades():
			if not upgrade.is_evolution:
				pool.append(upgrade)
		if pool.is_empty():
			break
		var pick := _weighted_take(pool, run_level + 3)
		if pick == null:
			break
		out.append(pick)
		# Apply immediately so repeat picks respect max levels.
		apply(pick)
	return out


## Synergy hint when the player already owns a listed partner upgrade/weapon.
func synergy_hint_for(upgrade: UpgradeData) -> String:
	if upgrade == null:
		return ""
	if upgrade.synergy_hint.strip_edges() != "":
		for id in upgrade.synergy_ids:
			if _owned.has(id) or level_of(id) > 0:
				return upgrade.synergy_hint
	return evolution_hint_for(upgrade)


## "Evolves into X" recipe hint for weapon / passive cards that feed an
## evolution the player has not unlocked yet.
func evolution_hint_for(upgrade: UpgradeData) -> String:
	if upgrade == null or upgrade.is_evolution:
		return ""
	for evo in catalog:
		if evo == null or not evo.is_evolution or level_of(evo.id) > 0:
			continue
		if upgrade.id in evo.requires_max:
			var partner := _first_title(evo.requires_owned)
			return "EVOLVES at max Lv + %s → %s" % [partner, evo.title] if partner != "" \
				else "EVOLVES at max Lv → %s" % evo.title
		if upgrade.id in evo.requires_owned:
			var weapon := _first_title(evo.requires_max)
			return "EVOLVES %s (max Lv) → %s" % [weapon, evo.title]
	return ""


func _first_title(ids: PackedStringArray) -> String:
	for id in ids:
		var u := find_upgrade(id)
		if u != null:
			return u.title
	return ""


## Applies a chosen upgrade: bumps its level, records ownership, and runs effects.
func apply(upgrade: UpgradeData) -> void:
	if upgrade == null:
		return
	_levels[upgrade.id] = level_of(upgrade.id) + 1
	_owned[upgrade.id] = true
	for effect in upgrade.effects:
		_apply_effect(effect)
	if upgrade.is_evolution:
		evolved.emit(upgrade)


func _apply_effect(effect: UpgradeEffectData) -> void:
	if effect == null:
		return
	match effect.kind:
		UpgradeEffectData.Kind.ACQUIRE_WEAPON:
			if _weapons.has(effect.target):
				# Picking an owned weapon's card again levels the weapon up.
				if _secondary != null:
					_secondary.level_up(effect.target)
			elif _weapons.size() < max_weapons:
				_weapons[effect.target] = 1
				_owned[effect.target] = true
				if _secondary != null:
					_secondary.acquire(effect.target)
		UpgradeEffectData.Kind.FIRE_RATE_MULT:
			if effect.target == "plasma" and _plasma != null:
				_plasma.add_fire_rate_mult(effect.value)
		UpgradeEffectData.Kind.PROJECTILES_ADD:
			if effect.target == "plasma" and _plasma != null:
				_plasma.add_projectiles(int(round(effect.value)))
		UpgradeEffectData.Kind.SPREAD_ADD:
			if effect.target == "plasma" and _plasma != null:
				_plasma.add_spread_degrees(effect.value)
		UpgradeEffectData.Kind.DAMAGE_MULT:
			if effect.target == "plasma" and _plasma != null:
				_plasma.add_damage_mult(effect.value)
		UpgradeEffectData.Kind.SECONDARY_DAMAGE_MULT:
			if _secondary != null:
				_secondary.add_damage_mult(effect.target, effect.value)
		UpgradeEffectData.Kind.SECONDARY_RATE_MULT:
			if _secondary != null:
				_secondary.add_rate_mult(effect.target, effect.value)
		UpgradeEffectData.Kind.SECONDARY_COUNT_ADD:
			if _secondary != null:
				_secondary.add_count(effect.target, int(round(effect.value)))
		UpgradeEffectData.Kind.ARMOR_ADD:
			if _player != null:
				_player.add_damage_reduction(effect.value)
		UpgradeEffectData.Kind.MAX_HP_MULT:
			if _player != null:
				_player.apply_max_hp_mult(effect.value)
		UpgradeEffectData.Kind.MOVE_SPEED_MULT:
			if _player != null:
				_player.apply_move_speed_mult(effect.value)
		UpgradeEffectData.Kind.CRIT_CHANCE_ADD:
			if _plasma != null:
				_plasma.add_crit_chance(effect.value)
		UpgradeEffectData.Kind.EVOLVE_WEAPON:
			if effect.target == "plasma":
				if _plasma != null:
					_plasma.evolve()
			elif _secondary != null:
				_secondary.evolve(effect.target)
		UpgradeEffectData.Kind.MAGNET_MULT:
			if _player != null:
				_player.apply_magnet_mult(effect.value)
		UpgradeEffectData.Kind.AREA_MULT:
			if _secondary != null:
				_secondary.add_area_mult(effect.value)
		UpgradeEffectData.Kind.REGEN_ADD:
			if _player != null:
				_player.add_regen(effect.value)
		UpgradeEffectData.Kind.LUCK_ADD:
			_luck += effect.value
		UpgradeEffectData.Kind.PIERCE_ADD:
			if _plasma != null:
				_plasma.add_pierce(int(round(effect.value)))
		UpgradeEffectData.Kind.BARRIER_ADD:
			if _player != null:
				_player.add_barrier(effect.value)
		UpgradeEffectData.Kind.HEAL_PERCENT:
			if _player != null:
				_player.heal_fraction(effect.value)
		UpgradeEffectData.Kind.COOLDOWN_MULT, UpgradeEffectData.Kind.XP_MULT:
			run_effect.emit(effect.kind, effect.target, effect.value)


func _acquires_new_weapon(upgrade: UpgradeData) -> bool:
	for effect in upgrade.effects:
		if effect != null and effect.kind == UpgradeEffectData.Kind.ACQUIRE_WEAPON:
			if not _weapons.has(effect.target):
				return true
	return false


## Removes and returns one upgrade from `pool`, weighted by effective weight.
func _weighted_take(pool: Array[UpgradeData], run_level: int = 1) -> UpgradeData:
	var total := 0.0
	for upgrade in pool:
		total += _effective_weight(upgrade, run_level)
	if total <= 0.0:
		return pool[0] if pool.size() > 0 else null
	var roll := _rng.randf() * total
	for upgrade in pool:
		roll -= _effective_weight(upgrade, run_level)
		if roll <= 0.0:
			return upgrade
	return pool[pool.size() - 1]


## Early levels suppress legendary/epic so each pick stays meaningful; luck
## lifts them back up.
func _effective_weight(upgrade: UpgradeData, run_level: int) -> float:
	var w := maxf(0.0, upgrade.weight)
	var lvl := maxi(1, run_level)
	var bias := early_rarity_bias
	match upgrade.rarity:
		UpgradeData.Rarity.LEGENDARY:
			if lvl <= 3 and bias.size() > 0:
				w *= bias[0]
			elif lvl <= 6 and bias.size() > 1:
				w *= bias[1]
			w *= 1.0 + _luck * luck_rarity_bonus
		UpgradeData.Rarity.EPIC:
			if lvl <= 3 and bias.size() > 2:
				w *= bias[2]
			elif lvl <= 5 and bias.size() > 3:
				w *= bias[3]
			w *= 1.0 + _luck * luck_rarity_bonus * 0.5
		_:
			pass
	return w
