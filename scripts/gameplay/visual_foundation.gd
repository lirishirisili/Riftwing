extends Node2D
## Visual foundation validation scene (milestone 15).
##
## Shows player scale, enemy sizes, projectile examples, pickups, parallax,
## engine glow, and hit-flash preview without changing combat systems.

@onready var _scout: Sprite2D = $Samples/Scout
@onready var _shooter: Sprite2D = $Samples/Shooter
@onready var _elite: Sprite2D = $Samples/Elite
@onready var _flash_sample: Sprite2D = $Samples/HitFlashDemo
@onready var _friendly: Projectile = $Samples/FriendlyBolt
@onready var _hostile: Projectile = $Samples/HostileBolt
@onready var _pickup_draw: Control = $Samples/PickupDemo
@onready var _label: Label = $UI/Caption

var _flash_t: float = 0.0


func _ready() -> void:
	_label.text = "RIFTSTRIKE visual foundation\nPlayer / enemies / bolts / pickup / parallax\nF3 debug overlay"
	_scout.modulate = Color(0.62, 0.32, 1, 1)
	_shooter.modulate = Color(0.55, 0.28, 0.95, 1)
	_elite.modulate = Color(0.7, 0.35, 1, 1)
	var player_data: ProjectileData = load("res://resources/weapons/plasma_projectile.tres")
	var enemy_data: ProjectileData = load("res://resources/weapons/enemy_plasma_projectile.tres")
	var bounds := Rect2(-200, -400, 2000, 3000)
	_friendly.hits_player = false
	_friendly.launch(Vector2(400, 1100), Vector2.UP, player_data, bounds)
	_friendly.set_process(false) # freeze for inspection
	_hostile.hits_player = true
	_hostile.launch(Vector2(680, 1100), Vector2.DOWN, enemy_data, bounds)
	_hostile.set_process(false)
	_pickup_draw.draw.connect(_on_pickup_draw)
	_pickup_draw.queue_redraw()


func _process(delta: float) -> void:
	_flash_t += delta
	var pulse := 0.5 + 0.5 * sin(_flash_t * 6.0)
	_flash_sample.modulate = Color(1, 1, 1, 1).lerp(Color(2.2, 2.2, 2.2, 1), pulse * 0.55)


func _on_pickup_draw() -> void:
	var r := 36.0
	var c := Color(0, 1, 0.61, 1)
	_pickup_draw.draw_circle(Vector2.ZERO, r * 1.7, Color(c, 0.22))
	_pickup_draw.draw_circle(Vector2.ZERO, r * 1.15, Color(c, 0.85))
	_pickup_draw.draw_circle(Vector2.ZERO, r * 0.55, Color(1, 1, 1, 0.95))
