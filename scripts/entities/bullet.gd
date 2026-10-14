class_name Bullet
extends Area2D
## Bullet —— 通用弹丸（M3）。
##
## 玩家子弹与敌人子弹共用本类，由 from_player 决定阵营与碰撞层。
## 命中判定走「每帧射线扫描」而不是 body_entered 信号：
##   - 高速弹不会隧穿薄墙；
##   - 无头测试里结果确定，不依赖信号派发时机；
##   - 同一条射线同时处理墙体与可受伤目标，按距离取最近者。
##
## 由 Player / Enemy 通过 fire_projectile() 生成，一般不直接 new。

const G := preload("res://scripts/core/game_const.gd")

const DEFAULT_TEXTURE := preload("res://assets/fx/bullet_p_0.png")

## 弹丸数据（可为 null，例如敌人子弹只填字段）
var data: WeaponData
## 自定义弹体贴图（敌人子弹用 bullet_e_*）；非空时优先于 data / 默认贴图
var custom_textures: Array[Texture2D] = []
## 发射者（用于击退方向与「不命中自己」）
var source: Node2D
## 特效挂载层（由发射者注入）。弹体命中后会 queue_free，
## 命中火花必须挂在常驻层上，否则特效随弹体一起消失。
var fx_layer: Node2D
## 飞行速度（像素/秒），含散射后的方向
var fly_velocity: Vector2 = Vector2.RIGHT * 300.0
## 本次命中的伤害与是否暴击（发射时按属性算好）
var damage: float = 1.0
var is_crit: bool = false
## true = 玩家子弹，false = 敌人子弹
var from_player: bool = true
## 穿透剩余次数
var pierce_left: int = 0
## 存活时间
var life: float = 2.0
## 命中判定半径
var radius: float = 3.0
## 追踪强度（0 = 不追踪，越大转向越快）
var homing: float = 0.0
## 命中后爆炸（半径 / 伤害比例）
var explode_radius: float = 0.0
var explode_damage_ratio: float = 0.0
## 拖尾
var trail_enabled: bool = true
var trail_interval: float = 0.05
## 弹体帧闪烁速率（0 = 固定第一帧）
var flicker_fps: float = 0.0
## 贴图缩放
var sprite_scale: float = 1.0
## 已失效标记
var dead: bool = false
# ---------- M9 机制型弹道状态 ----------
## BOOMERANG：是否正在返程
var returning: bool = false
## BOOMERANG：出膛时的出发点（返程终点）
var origin_point: Vector2 = Vector2.ZERO
## RICOCHET：剩余弹跳次数
var ricochet_left: int = 0
## MINE：落地等待敌人踩上来的倒计时
var mine_lifetime: float = 0.0
## MINE：已落地等待敌人踩上
var mine_armed: bool = false
## MINE：飞行时长（秒），到点自动落地布设。必须独立于 `life`：
## `life` 在落地后会被顶长成「已飞时长 + 待发时长」，如果拿它当飞行判据，
## 落地这一帧的 `_age >= life` 就会先把雷销毁。
var mine_flight_time: float = 0.0
## CHAIN / FROST：已命中过的目标，避免同一次连锁反复打同一个
var chain_visited: Array = []
var slow_applied_to: Array = []

var _sprite: Sprite2D
var _age: float = 0.0
var _trail_timer: float = 0.0
var _flicker_timer: float = 0.0
var _frame: int = 0
var _hit_targets: Array = []
var _textures: Array[Texture2D] = []
var _target_mask: int = 0


func _ready() -> void:
	if not custom_textures.is_empty():
		_textures = custom_textures
	elif data != null:
		_textures = data.projectile_textures()
	if _textures.is_empty():
		_textures = [DEFAULT_TEXTURE] as Array[Texture2D]
	life = maxf(life, 0.02)

	collision_layer = G.LAYER_PLAYER_BULLET if from_player else G.LAYER_ENEMY_BULLET
	collision_mask = 0
	monitoring = false
	monitorable = true
	z_index = 6

	_target_mask = G.MASK_PLAYER_BULLET if from_player else G.MASK_ENEMY_BULLET

	_sprite = Sprite2D.new()
	_sprite.texture = _textures[0]
	_sprite.centered = true
	_sprite.scale = Vector2.ONE * maxf(sprite_scale, 0.05)
	add_child(_sprite)
	rotation = fly_velocity.angle()

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = maxf(radius, 1.0)
	shape.shape = circle
	add_child(shape)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_age += delta

	# 布雷：到达飞行时长就落地布设。
	# 这个判断必须排在下面的过期检查**之前**——否则 _age 刚好等于飞行时长时，
	# 全局过期会先把雷销毁，布雷就退化成一次性手雷了。
	if kind() == WeaponData.Kind.MINE and not mine_armed \
			and _age >= maxf(mine_flight_time, 0.05):
		_land_mine()

	if _age >= life:
		_expire()
		return

	# 机制型弹道各自的每帧行为（在位移之前推进，保证时序稳定）
	match kind():
		WeaponData.Kind.BOOMERANG:
			_tick_boomerang(delta)
		WeaponData.Kind.MINE:
			_tick_mine(delta)
		_:
			pass

	if homing > 0.0:
		_steer(delta)

	var origin: Vector2 = global_position
	var target: Vector2 = origin + fly_velocity * delta
	var result: Dictionary = _scan(origin, target)

	if result.is_empty():
		global_position = target
		_advance_visuals(delta)
		_leave_trail(delta)
		return

	var collider: Variant = result.get("collider")
	global_position = result.get("position", target)
	if collider is Node and (collider as Node).has_method("take_hit") and not _hit_targets.has(collider):
		_hit_target(collider as Node, result.get("position", global_position))
	else:
		_impact(result.get("position", global_position), result.get("normal", Vector2.ZERO))


## 当前弹道类型（data 为空时按普通弹处理）
func kind() -> int:
	return int(data.kind) if data != null else WeaponData.Kind.PROJECTILE


# ==================== M9 机制型弹道 ====================

## 回旋镖：飞出一段后反向飞回发射点。去程与返程都能命中，
## 返程刻意**允许**再次命中同一批目标（每段各挨一次），这是它与普通弹的核心差异。
func _tick_boomerang(delta: float) -> void:
	if returning:
		if global_position.distance_to(origin_point) <= maxf(fly_velocity.length() * delta, 6.0):
			_expire()
		return
	# 去程走了总寿命的一半左右就掉头，避免"扔出去就回不来"
	if _age >= life * 0.45:
		returning = true
		fly_velocity = (origin_point - global_position).normalized() \
				* fly_velocity.length() * maxf(data.return_speed, 0.2)
		rotation = fly_velocity.angle()
		Fx.play(_fx_host(), "spark", global_position, {
			"fps": 26.0, "scale": 0.7, "z_index": 6, "tint": Color(1.0, 0.9, 0.6, 0.8),
		})


## 布雷：飞行途中落地布设，落地后静止等待敌人踩上
## 布雷：先飞一小段（"撒"出去），然后落地静止等待敌人踩上。
##
## 生命周期分两段，这是最容易写错的地方：
##   飞行段 —— 由 `life`（= bullet_lifetime）控制，到点自动落地布设；
##   待发段 —— 由 `mine_lifetime` 控制，**必须同时把 `life` 顶长**，
##             否则全局的 `_age >= life` 检查会在布设后 0.5 秒就把雷销毁，
##             `mine_lifetime` 形同虚设（雷退化成一次性手雷）。
func _tick_mine(delta: float) -> void:
	if not mine_armed:
		return
	mine_lifetime -= delta
	if mine_lifetime <= 0.0:
		_expire()
		return
	# 只认敌人：玩家不会踩到自己的雷
	if CombatUtil.nearest_target(self, global_position, CombatUtil.GROUP_ENEMIES,
			maxf(data.mine_trigger_range, 12.0)) != null:
		_detonate_mine()


func _detonate_mine() -> void:
	mine_armed = false
	AudioMgr.play_sfx("explode_small", 0.04)
	Fx.play(_fx_host(), "explode", global_position, {
		"fps": 22.0, "scale": maxf(data.mine_explosion_radius / 26.0, 0.9), "z_index": 12,
	})
	CombatUtil.area_damage(self, global_position, data.mine_explosion_radius, damage, false,
			data.knockback, _source_id(),
			G.LAYER_ENEMY if from_player else G.LAYER_PLAYER, [source])
	EventBus.explosion_occurred.emit(global_position, data.mine_explosion_radius)
	_destroy()


## 追踪转向（魔杖）：朝最近可受伤目标偏转
func _steer(delta: float) -> void:
	if not is_inside_tree():
		return
	var group: String = CombatUtil.GROUP_ENEMIES if from_player else CombatUtil.GROUP_PLAYER
	var nearest: Node2D = CombatUtil.nearest_target(self, global_position, group, 240.0, source)
	if nearest == null:
		return
	var wanted: Vector2 = (nearest.global_position - global_position).normalized()
	var speed: float = fly_velocity.length()
	fly_velocity = fly_velocity.normalized().slerp(wanted, clampf(homing * delta, 0.0, 1.0)) * speed
	rotation = fly_velocity.angle()


func _scan(origin: Vector2, target: Vector2) -> Dictionary:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space_state == null:
		return {}
	var step: float = maxf(radius * 2.0, 8.0)
	var delta_pos: Vector2 = target - origin
	var dist: float = delta_pos.length()
	if dist <= step:
		var query := PhysicsRayQueryParameters2D.create(origin, target, _target_mask, [get_rid()])
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.hit_from_inside = true
		return space_state.intersect_ray(query)
	var direction: Vector2 = delta_pos.normalized()
	var steps: int = int(ceilf(dist / step))
	var best_result: Dictionary = {}
	var best_dist: float = 1e9
	for i: int in range(steps):
		var from: Vector2 = origin + direction * step * float(i)
		var to: Vector2 = origin + direction * step * float(i + 1)
		if i == steps - 1:
			to = target
		var query := PhysicsRayQueryParameters2D.create(from, to, _target_mask, [get_rid()])
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.hit_from_inside = true
		var result: Dictionary = space_state.intersect_ray(query)
		if not result.is_empty():
			var hit_pos: Vector2 = result.get("position", to)
			var d: float = origin.distance_squared_to(hit_pos)
			if d < best_dist:
				best_dist = d
				best_result = result
	return best_result


func _hit_target(target: Node, hit_position: Vector2) -> void:
	_hit_targets.append(target)
	var knockback_force: float = data.knockback if data != null else 0.0
	CombatUtil.apply_hit(target, damage, is_crit, fly_velocity.normalized() * knockback_force,
			_source_id())
	_spawn_hit_fx(hit_position)
	AudioMgr.play_sfx("hit_crit" if is_crit else "hit_flesh", 0.05)

	# 机制型弹道的命中分支
	match kind():
		WeaponData.Kind.CHAIN:
			_jump_chain(target, hit_position)
			_destroy()
			return
		WeaponData.Kind.FROST:
			_apply_slow(target)
			_destroy()
			return
		WeaponData.Kind.BOOMERANG:
			# 回旋镖不消失：去程命中后继续飞，返程再撞一次
			_hit_targets.clear()
			return
		WeaponData.Kind.MINE:
			_land_mine()
			return
		_:
			pass

	# Explosive projectile: detonate on enemy hit
	if explode_radius > 0.0:
		_explode(hit_position)
		_destroy()
		return

	if pierce_left > 0:
		pierce_left -= 1
		return
	_destroy()


## 链式闪电：从命中的目标继续往最近的未访问敌人跳，每跳一次伤害衰减
func _jump_chain(from_target: Node, from_position: Vector2) -> void:
	if data == null:
		return
	chain_visited.append(from_target)
	var jump_damage: float = damage
	var current: Vector2 = from_position
	var group: String = CombatUtil.GROUP_ENEMIES if from_player else CombatUtil.GROUP_PLAYER
	for hop: int in range(maxi(data.chain_targets - 1, 0)):
		jump_damage *= clampf(data.chain_falloff, 0.1, 1.0)
		var next_target: Node2D = _nearest_unvisited(current, group, data.chain_range)
		if next_target == null:
			break
		chain_visited.append(next_target)
		CombatUtil.apply_hit(next_target, jump_damage, is_crit, Vector2.ZERO, _source_id())
		# 两点之间画一道电弧
		Fx.single(_fx_host(), "glow_soft_blue", (current + next_target.global_position) * 0.5, {
			"life": 0.14, "scale": 1.4, "z_index": 13, "tint": Color(0.7, 0.9, 1.0, 0.9),
		})
		AudioMgr.play_sfx("hit_flesh", 0.02, -12.0)
		current = next_target.global_position


func _nearest_unvisited(from: Vector2, group: String, max_distance: float) -> Node2D:
	var best: Node2D = null
	var best_distance: float = maxf(max_distance, 1.0)
	for node: Node in get_tree().get_nodes_in_group(group):
		if not (node is Node2D) or not is_instance_valid(node) or chain_visited.has(node):
			continue
		if node.has_method("is_dead_or_disabled") and bool(node.call("is_dead_or_disabled")):
			continue
		var distance: float = (node as Node2D).global_position.distance_to(from)
		if distance <= best_distance:
			best_distance = distance
			best = node as Node2D
	return best


## 减速：给敌人挂一段时间的减速（同一个目标不重复叠加）
func _apply_slow(target: Node) -> void:
	if data == null or not is_instance_valid(target):
		return
	if slow_applied_to.has(target):
		return
	slow_applied_to.append(target)
	if not target.has_method("apply_slow"):
		return
	target.call("apply_slow", clampf(data.slow_factor, 0.05, 1.0), maxf(data.slow_duration, 0.1))
	Fx.single(_fx_host(), "glow_soft_blue", (target as Node2D).global_position, {
		"life": 0.3, "scale": 1.0, "z_index": 12, "tint": Color(0.5, 0.85, 1.0, 0.7),
	})


## 布雷落地：静止布设，开始等待敌人
func _land_mine() -> void:
	if mine_armed:
		return
	mine_armed = true
	mine_lifetime = maxf(data.mine_lifetime, 0.5)
	# 关键：把总寿命顶到「已飞行时长 + 待发时长」，
	# 否则 _physics_process 开头的 `_age >= life` 会在布设后立刻销毁这颗雷
	life = _age + mine_lifetime
	fly_velocity = Vector2.ZERO
	rotation = 0.0
	set_physics_process(true)
	# 落地后不再靠 _scan 判定（碰撞全关），改由「每帧查最近敌人」引爆
	collision_layer = 0
	collision_mask = 0
	if _sprite != null:
		_sprite.modulate = Color(0.9, 1.0, 0.9, 0.9)
		_sprite.scale = Vector2.ONE * 0.8
	Fx.single(_fx_host(), "glow_soft_blue", global_position, {
		"life": 0.25, "scale": 0.8, "z_index": 5, "tint": Color(0.7, 1.0, 0.6, 0.6),
	})


## 撞墙：弹跳弹消耗一次次数并按法线反射，其余弹种照旧消失
func _impact(hit_position: Vector2, normal: Vector2) -> void:
	if kind() == WeaponData.Kind.RICOCHET and ricochet_left > 0:
		ricochet_left -= 1
		# 沿墙面切向反射（法线为 0 时原路弹回，保证不会卡死）
		var bounce: Vector2 = -fly_velocity.normalized().reflect(normal) if normal.length() > 0.01 \
				else -fly_velocity.normalized()
		fly_velocity = bounce.normalized() * fly_velocity.length()
		rotation = fly_velocity.angle()
		global_position = hit_position + bounce * 2.0
		AudioMgr.play_sfx("hit_wall", 0.03, -10.0)
		Fx.play(_fx_host(), "spark", hit_position, {"angle": bounce.angle(), "z_index": 8})
		return
	if kind() == WeaponData.Kind.MINE:
		_land_mine()
		return
	if explode_radius > 0.0:
		_explode(hit_position)
	else:
		AudioMgr.play_sfx("hit_wall", 0.06)
		Fx.play(_fx_host(), "spark", hit_position, {"angle": normal.angle(), "z_index": 8})
		Fx.play(_fx_host(), "hit", hit_position, {"fps": 26.0, "scale": 0.8, "z_index": 8})
	_destroy()


func _expire() -> void:
	Fx.play(_fx_host(), "smoke", global_position, {"fps": 18.0, "scale": 0.6, "z_index": 5})
	_destroy()


func _spawn_hit_fx(hit_position: Vector2) -> void:
	Fx.play(_fx_host(), "hit", hit_position, {"fps": 26.0, "scale": 0.9, "z_index": 9})


func _explode(hit_position: Vector2) -> void:
	AudioMgr.play_sfx("explode_big" if explode_radius >= 50.0 else "explode_small", 0.05)
	Fx.play(_fx_host(), "explode", hit_position, {
		"fps": 22.0, "scale": maxf(explode_radius / 26.0, 0.8), "z_index": 12,
	})
	CombatUtil.area_damage(self, hit_position, explode_radius, damage * explode_damage_ratio, false,
			(data.knockback if data != null else 60.0) * 1.6, _source_id(),
			G.LAYER_ENEMY if from_player else G.LAYER_PLAYER, [source])
	EventBus.explosion_occurred.emit(hit_position, explode_radius)


## 伤害归属：优先记发射者（玩家/敌人），弹体自身 id 只在无源时兜底
func _source_id() -> int:
	if source != null and is_instance_valid(source):
		return source.get_instance_id()
	return get_instance_id()


## 特效宿主：优先常驻特效层，其次弹道层（弹体本身会被立即释放，不能当宿主）
func _fx_host() -> Node:
	if fx_layer != null and is_instance_valid(fx_layer):
		return fx_layer
	var parent: Node = get_parent()
	return parent if parent != null else self


func _advance_visuals(delta: float) -> void:
	if flicker_fps <= 0.0 or _textures.size() < 2:
		return
	_flicker_timer += delta
	if _flicker_timer < 1.0 / flicker_fps:
		return
	_flicker_timer = 0.0
	_frame = (_frame + 1) % _textures.size()
	_sprite.texture = _textures[_frame]


func _leave_trail(delta: float) -> void:
	if not trail_enabled:
		return
	_trail_timer -= delta
	if _trail_timer > 0.0:
		return
	_trail_timer = trail_interval
	var parent: Node = get_parent()
	if parent == null or _textures.is_empty():
		return
	Fx.play_frames(parent, [_textures[0]] as Array[Texture2D], global_position, {
		"fps": 6.0, "fade": true, "z_index": 2, "scale": sprite_scale * 0.85,
		"angle": rotation, "tint": Color(1, 1, 1, 0.5),
	})


func _destroy() -> void:
	if dead:
		return
	dead = true
	set_physics_process(false)
	queue_free()
