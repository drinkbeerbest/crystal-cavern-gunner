class_name EnemyStalker
extends Enemy
## EnemyStalker —— 影袭者，**隐形**型近战（M9 新增原型）。
##
## 行为循环：潜行 → 贴近 → 显形突刺 → 重新潜行。
##
## 设计要点：隐形敌最大的风险是"玩家看不见所以被白嫖"。所以这里强制两件事：
##   1. 潜行时**必须留痕**——半透明剪影 + 脚下渐强的红光，玩家永远知道"有东西在靠近"；
##   2. 显形前有固定的前摇，并且**显形那一帧无敌**——
##      所以它可以贴着你的脸出现，但你只要在它突刺前躲开方向就不会挨刀。
## 换句话说，它考的是"能不能从残影里读出方向"，不是"会不会被偷袭"。

## 潜行 / 显形前摇 / 突刺 后退 的状态
enum Phase { STALK, REVEAL, LUNGE, RECOVER }

const PHASE_NAMES: Array[String] = ["stalk", "reveal", "lunge", "recover"]

## 潜行时的可见度（保留剪影而不是完全消失）
const HIDDEN_ALPHA: float = 0.28
## 显形前摇的**兜底**时长。实际值走 `data.reveal_time`（可在数值表里调），
## 之所以不直接用常量：隐形怪的平衡全押在这一项上，它必须是能调的数据，而不是写死的数字。
const REVEAL_TIME_FALLBACK: float = 0.85
## 突刺后摇：动作变形期间不能再次潜行，避免无限压脸
const RECOVER_TIME: float = 0.75
## 潜行触发的最小距离兜底（防止数值表把 strike_trigger_range 填成 0）
const MIN_TRIGGER_RANGE: float = 24.0

var phase: int = Phase.STALK
var phase_timer: float = 0.0

var _lunge_dir: Vector2 = Vector2.RIGHT
var _rng_seedless := RandomNumberGenerator.new()

# 观测（测试用）
var reveals: int = 0
var lunges: int = 0
var times_hidden: int = 0


func configure(enemy_data: EnemyData) -> void:
	super.configure(enemy_data)
	_rng_seedless.seed = hash("stalker" + str(enemy_data.id) + str(GameState.run_seed))


func _think(delta: float) -> void:
	_refresh_target()
	phase_timer = maxf(phase_timer - delta, 0.0)
	if target == null or not is_instance_valid(target) or _target_is_dead():
		# 没人可打就退回基类的游荡，并恢复可见
		phase = Phase.STALK
		super._think(delta)
		_apply_stalk_look()
		return

	var to_target: Vector2 = target.global_position - global_position
	var distance: float = to_target.length()
	if distance > 0.01:
		facing = to_target.normalized()

	match phase:
		Phase.STALK:
			_stalk(delta, distance)
		Phase.REVEAL:
			_hold(delta)
			if phase_timer <= 0.0:
				_begin_lunge()
		Phase.LUNGE:
			_lunge(delta, distance)
		Phase.RECOVER:
			_hold(delta)
			if phase_timer <= 0.0:
				_enter_stalk()


## 潜行：朝玩家摸过去，速度略快于普通近战但**不吃接触伤害**（否则隐形白嫖）
func _stalk(_delta: float, distance: float) -> void:
	set_state(State.CHASE)
	move_velocity = facing * data.move_speed
	_apply_stalk_look()
	if distance <= maxf(data.strike_trigger_range, MIN_TRIGGER_RANGE):
		_begin_reveal()


## 本次显形的实际前摇时长（数值表优先）
func reveal_duration() -> float:
	return maxf(data.reveal_time if data != null else REVEAL_TIME_FALLBACK, 0.1)


## 显形前摇：站定不动 + 红光渐强，这是玩家唯一的信息，必须给足
func _begin_reveal() -> void:
	phase = Phase.REVEAL
	phase_timer = reveal_duration()
	move_velocity = Vector2.ZERO
	reveals += 1
	set_state(State.ATTACK)
	AudioMgr.play_sfx(data.sfx_fuse, 0.03, -12.0)
	Fx.play(_fx_host(), "ring", global_position, {
		"fps": 18.0, "scale": 0.6, "z_index": 4, "tint": Color(1.0, 0.35, 0.3, 0.8),
	})


func _begin_lunge() -> void:
	phase = Phase.LUNGE
	phase_timer = 0.0
	_lunge_dir = facing
	lunges += 1
	_reveal_flash()


## 突刺：沿锁定方向高速突进，命中玩家即结算并进入后摇
func _lunge(delta: float, distance: float) -> void:
	set_state(State.ATTACK)
	move_velocity = _lunge_dir * data.strike_speed
	if target != null and is_instance_valid(target) and not _target_is_dead():
		var reach: float = data.body_radius + _body_radius_of(target) + 8.0
		if global_position.distance_to(target.global_position) <= reach:
			damage_target(data.strike_damage, _lunge_dir * data.strike_knockback)
			_end_lunge()
			return
	# 突刺时长到 / 撞墙就收手
	phase_timer += delta
	if phase_timer >= data.strike_duration or last_collided_wall:
		_end_lunge()


func _end_lunge() -> void:
	phase = Phase.RECOVER
	phase_timer = RECOVER_TIME
	move_velocity = Vector2.ZERO
	_lunge_fx()


## 显形后摇结束后重新潜行
func _enter_stalk() -> void:
	phase = Phase.STALK
	phase_timer = 0.0
	times_hidden += 1
	set_state(State.CHASE)
	_apply_stalk_look()


func _hold(_delta: float) -> void:
	move_velocity = Vector2.ZERO


## 潜行表现：半透明 + 脚下的"逼近红光"随距离增强
func _apply_stalk_look() -> void:
	if _sprite == null:
		return
	_sprite.modulate = Color(1, 1, 1, HIDDEN_ALPHA)
	if _glow != null:
		var closeness: float = 1.0
		if target != null and is_instance_valid(target):
			var distance: float = global_position.distance_to(target.global_position)
			closeness = clampf(1.0 - distance / maxf(data.strike_trigger_range * 2.0, 1.0), 0.0, 1.0)
		_glow.modulate = Color(1.0, 0.35, 0.3, 0.10 + 0.35 * closeness)


## 显形：恢复不透明并闪一下
func _reveal_flash() -> void:
	if _sprite != null:
		_sprite.modulate = Color(2.4, 1.9, 1.9, 1.0)
	if _glow != null:
		_glow.modulate = Color(1.0, 0.55, 0.4, 0.55)
	set_state(State.ATTACK)


func _lunge_fx() -> void:
	AudioMgr.play_sfx(data.sfx_attack, 0.03, -12.0)
	Fx.play(_fx_host(), "slash", global_position + _lunge_dir * 12.0, {
		"fps": 30.0, "angle": _lunge_dir.angle(), "scale": 0.9, "z_index": 11,
	})


## 显形后的正常受击闪烁要盖掉潜行 look
func _update_animation(delta: float) -> void:
	super._update_animation(delta)
	if _sprite == null:
		return
	if hit_flash_timer > 0.0:
		_sprite.modulate = Color(2.3, 1.7, 1.7, 1.0)
	elif phase == Phase.STALK:
		_apply_stalk_look()
	elif phase == Phase.REVEAL:
		# 显形前摇：从半透明渐亮，配合红光逼玩家做决定
		var t: float = 1.0 - clampf(phase_timer / maxf(reveal_duration(), 0.01), 0.0, 1.0)
		_sprite.modulate = Color(1, 1, 1, lerpf(HIDDEN_ALPHA, 1.0, t))
		if _glow != null:
			_glow.modulate = Color(1.0, 0.4, 0.3, 0.25 + 0.4 * t)
	else:
		_sprite.modulate = Color(1, 1, 1, 1)
		if _glow != null:
			_glow.modulate = Color(1.0, 0.5, 0.35, 0.3)
