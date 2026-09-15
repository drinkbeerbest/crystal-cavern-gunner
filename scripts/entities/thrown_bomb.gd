class_name ThrownBomb
extends Node2D
## ThrownBomb —— 玩家投掷的炸弹（M6）。
##
## 生命周期：飞行（抛物线视觉 + 空气阻力）-> 落地 -> 引信倒计时 -> 爆炸。
## 落地条件有二：飞满 BOMB_THROW_RANGE，或飞出房间可走范围 bounds（撞墙即落地）。
## 爆炸用 CombatUtil.area_damage 打敌人，并对玩家造成 BOMB_SELF_DAMAGE_RATIO 比例的自伤
## （按距离同样衰减），提示玩家不要贴脸扔。
##
## 素材复用掉落拾取物的 bomb_0..3.png（同一枚炸弹的两种状态，保持一致性）。

const G := preload("res://scripts/core/game_const.gd")

const BOMB_DIR: String = "res://assets/pickups/"
const FRAME_COUNT: int = 4
const FLY_FPS: float = 7.0
const DRAG: float = 300.0
const FLY_Z: int = 9
const REST_Z: int = 7

enum State { FLYING, FUSED, DONE }

## 爆炸结算结果：{"damaged": int, "self_hit": bool, "center": Vector2}
signal exploded(bomb: ThrownBomb, result: Dictionary)
signal landed(bomb: ThrownBomb)

var state: int = State.FLYING
var velocity: Vector2 = Vector2.ZERO
var max_range: float = G.BOMB_THROW_RANGE
var bounds: Rect2 = Rect2()
var radius: float = G.BOMB_RADIUS
var damage: float = G.BOMB_DAMAGE
var knockback: float = G.BOMB_KNOCKBACK
var fuse_time: float = G.BOMB_FUSE
var self_damage_ratio: float = G.BOMB_SELF_DAMAGE_RATIO
## 投掷者的 instance_id（作为 area_damage 的 source）
var thrower_id: int = 0
## 玩家引用：自伤用
var target_player: Player = null
## 特效宿主
var fx_layer: Node2D = null

var is_exploded: bool = false
var result: Dictionary = {}

var _sprite: Sprite2D = null
var _frames: Array = []
var _frame_index: int = 0
var _frame_timer: float = 0.0
var _time: float = 0.0
var _traveled: float = 0.0
var _fuse_remaining: float = 0.0


static func create(direction: Vector2, speed: float = G.BOMB_THROW_SPEED) -> ThrownBomb:
	var bomb := ThrownBomb.new()
	bomb.velocity = direction.normalized() * speed if direction.length_squared() > 0.001 else Vector2.UP * speed
	return bomb


func _ready() -> void:
	z_index = FLY_Z
	_build_nodes()
	if state == State.FUSED:
		_fuse_remaining = fuse_time


func _build_nodes() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "BombSprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = Vector2(0, -3)
	add_child(_sprite)
	for i: int in range(FRAME_COUNT):
		var path: String = BOMB_DIR + "bomb_%d.png" % i
		if ResourceLoader.exists(path):
			_frames.append(load(path))
	if not _frames.is_empty():
		_sprite.texture = _frames[0]


func _physics_process(delta: float) -> void:
	if state == State.DONE:
		return
	_time += delta
	match state:
		State.FLYING:
			_fly(delta)
		State.FUSED:
			_tick_fuse(delta)
	_update_animation(delta)


func _fly(delta: float) -> void:
	var step: Vector2 = velocity * delta
	position += step
	_traveled += step.length()
	velocity = velocity.move_toward(Vector2.ZERO, DRAG * delta)
	# 抛物线视觉：中段"更高"（贴图更大），落地回到原尺寸
	var ratio: float = clampf(_traveled / maxf(max_range, 1.0), 0.0, 1.0)
	var height: float = sin(ratio * PI)
	if _sprite != null:
		_sprite.scale = Vector2.ONE * (1.0 + height * 0.3)
		_sprite.position = Vector2(0, -3 - height * 7.0)
	if _traveled >= max_range or velocity.length_squared() < 400.0:
		land()
		return
	if bounds.size.x > 0.0 and bounds.size.y > 0.0 and not bounds.has_point(position):
		position = Vector2(
			clampf(position.x, bounds.position.x, bounds.end.x),
			clampf(position.y, bounds.position.y, bounds.end.y))
		land()


func land() -> void:
	if state != State.FLYING:
		return
	state = State.FUSED
	velocity = Vector2.ZERO
	_fuse_remaining = fuse_time
	z_index = REST_Z
	if _sprite != null:
		_sprite.scale = Vector2.ONE
		_sprite.position = Vector2(0, -3)
	Fx.play(_fx_host(), "dust", global_position + Vector2(0, 3), {"fps": 16.0, "scale": 0.6, "z_index": 4})
	AudioMgr.play_sfx("step", 0.0, -16.0)
	landed.emit(self)


func _tick_fuse(delta: float) -> void:
	_fuse_remaining -= delta
	# 引信越短闪得越快，给玩家撤离提示
	if _sprite != null:
		var urgency: float = 1.0 - clampf(_fuse_remaining / maxf(fuse_time, 0.001), 0.0, 1.0)
		_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.5, 0.9, 0.8), urgency * 0.55)
		_sprite.scale = Vector2.ONE * (1.0 + sin(_time * (10.0 + urgency * 26.0)) * 0.06)
	if _fuse_remaining <= 0.0:
		explode()


## 引信剩余时间（测试用）
func fuse_remaining() -> float:
	return _fuse_remaining


func _update_animation(delta: float) -> void:
	if _frames.size() < 2 or _sprite == null:
		return
	var fps: float = FLY_FPS
	if state == State.FUSED:
		var urgency: float = 1.0 - clampf(_fuse_remaining / maxf(fuse_time, 0.001), 0.0, 1.0)
		fps = lerpf(9.0, 24.0, urgency)
	_frame_timer += delta
	var step_time: float = 1.0 / maxf(fps, 1.0)
	if _frame_timer < step_time:
		return
	_frame_timer = fmod(_frame_timer, step_time)
	_frame_index = (_frame_index + 1) % _frames.size()
	_sprite.texture = _frames[_frame_index]


func explode() -> Dictionary:
	if is_exploded or state == State.DONE:
		return {}
	is_exploded = true
	state = State.DONE
	var center: Vector2 = global_position

	var damaged: Array = CombatUtil.area_damage(self, center, radius, damage, false,
			knockback, thrower_id, G.LAYER_ENEMY, [])

	var self_hit: bool = false
	if target_player != null and is_instance_valid(target_player) and not target_player.dead:
		var offset: Vector2 = target_player.global_position - center
		var distance: float = offset.length()
		if distance <= radius:
			var falloff: float = lerpf(1.0, 0.5, clampf(distance / maxf(radius, 1.0), 0.0, 1.0))
			var direction: Vector2 = offset.normalized() if distance > 0.5 else Vector2.UP
			self_hit = CombatUtil.apply_hit(target_player, damage * self_damage_ratio * falloff,
					false, direction * knockback * 0.55, thrower_id)

	AudioMgr.play_sfx("explode_big", 0.0, -3.0)
	Fx.play(_fx_host(), "explode", center, {"fps": 18.0, "scale": 1.5, "z_index": 14})
	Fx.play(_fx_host(), "smoke", center, {"fps": 12.0, "scale": 1.7, "z_index": 13})
	Fx.play(_fx_host(), "ring", center, {"fps": 20.0, "scale": radius / 26.0, "z_index": 11})
	EventBus.request_screen_shake.emit(4.2, 0.26)

	result = {
		"center": center, "damaged": damaged.size(), "self_hit": self_hit,
		"radius": radius, "damage": damage,
	}
	exploded.emit(self, result)
	queue_free()
	return result


func _fx_host() -> Node2D:
	if fx_layer != null and is_instance_valid(fx_layer):
		return fx_layer
	var parent_node: Node = get_parent()
	return parent_node as Node2D
