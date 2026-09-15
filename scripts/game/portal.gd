class_name Portal
extends Area2D
## Portal —— 通往下一层的传送门（M5）。
##
## Boss 房清空后由世界层生成并 `activate()`，玩家走进去即触发 `used`。
## 8 帧循环动画来自 assets/props/portal_0..7.png，交给 FxSprite 播放。

const G := preload("res://scripts/core/game_const.gd")

const PROP_DIR: String = "res://assets/props/"
const FRAME_COUNT: int = 8
const ANIM_FPS: float = 12.0
## 激活后的武装延迟：传送门可能正好出现在玩家脚下，别一瞬间把人吸走
const ARM_DELAY: float = 0.8
const TRIGGER_RADIUS: float = 17.0

signal used(portal: Portal)

var is_active: bool = false
var target_floor: int = 1

var _arm_timer: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = G.LAYER_PLAYER
	set_deferred("monitoring", false)
	_build_nodes()


func _build_nodes() -> void:
	var frames: Array[Texture2D] = []
	for i: int in range(FRAME_COUNT):
		var path: String = PROP_DIR + "portal_%d.png" % i
		if ResourceLoader.exists(path):
			frames.append(load(path))
	if not frames.is_empty():
		Fx.play_frames(self, frames, Vector2(0, -16),
				{"fps": ANIM_FPS, "loop": true, "fade": false, "z_index": 3})

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = TRIGGER_RADIUS
	shape.shape = circle
	add_child(shape)

	body_entered.connect(_on_body_entered)


## 开门：播音效 + 开始监听玩家
func activate(p_target_floor: int = 1) -> void:
	target_floor = p_target_floor
	is_active = true
	_arm_timer = ARM_DELAY
	set_deferred("monitoring", true)
	AudioMgr.play_sfx("portal", 0.0, -5.0)


func _physics_process(delta: float) -> void:
	if _arm_timer > 0.0:
		_arm_timer = maxf(0.0, _arm_timer - delta)
		return
	if not is_active or not monitoring:
		return
	# 轮询重叠：传送门常常正好在玩家脚下激活，body_entered 只在"进入瞬间"发一次，
	# 站着不动就永远收不到第二次，这里补上持续检测。
	for body: Node2D in get_overlapping_bodies():
		if body != null and is_instance_valid(body) and body.is_in_group(CombatUtil.GROUP_PLAYER):
			_trigger()
			return


func _trigger() -> void:
	if not is_active:
		return
	is_active = false
	# 可能在 body_entered 回调链里，直接改 monitoring 会被引擎拦下
	set_deferred("monitoring", false)
	AudioMgr.play_sfx("teleport_out", 0.0, -6.0)
	used.emit(self)


func _on_body_entered(body: Node2D) -> void:
	if not is_active or _arm_timer > 0.0:
		return
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group(CombatUtil.GROUP_PLAYER):
		return
	_trigger()
