class_name ExperienceTracker
extends Node
## Turns collected energy into run experience and fires level-ups.
##
## Listens to the player's `energy_changed` signal, accumulates XP, and compares
## it against a data-driven LevelCurveData. At most one `leveled_up` is emitted
## while a choice is still pending — excess XP banks above the threshold so a
## big pickup / guaranteed grant never floods the upgrade screen queue. The next
## level only resolves on a later XP gain after the player finishes the current
## choice (play → pick → play → pick).

## Emitted once per level gained. `new_level` is the level just reached.
signal leveled_up(new_level: int)
## Emitted whenever XP or level changes, for HUD / debug readouts.
signal progress_changed(level: int, xp_into_level: int, xp_for_next: int)

@export var curve: LevelCurveData

var _level: int = 1
var _xp_into_level: int = 0
var _last_energy: int = 0
var _pending_levels: int = 0


func _ready() -> void:
	if curve == null:
		curve = LevelCurveData.new()


## Connects to a player's energy signal. Energy gained since the last reading is
## converted 1:1 into XP (the pickup value is the balance lever, not this node).
func track_player(player: PlayerShip) -> void:
	_last_energy = player.get_energy()
	if not player.energy_changed.is_connected(_on_energy_changed):
		player.energy_changed.connect(_on_energy_changed)
	progress_changed.emit(_level, _xp_into_level, curve.xp_to_reach_next(_level))


func get_level() -> int:
	return _level


func get_xp_into_level() -> int:
	return _xp_into_level


func get_xp_for_next() -> int:
	return curve.xp_to_reach_next(_level)


## Levels earned but not yet consumed by an upgrade choice.
func get_pending_levels() -> int:
	return _pending_levels


## The run flow calls this after showing one upgrade screen to consume a level.
## Does not immediately fire the next level — banked XP waits for the next gain
## so choices never cascade back-to-back without combat in between.
func consume_pending_level() -> void:
	if _pending_levels > 0:
		_pending_levels -= 1
	progress_changed.emit(_level, _xp_into_level, curve.xp_to_reach_next(_level))


func _on_energy_changed(total: int) -> void:
	var gained := total - _last_energy
	_last_energy = total
	if gained > 0:
		add_experience(gained)


## Adds raw XP and rolls at most one level-up while none is pending.
## Exposed so a debug command can force a level without collecting pickups.
func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	_xp_into_level += amount
	_try_level_up_once()
	progress_changed.emit(_level, _xp_into_level, curve.xp_to_reach_next(_level))


## Resolves a single threshold crossing. Further crossings stay banked until the
## pending choice is consumed and more XP arrives.
func _try_level_up_once() -> void:
	if _pending_levels > 0:
		return
	var needed := curve.xp_to_reach_next(_level)
	if _xp_into_level < needed:
		return
	_xp_into_level -= needed
	_level += 1
	_pending_levels = 1
	leveled_up.emit(_level)
