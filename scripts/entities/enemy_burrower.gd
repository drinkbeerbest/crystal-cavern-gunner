class_name EnemyBurrower
extends Enemy
## EnemyBurrower —— 穿地兽，**钻地突墙**型（M9 新增原型）。
##
## 行为循环：潜入（关闭碰撞、可穿墙移动）→ 接近玩家 → 破土预警 → 破土砸地。
##
## 它是这批新怪里唯一会「无视地形」的：潜入期间 collision_layer/mask 归零，
## 因此能直接从墙的另一侧钻到玩家脚下。这解决了老敌人的一个老问题——
## 玩家躲在房间里打怪时，房间另一侧的怪只能干瞪眼。
##
## 公平性设计：破土前有 **WARN_TIME** 的地面预警圈（走 Telegraph 贴花），
## 玩家只要看到脚下亮红圈就知道要跳开；且破土瞬间怪物的 attack_cooldown_timer
## 留有硬直，不会"落地即砸"。所以它考的是「有没有注意到脚下的圈」，
## 而不是「有没有被凭空偷袭」。

enum Phase { SUBMERGED, WARNING, ERUPT, RECOVER }

const PHASE_NAMES: Array[String] = ["submerged", "warning", "erupt", "recover"]

## 破土前的地面预警时长
const WARN_TIME: float = 0.65
## 破土后的硬直（这段时间不会砸地，给玩家脱离窗口）
const ERUPT_STUN: float = 0.45
## 破土后的恢复时间
const RECOVER_TIME: float = 1.1
## 潜入时的可见度
const SUBMERGED_ALPHA: float = 0.22
## 破土范围
const ERUPT_RADIUS: float = 62.0

var phase: int = Phase.SUBMERGED
var phase_timer: float = 0.0
var erupt_position: Vector2 = Vector2.ZERO
var _telegraph: Telegraph = null

# 观测（测试用）
var eruptions: int = 0
var times_submerged: int = 0


func configure(enemy_data: EnemyData) -> void:
	super.configure(enemy_data)


func _ready() -> void:
	super._ready()
	_apply_submerged(true)


func _think(delta: float) -> void:
	_refresh_target()
	phase_timer = maxf(phase_timer - delta, 0.0)
	if target == null or not is_instance_valid(target) or _target_is_dead():
		if phase == Phase.WARNING:
			_cancel_warning()
		phase = Phase.SUBMERGED
		_apply_submerged(true)
		super._think(delta)
		return

	var to_target: Vector2 = target.global_position - global_position
	if to_target.length_squared() > 0.01:
		facing = to_target.normalized()

	match phase:
		Phase.SUBMERGED:
			_submerge(delta, to_target.length())
		Phase.WARNING:
			_hold()
			if phase_timer <= 0.0:
				_erupt()
		Phase.ERUPT:
			_hold()
			if phase_timer <= 0.0:
				phase = Phase.RECOVER
				phase_timer = RECOVER_TIME
				_apply_submerged(true)
				times_submerged += 1
		Phase.RECOVER:
			_hold()
			if phase_timer <= 0.0:
				phase = Phase.SUBMERGED
				_apply_submerged(true)


## 潜入：向玩家靠近并穿过墙体；接近到触发距离就准备破土
func _submerge(_delta: float, distance: float) -> void:
	set_state(State.CHASE)
	move_velocity = facing * data.move_speed * 1.35
	if distance <= maxf(data.erupt_trigger_range, 40.0):
		_begin_warning()


## 破土预警：在玩家脚下画一个逐渐填满的圆圈
func _begin_warning() -> void:
	phase = Phase.WARNING
	phase_timer = WARN_TIME
	move_velocity = Vector2.ZERO
	set_state(State.ATTACK)
	erupt_position = target.global_position if is_instance_valid(target) else global_position
	# 预警跟着玩家走？还是钉在原地？—— 钉在原地：钉住才可预判，
	# 跟着走会让玩家永远逃不出圈，读起来像"必中"，那就不好玩了。
	_telegraph = Telegraph.circle(_decal_host(), erupt_position, ERUPT_RADIUS, WARN_TIME,
			Color(1.0, 0.42, 0.24, 0.92))
	AudioMgr.play_sfx(data.sfx_fuse, 0.04, -10.0)


## 预警被取消（玩家跑出可感知范围 / 目标消失）
func _cancel_warning() -> void:
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null


## 破土：传送到预警位置，砸一圈范围伤害
func _erupt() -> void:
	phase = Phase.ERUPT
	phase_timer = ERUPT_STUN
	eruptions += 1
	global_position = erupt_position
	move_velocity = Vector2.ZERO
	_apply_submerged(false)
	AudioMgr.play_sfx("boss_slam", 0.0, -8.0)
	Fx.play(_fx_host(), "explode", global_position + Vector2(0, -4), {
		"fps": 22.0, "scale": ERUPT_RADIUS / 26.0, "z_index": 13,
	})
	Fx.scatter(_fx_host(), "dust", global_position, 8, 26.0, {"fps": 18.0, "z_index": 9})
	EventBus.request_screen_shake.emit(2.6, 0.18)
	# 破土落地才开始结算范围伤害：预警期给足了撤离时间
	CombatUtil.area_damage(self, global_position, ERUPT_RADIUS, data.erupt_damage, false,
			data.erupt_knockback, get_instance_id(), G.LAYER_PLAYER, [])


func _hold() -> void:
	move_velocity = Vector2.ZERO


## 潜入表现：半透明 + 关闭碰撞（这是它能穿墙的唯一原因）
func _apply_submerged(submerged: bool) -> void:
	if dead:
		return
	if submerged:
		collision_layer = 0
		collision_mask = 0
		if _sprite != null:
			_sprite.modulate = Color(1, 1, 1, SUBMERGED_ALPHA)
		# 沉到地板下面，视觉上"钻地里"
		z_index = -3
		if _glow != null:
			_glow.modulate = Color(0.6, 0.9, 1.0, 0.12)
	else:
		collision_layer = G.LAYER_ENEMY
		collision_mask = G.MASK_ENEMY
		z_index = 0
		if _sprite != null:
			_sprite.modulate = Color(1, 1, 1, 1)
		if _glow != null:
			_glow.modulate = Color(1.0, 0.7, 0.4, 0.4)


func _decal_host() -> Node2D:
	if decal_layer != null and is_instance_valid(decal_layer):
		return decal_layer
	var parent: Node = get_parent()
	return parent as Node2D if parent is Node2D else self


func _exit_tree() -> void:
	_cancel_warning()


func _update_animation(delta: float) -> void:
	super._update_animation(delta)
	if _sprite == null or hit_flash_timer > 0.0:
		return
	# 预警阶段逐渐显形，让"要出来了"这件事在贴图上也可见
	if phase == Phase.WARNING:
		var t: float = 1.0 - clampf(phase_timer / maxf(WARN_TIME, 0.01), 0.0, 1.0)
		_sprite.modulate = Color(1, 1, 1, lerpf(SUBMERGED_ALPHA, 1.0, t))
