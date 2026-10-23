class_name CombatProfile
extends RefCounted
## Runtime-derived combat stats for a single run.
##
## Built once at run start from the selected ship's base stats + the player's
## hangar upgrade levels (via HangarStats). This is the single place that turns
## authored ATK / DEF / HP / CRIT numbers into the concrete run modifiers combat
## uses: weapon damage multiplier, HP multiplier, crit chance/multiplier,
## incoming-damage reduction, and movement responsiveness. It never mutates a
## shared Resource — callers duplicate their own data and read these values.
##
## All modifiers are RELATIVE to a reference ship (the starter ship): a level-0
## starter yields neutral values (mult 1.0, 0 reduction) so the run keeps its
## tuned baseline, every hangar purchase improves the run from there, and a
## higher-tier ship is genuinely stronger (or trades stats) instead of being
## normalized back to the starter. Without a reference the ship is its own.


## Added-DEF softening: extra DEF equal to this value yields ~50% reduction.
const _DEF_SOFTENING := 300.0
## Hard cap so defense can never trivialize danger (telegraphs must still matter).
const _MAX_REDUCTION := 0.6
## A ship with less DEF than the reference takes up to this much extra damage.
const _MIN_REDUCTION := -0.2
## Crit chance can never exceed this (keeps damage variance readable).
const _CRIT_CAP := 0.75
## Per engine level movement responsiveness bonus.
const _ENGINE_MOVE_PER_LEVEL := 0.03
const _ENGINE_MOVE_CAP := 1.6

var hp_mult: float = 1.0            # scales the run's baseline HP
var weapon_damage_mult: float = 1.0
var crit_chance: float = 0.0        # 0..1
var crit_multiplier: float = 1.75
var damage_reduction: float = 0.0   # 0..0.6
var move_speed_mult: float = 1.0
## Snapshot of the raw hangar totals (for HUD / debug readouts).
var attack: int = 0
var defense: int = 0
var hp: int = 0
var critical: float = 0.0


## Builds a profile from a ship and its hangar level map. Pure: does not touch
## SaveManager or mutate `ship`.
static func from_hangar(ship: ShipData, levels: Dictionary, reference: ShipData = null) -> CombatProfile:
	var p := CombatProfile.new()
	if ship == null:
		return p
	var stats := HangarStats.compute(ship, levels)
	p.attack = stats.attack
	p.defense = stats.defense
	p.hp = stats.hp
	p.critical = stats.critical
	# Everything is relative to the reference ship, so a fresh starter reads
	# neutral and only upgrades (or a stronger hull) change the run.
	var ref := reference if reference != null else ship
	var base_atk := maxi(1, ref.base_attack)
	var base_hp := maxi(1, ref.base_hp)
	p.weapon_damage_mult = maxf(0.01, float(stats.attack) / float(base_atk))
	p.hp_mult = maxf(0.01, float(stats.hp) / float(base_hp))
	# Critical is authored as a percent (e.g. 8.0 => 8%).
	p.crit_chance = clampf(stats.critical / 100.0, 0.0, _CRIT_CAP)
	# DEF above the reference grants armor with diminishing returns; a lighter
	# hull (Razor Wing) below the reference takes a little extra damage.
	var added_def := float(stats.defense - ref.base_defense)
	if added_def >= 0.0:
		p.damage_reduction = clampf(added_def / (added_def + _DEF_SOFTENING), 0.0, _MAX_REDUCTION)
	else:
		p.damage_reduction = clampf(added_def / _DEF_SOFTENING * 0.5, _MIN_REDUCTION, 0.0)
	# Engine track drives movement responsiveness on top of its combat deltas.
	var engine_level := int(levels.get("engine", 0))
	p.move_speed_mult = clampf(
		1.0 + _ENGINE_MOVE_PER_LEVEL * float(maxi(0, engine_level)),
		1.0, _ENGINE_MOVE_CAP)
	return p


## Reduces incoming player damage by the profile's mitigation. Centralized here
## so Player / Enemy / Projectile never re-implement armor math.
func mitigate(incoming: float) -> float:
	return maxf(0.0, incoming * (1.0 - damage_reduction))


## Resolves an outgoing hit: applies the weapon damage multiplier and rolls a
## crit with the supplied RNG. Returns {"damage": float, "crit": bool}.
func resolve_hit(base_damage: float, rng: RandomNumberGenerator) -> Dictionary:
	var dmg := base_damage * weapon_damage_mult
	var crit := crit_chance > 0.0 and rng != null and rng.randf() < crit_chance
	if crit:
		dmg *= crit_multiplier
	return {"damage": dmg, "crit": crit}
