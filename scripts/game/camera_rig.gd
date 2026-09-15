class_name CameraRig
extends Camera2D
## CameraRig —— 跟随玩家的战斗相机（M3）。
##
## 三件事：
##   1. 平滑跟随 + 朝瞄准方向的轻微前瞻（射击游戏手感关键）；
##   2. 把视野夹在房间边界内（房间比视野小时直接居中，避免露出黑边）；
##   3. 屏幕震动（监听 EventBus.request_screen_shake，可在设置里关闭）。
##
## 不用 Camera2D 自带的 position_smoothing / limit_*：房间尺寸随层变化，
## 自己插值 + 自己夹边界，换房时只需调一次 set_bounds()。

const G := preload("res://scripts/core/game_const.gd")

## 跟随插值速度（越大越硬）
const FOLLOW_SPEED: float = 13.0
## 瞄准方向前瞻距离（世界像素）
const LOOK_AHEAD: float = 30.0
## 前瞻的插值速度（比身体跟随更慢，避免甩枪时镜头乱晃）
const LOOK_SPEED: float = 6.0
## 震动衰减速率
const SHAKE_DECAY: float = 7.0
## 震动上限（防止多把武器叠加把画面抖散）
const SHAKE_CAP: float = 9.0

var target: Node2D = null
var bounds: Rect2 = Rect2()
var has_bounds: bool = false
var shake_strength: float = 0.0

var _shake_remain: float = 0.0
var _shake_total: float = 0.1
var _look_offset: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	zoom = Vector2(G.CAMERA_ZOOM, G.CAMERA_ZOOM)
	# 自己插值，关掉引擎平滑避免双重延迟
	position_smoothing_enabled = false
	make_current()
	if not EventBus.request_screen_shake.is_connected(_on_shake_requested):
		EventBus.request_screen_shake.connect(_on_shake_requested)


func set_target(node: Node2D) -> void:
	target = node
	if node != null:
		global_position = _clamp_to_bounds(node.global_position)


func set_bounds(rect: Rect2) -> void:
	bounds = rect
	has_bounds = rect.size.x > 0.0 and rect.size.y > 0.0


func clear_bounds() -> void:
	has_bounds = false
	bounds = Rect2()


func add_shake(strength: float, duration: float) -> void:
	shake_strength = minf(maxf(shake_strength, strength), SHAKE_CAP)
	_shake_total = maxf(duration, 0.05)
	_shake_remain = maxf(_shake_remain, _shake_total)


func stop_shake() -> void:
	shake_strength = 0.0
	_shake_remain = 0.0
	offset = Vector2.ZERO


func _physics_process(delta: float) -> void:
	var desired: Vector2 = _desired_position(delta)
	if target != null:
		global_position = global_position.lerp(desired, 1.0 - exp(-FOLLOW_SPEED * delta))
	else:
		global_position = desired
	_apply_shake(delta)


func _desired_position(delta: float) -> Vector2:
	if target == null or not is_instance_valid(target):
		return _clamp_to_bounds(global_position)
	var base: Vector2 = target.global_position

	# 前瞻：朝瞄准方向偏移，让玩家看到更多前方空间
	var aim: Vector2 = Vector2.ZERO
	if "aim_direction" in target:
		aim = target.aim_direction
	_look_offset = _look_offset.lerp(aim * LOOK_AHEAD, 1.0 - exp(-LOOK_SPEED * delta))

	return _clamp_to_bounds(base + _look_offset)


func _clamp_to_bounds(pos: Vector2) -> Vector2:
	if not has_bounds:
		return pos
	var half: Vector2 = get_viewport_rect().size / (2.0 * zoom.x)
	pos.x = _clamp_axis(pos.x, bounds.position.x + half.x, bounds.end.x - half.x, bounds.get_center().x)
	pos.y = _clamp_axis(pos.y, bounds.position.y + half.y, bounds.end.y - half.y, bounds.get_center().y)
	return pos


## 房间比视野窄时 min>max，此时锁定到中心而不是夹出界
static func _clamp_axis(value: float, min_value: float, max_value: float, fallback_center: float) -> float:
	if max_value < min_value:
		return fallback_center
	return clampf(value, min_value, max_value)


func _apply_shake(delta: float) -> void:
	if _shake_remain > 0.0:
		_shake_remain = maxf(_shake_remain - delta, 0.0)
		var ratio: float = _shake_remain / _shake_total
		var amount: float = shake_strength * ratio * ratio
		offset = Vector2(_rng.randf_range(-amount, amount), _rng.randf_range(-amount, amount))
		if _shake_remain <= 0.0:
			shake_strength = 0.0
			offset = Vector2.ZERO
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO


func _on_shake_requested(strength: float, duration: float) -> void:
	if strength <= 0.0:
		return
	if not bool(GameState.settings.get("screen_shake", true)):
		return
	add_shake(strength, duration)
