class_name EnemyHexeye
extends Enemy
## EnemyHexeye —— 六目浮灵，远程射击型（M4）。
##
## 行为链：与玩家保持 `preferred_range` 距离（太近后撤、太远跟上、合适距离横向游走）
##         -> 冷却结束且有视线时进入瞄准（停顿 + 脚下红光预警，玩家可侧移躲开）
##         -> 发射 `burst_count` 发敌方弹丸（精英三连发）-> 回到游走。
## 弹丸走通用 Bullet（from_player = false，碰撞层 ENEMY_BULLET，贴图 bullet_e_*）。

## 瞄准时脚下光晕的透明度（基类只给精英做脉动，这里用 glow_boost 覆盖）
const AIM_GLOW_ALPHA: float = 0.42

var aim_timer: float = 0.0
var burst_left: int = 0
var burst_timer: float = 0.0
var rounds_fired: int = 0
var strafe_direction: float = 1.0

var _strafe_flip_timer: float = 1.4


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
	var direction: Vector2 = to_target.normalized() if distance > 0.01 else facing
	facing = direction

	_strafe_flip_timer -= delta
	if _strafe_flip_timer <= 0.0:
		_strafe_flip_timer = _rng.randf_range(1.0, 2.2)
		strafe_direction = -strafe_direction
	var lateral: Vector2 = Vector2(-direction.y, direction.x) * strafe_direction * data.strafe_strength

	var wanted: Vector2 = lateral
	if distance < data.keep_distance_min:
		wanted = -direction * data.move_speed + lateral * 0.4
	elif distance > data.preferred_range * 1.18:
		wanted = direction * data.move_speed + lateral * 0.3
	move_velocity = wanted
	set_state(State.CHASE)

	# 贴脸时先拉开距离再开火（否则会被近战压着打却毫无反应）
	if attack_cooldown <= 0.0 and distance <= data.sight_range \
			and distance >= data.keep_distance_min * 0.7 and _has_line_of_sight():
		_begin_aim()


## 视线检测：被墙体挡住时不开火（避免隔着掩体白给）
func _has_line_of_sight() -> bool:
	if target == null or not is_instance_valid(target) or not is_inside_tree():
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position,
			G.LAYER_WORLD, [get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()


func _begin_aim() -> void:
	set_state(State.ATTACK)
	aim_timer = data.aim_time
	burst_left = maxi(data.burst_count, 1)
	burst_timer = 0.0
	Fx.play(_fx_host(), "ring", global_position + Vector2(0, -4), {
		"fps": 9.0, "scale": 0.6, "z_index": 4, "tint": Color(1.0, 0.45, 0.5, 0.6),
	})
	if _glow != null:
		_glow.modulate = Color(1.0, 0.4, 0.4, AIM_GLOW_ALPHA)
	glow_boost = AIM_GLOW_ALPHA


func _tick_attack(delta: float) -> void:
	if aim_timer > 0.0:
		aim_timer -= delta
		# 瞄准时几乎停住，让预警读得清楚
		move_velocity = Vector2.ZERO
		if _sprite != null:
			var charge: float = 1.0 - clampf(aim_timer / maxf(data.aim_time, 0.01), 0.0, 1.0)
			_sprite.modulate = Color(1.0 + 0.3 * charge, 1.0 - 0.1 * charge, 1.0 - 0.15 * charge, 1.0)
		if aim_timer <= 0.0:
			_fire_one()
		return

	if burst_left > 0:
		burst_timer -= delta
		move_velocity = _keep_distance_velocity() * 0.5
		if burst_timer <= 0.0:
			_fire_one()
		return

	_finish_round()


## 一轮打完：进冷却，恢复正常游走
func _finish_round() -> void:
	attack_cooldown = data.fire_interval
	glow_boost = -1.0
	if _glow != null:
		_glow.modulate.a = 0.0
	if _sprite != null:
		_sprite.modulate = Color.WHITE
	set_state(State.CHASE)


func _fire_one() -> void:
	burst_left -= 1
	burst_timer = data.burst_interval
	rounds_fired += 1
	if _sprite != null:
		_sprite.modulate = Color.WHITE
	if target == null or not is_instance_valid(target):
		return
	var direction: Vector2 = (target.global_position - global_position).normalized()
	var spread: float = deg_to_rad(data.spread_deg)
	var offset_angle: float = 0.0
	if data.burst_count > 1:
		offset_angle = _rng.randf_range(-spread, spread)
	fire_bullet(direction.rotated(offset_angle), data.bullet_damage, data.bullet_speed,
			data.bullet_lifetime, data.bullet_radius)
	AudioMgr.play_sfx(data.sfx_shoot, 0.05, -7.0)
	Fx.play(_fx_host(), "muzzle", _muzzle_position(direction), {
		"fps": 30.0, "angle": direction.angle(), "scale": 0.7, "z_index": 11,
		"tint": Color(1.0, 0.55, 0.5, 0.9),
	})


## 保持交战距离的期望速度（连发间隙用，让它一边打一边微调位置）
func _keep_distance_velocity() -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	var to_target: Vector2 = target.global_position - global_position
	var distance: float = to_target.length()
	var direction: Vector2 = to_target.normalized() if distance > 0.01 else facing
	if distance < data.keep_distance_min:
		return -direction * data.move_speed
	if distance > data.preferred_range * 1.18:
		return direction * data.move_speed
	return Vector2(-direction.y, direction.x) * strafe_direction * data.strafe_strength


## 强击退打断瞄准（本轮作废，进短冷却）
func interrupt() -> void:
	super.interrupt()
	if state != State.ATTACK:
		return
	aim_timer = 0.0
	burst_left = 0
	attack_cooldown = maxf(attack_cooldown, data.fire_interval * 0.6)
	glow_boost = -1.0
	if _glow != null:
		_glow.modulate.a = 0.0
	if _sprite != null:
		_sprite.modulate = Color.WHITE
	set_state(State.STUNNED)
