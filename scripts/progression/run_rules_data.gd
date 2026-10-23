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
