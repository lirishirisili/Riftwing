class_name DailyChallenge
extends RefCounted
## Deterministic daily challenge derived from the local calendar date.
##
## No backend: the same local day always produces the same challenge for the
## same progress, so the run is reproducible and the one-time reward can be
## tracked by date string in SaveManager. Modifiers reuse the existing NORMAL /
## HARD difficulty profiles so the run pipeline needs no special-casing.
##
## The stage is drawn only from stages the player can already launch, and HARD
## is only rolled once the player has cleared a few stages, so a new pilot is
## never thrown into a late-sector HARD run.

const _FALLBACK_POOL := ["1-1", "1-2", "1-3"]
const _NORMAL := "normal"
const _HARD := "hard"
## Cleared NORMAL stages required before the daily may roll HARD.
const _HARD_UNLOCK_CLEARS := 3


## Local-date key "YYYY-MM-DD" — the identity of today's challenge.
static func today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## Stable non-negative seed for a given date key.
static func seed_for(date_key: String) -> int:
	return int(hash(date_key)) & 0x7fffffff


## Builds today's challenge descriptor. Pure and deterministic for a given date
## and inputs. `stage_pool` is the list of launchable stage ids (empty = the
## starter stages); `cleared_count` gates HARD rolls.
static func build(stage_pool: Array = [], cleared_count: int = 0) -> Dictionary:
	var key := today_key()
	var pool: Array = stage_pool if not stage_pool.is_empty() else _FALLBACK_POOL
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(key)
	var stage_id: String = String(pool[rng.randi_range(0, pool.size() - 1)])
	var hard := rng.randf() < 0.5 and cleared_count >= _HARD_UNLOCK_CLEARS
	var difficulty := _HARD if hard else _NORMAL
	var reward_core := 3 if hard else 2
	var modifier_label := "HARD MODIFIERS" if hard else "STANDARD MODIFIERS"
	return {
		"date_key": key,
		"seed": rng.seed,
		"stage_id": stage_id,
		"difficulty": difficulty,
		"reward_core": reward_core,
		"modifier_label": modifier_label,
	}
