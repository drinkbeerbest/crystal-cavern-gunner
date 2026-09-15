class_name TrainingDummy
extends StaticBody2D
## TrainingDummy —— 打靶水晶（M3 开发用目标）。
##
## 作用有两个：
##   1. 试验场里给玩家一个能打的东西，肉眼验证弹道 / 激光 / 近战 / 爆炸；
##   2. 无头测试里的"受击契约"实现方，用来断言子弹真的造成了伤害、
##      暴击倍率、击退向量、穿透数量等。
##
## 它遵守 CombatUtil 的受击契约：
##   take_hit(amount, is_crit, knockback, source) -> void
## M4 的 Enemy 会实现同一份契约，本类随后只保留在试验场里当靶子。

const G := preload("res://scripts/core/game_const.gd")

const TEXTURE_PRIMARY: String = "res://assets/props/crystal_0.png"
const TEXTURE_FALLBACK: String = "res://assets/props/crate.png"

var max_health: float = 90.0
var health: float = 90.0
## 被打碎后是否自动重生（试验场用；测试里设为 false）
var auto_respawn: bool = true
var respawn_delay: float = 1.1

# ---------- 测试可观测计数 ----------
var hit_count: int = 0
var crit_count: int = 0
var total_damage: float = 0.0
var last_knockback: Vector2 = Vector2.ZERO
var last_source_id: int = 0
var destroyed: bool = false
var last_hit_position: Vector2 = Vector2.ZERO

var _sprite: Sprite2D
var _glow: Sprite2D
var _flash: float = 0.0
var _respawn_timer: float = 0.0


func _ready() -> void:
	add_to_group(CombatUtil.GROUP_ENEMIES)
	collision_layer = G.LAYER_ENEMY
	collision_mask = 0

	health = max_health

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 24)
	shape.shape = rect
	shape.position = Vector2(0, -2)
	add_child(shape)

	_glow = Sprite2D.new()
	if ResourceLoader.exists("res://assets/fx/glow_soft.png"):
		_glow.texture = load("res://assets/fx/glow_soft.png")
	_glow.scale = Vector2.ONE * 0.7
	_glow.modulate = Color(0.55, 0.85, 1.0, 0.35)
	_glow.z_index = -1
	add_child(_glow)

	_sprite = Sprite2D.new()
	var path: String = TEXTURE_PRIMARY if ResourceLoader.exists(TEXTURE_PRIMARY) else TEXTURE_FALLBACK
	if ResourceLoader.exists(path):
		_sprite.texture = load(path)
	_sprite.position = Vector2(0, -4)
	add_child(_sprite)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		_sprite.modulate = Color(2.2, 1.6, 1.6, 1.0) if _flash > 0.0 else Color.WHITE
	if destroyed:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0 and auto_respawn:
			respawn()
		return
	_glow.modulate.a = 0.28 + 0.1 * sin(Time.get_ticks_msec() * 0.004)


## 受击契约
func take_hit(amount: float, is_crit: bool, knockback: Vector2, source: int) -> void:
	if destroyed:
		return
	hit_count += 1
	total_damage += amount
	last_knockback = knockback
	last_source_id = source
	last_hit_position = global_position
	if is_crit:
		crit_count += 1
	health -= amount
	_flash = 0.12
	AudioMgr.play_sfx("hit_flesh", 0.08, -6.0)
	EventBus.enemy_hurt.emit(self, amount, is_crit)
	if health <= 0.0:
		_break_apart()


func _break_apart() -> void:
	destroyed = true
	health = 0.0
	_respawn_timer = respawn_delay
	_sprite.visible = false
	_glow.visible = false
	set_deferred("collision_layer", 0)
	AudioMgr.play_sfx("break_crate", 0.06)
	Fx.play(self, "explode", global_position + Vector2(0, -4), {"fps": 20.0, "scale": 0.85, "z_index": 12})
	Fx.scatter(self, "spark", global_position + Vector2(0, -4), 3, 12.0, {"fps": 24.0, "z_index": 12})
	EventBus.enemy_died.emit(self, global_position)


func respawn() -> void:
	destroyed = false
	health = max_health
	hit_count = 0
	crit_count = 0
	total_damage = 0.0
	_sprite.visible = true
	_glow.visible = true
	collision_layer = G.LAYER_ENEMY
	Fx.play(self, "ring", global_position, {"fps": 18.0, "scale": 0.9, "z_index": 12})


func is_dead_or_disabled() -> bool:
	return destroyed


func reset(full_health: float = 0.0) -> void:
	if full_health > 0.0:
		max_health = full_health
	respawn()
