class_name UpgradeManager
extends Node
## Owns the upgrade catalog, the run loadout, and choice generation.
##
## On level-up the run flow asks for three choices (roll_choices), shows them,
## and calls apply() with the picked UpgradeData. The manager tracks per-upgrade
## levels, enforces prerequisites and max levels, and routes each effect to the
## right runtime system. All offered content and every applied number come from
## UpgradeData resources; no balance lives here.

## Catalog of every upgrade that can be offered this run.
@export var catalog: Array[UpgradeData] = []

## Weapon ids considered "owned" at run start (the base loadout). The plasma
## cannon is always equipped, so its upgrades' prerequisites resolve.
@export var starting_loadout: PackedStringArray = PackedStringArray(["plasma"])

## Hard cap on simultaneously equipped weapons (docs/02_GAMEPLAY_SPEC.md: four).
@export_range(1, 8) var max_weapons: int = 4

## Weapon ids acquired via ACQUIRE_WEAPON effects (a subset of the loadout).
var _weapons: Dictionary = {}
## id -> chosen level for every upgrade picked so far.
var _levels: Dictionary = {}
## Generic ownership set (weapons + base loadout) used for prerequisite checks.
var _owned: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _plasma: PlasmaWeapon = null


func _ready() -> void:
	_rng.randomize()
	for id in starting_loadout:
		_owned[id] = true
		_weapons[id] = 1


## The live plasma weapon whose runtime modifiers plasma upgrades adjust.
func bind_plasma_weapon(weapon: PlasmaWeapon) -> void:
	_plasma = weapon


## Deterministic seeding so a probe/test can reproduce a specific roll.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## Current chosen level of an upgrade (0 = never picked).
func level_of(id: String) -> int:
	return int(_levels.get(id, 0))


## Number of equipped weapons (base + acquired).
func weapon_count() -> int:
	return _weapons.size()


## True when the upgrade is currently offerable: below its max level, all
## prerequisites owned, and — for weapon acquisitions — under the weapon cap.
func is_eligible(upgrade: UpgradeData) -> bool:
	if upgrade == null:
		return false
	if level_of(upgrade.id) >= upgrade.max_level:
		return false
	for prereq in upgrade.prerequisites:
		if not _owned.has(prereq):
			return false
	if _acquires_new_weapon(upgrade) and _weapons.size() >= max_weapons:
		return false
	return true


## Every catalog entry currently eligible.
func eligible_upgrades() -> Array[UpgradeData]:
	var out: Array[UpgradeData] = []
	for upgrade in catalog:
		if is_eligible(upgrade):
			out.append(upgrade)
	return out


## Picks up to `count` distinct eligible upgrades, weighted by UpgradeData.weight
## and early-run rarity bias (legendary rarer early; epic mid-run).
## No reroll this milestone (docs/02_GAMEPLAY_SPEC.md); the caller shows the result.
func roll_choices(count: int = 3, run_level: int = 1) -> Array[UpgradeData]:
	var pool := eligible_upgrades()
	var chosen: Array[UpgradeData] = []
	while chosen.size() < count and pool.size() > 0:
		var pick := _weighted_take(pool, run_level)
		if pick == null:
			break
		chosen.append(pick)
		pool.erase(pick)
	return chosen


## Synergy hint when the player already owns a listed partner upgrade/weapon.
func synergy_hint_for(upgrade: UpgradeData) -> String:
	if upgrade == null or upgrade.synergy_hint.strip_edges() == "":
		return ""
	for id in upgrade.synergy_ids:
		if _owned.has(id) or level_of(id) > 0:
			return upgrade.synergy_hint
	return ""


## Applies a chosen upgrade: bumps its level, records ownership, and runs effects.
func apply(upgrade: UpgradeData) -> void:
	if upgrade == null:
		return
	_levels[upgrade.id] = level_of(upgrade.id) + 1
	_owned[upgrade.id] = true
	for effect in upgrade.effects:
		_apply_effect(effect)


func _apply_effect(effect: UpgradeEffectData) -> void:
	if effect == null:
		return
	match effect.kind:
		UpgradeEffectData.Kind.ACQUIRE_WEAPON:
			if not _weapons.has(effect.target) and _weapons.size() < max_weapons:
				_weapons[effect.target] = 1
				_owned[effect.target] = true
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


## Early levels suppress legendary/epic so each pick stays meaningful.
func _effective_weight(upgrade: UpgradeData, run_level: int) -> float:
	var w := maxf(0.0, upgrade.weight)
	var lvl := maxi(1, run_level)
	match upgrade.rarity:
		UpgradeData.Rarity.LEGENDARY:
			if lvl <= 3:
				w *= 0.22
			elif lvl <= 6:
				w *= 0.55
		UpgradeData.Rarity.EPIC:
			if lvl <= 3:
				w *= 0.5
			elif lvl <= 5:
				w *= 0.8
		_:
			pass
	return w
