class_name RunRulesData
extends Resource
## Run-wide rules that are not tied to a single enemy, weapon, or stage.
##
## Everything here used to be a constant inside RunController / the HUD / the
## upgrade screen. Keeping it in one Resource lets balance be tuned without code
## changes (docs/04_ARCHITECTURE.md: balance in Resources, behavior in nodes).

## Seconds a kill chain stays alive without another kill.
@export_range(0.5, 10.0, 0.1) var combo_window_seconds: float = 2.5

## Delay between the end-of-run banner and the results screen.
@export_range(0.2, 5.0, 0.1) var results_delay_seconds: float = 1.6

## Free card rerolls granted per run.
@export_range(0, 10) var rerolls_per_run: int = 1

## Card banishes per run (a banished card never returns this run).
@export_range(0, 10) var banishes_per_run: int = 2

## Left HUD ability (Missile Barrage): stored charges and recharge seconds.
@export_range(1, 9) var ability_left_charges: int = 3
@export_range(0.5, 60.0, 0.5) var ability_left_cooldown: float = 7.0

## Right HUD ability (Arc Burst): stored charges and recharge seconds.
@export_range(1, 9) var ability_right_charges: int = 2
@export_range(0.5, 60.0, 0.5) var ability_right_cooldown: float = 9.0

## Protected window granted when a boss dies, so leftover fire cannot turn a
## won fight into a defeat during the death sequence.
@export_range(0.0, 6.0, 0.1) var boss_kill_invuln_seconds: float = 2.5

## When a wave runs dry before the phase clock reaches its next beat, the wave
## restarts if at least this many seconds remain (otherwise the clock jumps
## straight to the next beat so there is never dead air).
@export_range(0.0, 60.0, 1.0) var wave_refill_min_seconds: float = 12.0

# --- Combo / streaks ---------------------------------------------------------

## Kills per combo tier; each tier adds `combo_bonus_per_tier` to the score
## multiplier applied to kill points (x1.0 -> up to `combo_max_mult`).
@export_range(1, 100) var combo_kills_per_tier: int = 10
@export_range(0.0, 2.0, 0.05) var combo_bonus_per_tier: float = 0.25
@export_range(1.0, 10.0, 0.1) var combo_max_mult: float = 3.0

## Kill-streak callouts: combo counts and their labels (same length).
@export var streak_thresholds: PackedInt32Array = PackedInt32Array([15, 30, 50, 80, 120])
@export var streak_labels: PackedStringArray = PackedStringArray([
	"KILLING SPREE", "RAMPAGE", "UNSTOPPABLE", "GODLIKE", "RIFT LEGEND"])

# --- Rift Nova (screen-clear ultimate) ---------------------------------------

## Kills needed to charge the Nova from empty.
@export_range(5, 500) var nova_kills_to_charge: int = 45
## Boss damage (fraction of its max HP) that fully charges the Nova.
@export_range(0.05, 2.0, 0.05) var nova_boss_damage_to_charge: float = 0.6
## Damage dealt to every wave enemy / boss add on screen.
@export_range(1.0, 10000.0, 1.0) var nova_enemy_damage: float = 400.0
## Boss damage as a fraction of the boss's max HP.
@export_range(0.0, 0.5, 0.01) var nova_boss_damage_ratio: float = 0.06
## Invulnerability granted when the Nova detonates.
@export_range(0.0, 3.0, 0.1) var nova_invuln_seconds: float = 1.0

# --- Drops / chests -------------------------------------------------------------

## Chance per normal kill to drop a heal orb / magnet orb.
@export_range(0.0, 0.5, 0.001) var heal_drop_chance: float = 0.012
@export_range(0.0, 0.5, 0.001) var magnet_drop_chance: float = 0.007
## Chest reveal sizes and their base weights (same length), e.g. 1 / 3 / 5.
@export var chest_sizes: PackedInt32Array = PackedInt32Array([1, 3, 5])
@export var chest_weights: PackedFloat32Array = PackedFloat32Array([0.66, 0.27, 0.07])
## Per point of luck, multiplies the weight of every chest size above 1.
@export_range(0.0, 3.0, 0.05) var chest_luck_bonus: float = 0.5
## The mini-boss drops a chest.
@export var mini_boss_drops_chest: bool = true

# --- Endless / Boss Rush ----------------------------------------------------------

## Endless: seconds of waves between bosses, and the per-boss difficulty step.
@export_range(20.0, 300.0, 5.0) var endless_boss_interval: float = 75.0
@export_range(1.0, 2.0, 0.01) var endless_scale_per_boss: float = 1.2
## Boss Rush: breather between bosses and free level-ups granted before each.
@export_range(1.0, 15.0, 0.5) var rush_breather_seconds: float = 4.0
@export_range(0, 4) var rush_levels_per_boss: int = 1

# --- Rewarded revive ------------------------------------------------------------

## Revives allowed per run (rewarded ad), HP restored, protection window, and
## how long the offer stays up.
@export_range(0, 3) var revives_per_run: int = 1
@export_range(0.1, 1.0, 0.05) var revive_hp_fraction: float = 0.5
@export_range(0.5, 6.0, 0.1) var revive_invuln_seconds: float = 3.0
@export_range(2.0, 15.0, 0.5) var revive_offer_seconds: float = 6.0
