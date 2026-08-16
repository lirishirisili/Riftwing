class_name DailyChallenge
extends RefCounted
## Deterministic daily challenge derived purely from the local calendar date.
##
## No backend: the same local day always produces the same stage + modifiers, so
## the run is reproducible and the one-time reward can be tracked by date string
## in SaveManager. Modifiers reuse the existing NORMAL / HARD difficulty profiles
## so the run pipeline needs no special-casing.

const _STAGE_POOL := ["1-1", "1-2", "1-3", "1-4", "1-5", "1-6", "1-7", "1-8"]
const _NORMAL := "normal"
const _HARD := "hard"


## Local-date key "YYYY-MM-DD" — the identity of today's challenge.
static func today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## Stable non-negative seed for a given date key.
static func seed_for(date_key: String) -> int:
	return int(hash(date_key)) & 0x7fffffff


## Builds today's challenge descriptor. Pure and deterministic for a given date.
static func build() -> Dictionary:
	var key := today_key()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(key)
	var stage_id: String = _STAGE_POOL[rng.randi_range(0, _STAGE_POOL.size() - 1)]
	var hard := rng.randf() < 0.5
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
