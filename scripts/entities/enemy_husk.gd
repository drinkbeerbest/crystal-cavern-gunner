class_name EnemyHusk
extends Enemy
## EnemyHusk —— 晶壳行者，近战冲锋型（M4）。
##
## 行为链：追踪 -> 进入起手距离后原地蓄力（后拉 + 预警环 + 变红，给玩家反应时间）
##         -> 沿**锁定的方向**高速冲刺 -> 撞到玩家造成撞击伤害与强击退 -> 冷却后回到追踪。
## 冲刺中撞到墙会眩晕 `charge_stun_on_wall` 秒，这是玩家的主要反打窗口；
## 足够强的击退（>= Enemy.INTERRUPT_KNOCKBACK）也能打断起手或冲刺。

## 冲刺拖尾的生成间隔
const TRAIL_INTERVAL: float = 0.045
## 冲刺命中判定余量（配合 body_radius）
const CHARGE_HIT_PADDING: float = 12.0

var charge_direction: Vector2 = Vector2.ZERO
var windup_timer: float = 0.0
var charge_timer: float = 0.0
var charges_done: int = 0
var wall_stuns: int = 0
var charge_hits: int = 0

var _hit_this_charge: bool = false
var _trail_timer: float = 0.0


func _think(delta: float) -> void:
	if state == State.ATTACK:
		_tick_attack(delta)
		return
	_refresh_target()
	if target == null:
		super._think(delta)
		return
	var to_target: Vector2 = target.global_position - global_position
	var distance: float = to_target.length()
	if distance > 0.01:
		facing = to_target.normalized()
	set_state(State.CHASE)
	move_velocity = facing * data.move_speed
	if distance <= data.charge_trigger_range and attack_cooldown <= 0.0:
		_begin_windup()


func _begin_windup() -> void:
	set_state(State.ATTACK)
	windup_timer = data.charge_windup
	charge_timer = 0.0
	charge_direction = facing
	_hit_this_charge = false
	AudioMgr.play_sfx(data.sfx_attack, 0.03, -5.0)
	Fx.play(_fx_host(), "ring", global_position, {
		"fps": 11.0, "scale": 0.75, "z_index": 4, "tint": Color(1.0, 0.5, 0.38, 0.6),
	})
	Fx.play(_fx_host(), "dust", global_position + Vector2(0, 5), {"fps": 16.0, "scale": 0.8, "z_index": 4})


func _tick_attack(delta: float) -> void:
	if windup_timer > 0.0:
		windup_timer -= delta
		# 后拉蓄势：视觉上"缩回去"，随后猛冲（方向已在起手时锁定）
		move_velocity = -charge_direction * data.move_speed * 0.3
		if _sprite != null:
			var tension: float = 1.0 - clampf(windup_timer / maxf(data.charge_windup, 0.01), 0.0, 1.0)
			_sprite.modulate = Color(1.0 + 0.55 * tension, 0.85 - 0.2 * tension, 0.8 - 0.25 * tension, 1.0)
		if windup_timer <= 0.0:
			_launch_charge()
		return

	if charge_timer > 0.0:
		charge_timer -= delta
		move_velocity = charge_direction * data.charge_speed
		_leave_trail(delta)
		_try_charge_hit()
		if charge_timer <= 0.0:
			_end_charge(false)
		return

	_end_charge(false)


func _launch_charge() -> void:
	windup_timer = 0.0
	charge_timer = data.charge_duration
	attacks_made += 1
	charges_done += 1
	_hit_this_charge = false
	_trail_timer = 0.0
	facing = charge_direction
	# 起手当帧就给满冲刺速度：_tick_attack 的蓄力分支随后 return，
	# 若不在这里改写位移意图，基类会再用上一帧的"后拉"速度位移一格，冲刺起手会迟一拍
	move_velocity = charge_direction * data.charge_speed
	if _sprite != null:
		_sprite.modulate = Color(1.35, 0.95, 0.85, 1.0)
		_sprite.flip_h = charge_direction.x < 0.0
	AudioMgr.play_sfx("dash", 0.05, -3.0)
	Fx.play(_fx_host(), "dust", global_position + Vector2(0, 5), {"fps": 22.0, "scale": 1.0, "z_index": 5})


## 位移之后的修正：锁定冲刺朝向（后拉位移会把 facing 反向），以及撞墙眩晕判定
func _post_move(_delta: float) -> void:
	if state != State.ATTACK:
		return
	if windup_timer > 0.0:
		facing = charge_direction
		if _sprite != null:
			_sprite.flip_h = charge_direction.x < 0.0
		return
	if charge_timer > 0.0:
		facing = charge_direction
		if last_collided_wall:
			_end_charge(true)


func _try_charge_hit() -> void:
	if _hit_this_charge or target == null or not is_instance_valid(target):
		return
	var distance: float = global_position.distance_to(target.global_position)
	if distance > data.body_radius + CHARGE_HIT_PADDING:
		return
	_hit_this_charge = true
	charge_hits += 1
	if damage_target(data.charge_damage, charge_direction * data.charge_knockback):
		AudioMgr.play_sfx("hit_flesh", 0.07)
		EventBus.request_screen_shake.emit(2.6, 0.16)
		Fx.play(_fx_host(), "hit", target.global_position, {"fps": 26.0, "scale": 1.0, "z_index": 12})


func _end_charge(hit_wall: bool) -> void:
	var was_charging: bool = charge_timer > 0.0
	windup_timer = 0.0
	charge_timer = 0.0
	move_velocity = Vector2.ZERO
	attack_cooldown = data.charge_cooldown
	if _sprite != null:
		_sprite.modulate = Color.WHITE
	if hit_wall and was_charging:
		wall_stuns += 1
		stun(data.charge_stun_on_wall)
		AudioMgr.play_sfx("hit_wall", 0.05)
		Fx.play(_fx_host(), "dust", global_position + charge_direction * 8.0, {
			"fps": 20.0, "scale": 1.1, "z_index": 6,
		})
		set_state(State.STUNNED)
		return
	set_state(State.CHASE)


func _leave_trail(delta: float) -> void:
	_trail_timer -= delta
	if _trail_timer > 0.0:
		return
	_trail_timer = TRAIL_INTERVAL
	Fx.single(_fx_host(), "dash_trail", global_position + data.sprite_offset, {
		"z_index": 1, "scale": 0.9, "fade": true, "tint": Color(1.0, 0.62, 0.45, 0.55),
	})


## 强击退可打断起手与冲刺
func interrupt() -> void:
	super.interrupt()
	if state != State.ATTACK:
		return
	if charge_timer > 0.0:
		_end_charge(false)
		return
	windup_timer = 0.0
	attack_cooldown = maxf(attack_cooldown, data.charge_cooldown * 0.5)
	if _sprite != null:
		_sprite.modulate = Color.WHITE
	set_state(State.STUNNED)
