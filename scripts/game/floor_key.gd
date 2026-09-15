class_name FloorKey
extends Area2D
## FloorKey —— 精英房掉落的「地牢钥匙」（M5）。
##
## 碰到即拾取（和金币/血包一致，不用按 E），写入 GameState.has_floor_key，
## 用来开本层的 Boss 房门；进下一层时由 GameState.advance_floor() 清空。

const G := preload("res://scripts/core/game_const.gd")

const TEX_PATH: String = "res://assets/pickups/key.png"
const PICKUP_RADIUS: float = 13.0
const BOB_AMPLITUDE: float = 3.0
const BOB_SPEED: float = 3.2

## 落地保护：钥匙常常正好掉在玩家脚下，留一点时间让它"掉出来"再可拾取
const ARM_DELAY: float = 0.45

signal collected(key: FloorKey)

var _sprite: Sprite2D = null
var _base_position: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _arm_timer: float = ARM_DELAY
var _collected: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = G.LAYER_PLAYER
	# 用 set_deferred：钥匙可能在物理回调链里生成（清怪瞬间），直接改会被引擎拦下
	set_deferred("monitoring", true)
	_base_position = position
	_build_nodes()
	body_entered.connect(_on_body_entered)


func _build_nodes() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "KeySprite"
	_sprite.texture = load(TEX_PATH) if ResourceLoader.exists(TEX_PATH) else null
	_sprite.z_index = 6
	add_child(_sprite)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PICKUP_RADIUS
	shape.shape = circle
	add_child(shape)


func _process(delta: float) -> void:
	_time += delta
	position = _base_position + Vector2(0, sin(_time * BOB_SPEED) * BOB_AMPLITUDE)
	if _sprite != null:
		# 轻微呼吸发光，提示这是关键道具
		var pulse: float = 1.0 + sin(_time * BOB_SPEED * 1.7) * 0.08
		_sprite.scale = Vector2.ONE * pulse


func _physics_process(delta: float) -> void:
	if _collected:
		return
	if _arm_timer > 0.0:
		_arm_timer = maxf(0.0, _arm_timer - delta)
		return
	# 轮询重叠：钥匙掉在玩家脚下时 body_entered 不会再发第二次
	for body: Node2D in get_overlapping_bodies():
		if body != null and is_instance_valid(body) and body.is_in_group(CombatUtil.GROUP_PLAYER):
			_collect()
			return


func _on_body_entered(body: Node2D) -> void:
	if _collected or _arm_timer > 0.0:
		return
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group(CombatUtil.GROUP_PLAYER):
		return
	_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true
	# 可能在 body_entered 回调链里，直接改 monitoring 会被引擎拦下
	set_deferred("monitoring", false)
	collected.emit(self)
	queue_free()
