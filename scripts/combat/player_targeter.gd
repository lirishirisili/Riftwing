class_name PlayerTargeter
extends RefCounted
## Targeter for hostile bolts: homing enemy orbs steer toward the player.
## Mirrors the SecondaryWeaponSystem targeter API used by Projectile.

var player: Node2D


func _init(p_player: Node2D = null) -> void:
	player = p_player


func nearest_target_node(_from: Vector2, _max_dist: float = INF) -> Node2D:
	if player != null and is_instance_valid(player) and player.visible:
		return player
	return null


## Hostile bolts never area-detonate (kept for API parity).
func detonate(_pos: Vector2, _radius: float, _damage: float, _pulses: int = 1, _interval: float = 0.35) -> void:
	pass
