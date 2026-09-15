class_name Enemy
extends CharacterBody2D
## Enemy —— 敌人基类（M4）。
##
## 负责所有敌人共有的部分：
##   1. 生存与受击契约（`take_hit`，与 Player / TrainingDummy 同一份约定）；
##   2. 状态机骨架 DORMANT -> IDLE/CHASE -> ATTACK -> STUNNED -> DEAD，子类只写 `_think()`；
##   3. 移动与避障：`move_and_slide()` + 同类分离力，保证敌人不会叠成一坨；
##   4. 击退、受击闪白、硬直打断（大击退可打断冲锋/瞄准）、死亡动画与自动释放；
##   5. 掉落钩子：死亡时 `EnemyData.roll_drops()` 摇奖并通过 EventBus.enemy_dropped 交给世界层。
##
## 子类（husk / hexeye / bloom）只需覆写 `_think(delta)` 与少量钩子，
## 通过 `move_velocity` 表达"这一帧想去哪"，位移与碰撞统一由基类执行。

const G := preload("res://scripts/core/game_const.gd")

enum State { DORMANT, IDLE, CHASE, ATTACK, STUNNED, DEAD }

const STATE_NAMES: Array[String] = ["dormant", "idle", "chase", "attack", "stunned", "dead"]

const HIT_FLASH_TIME: float = 0.12
const KNOCKBACK_DECAY: float = 900.0
## 击退强度超过该值才算"打断动作"（避免被小手枪点一下就永远冲不了锋）
const INTERRUPT_KNOCKBACK: float = 150.0
## 接触伤害判定余量（像素）
const CONTACT_PADDING: float = 4.0
## 状态日志保留条数（测试观测用）
const STATE_LOG_LIMIT: int = 40

var data: EnemyData = null
var max_health: float = 1.0
var health: float = 1.0
var state: State = State.DORMANT
var activated: bool = false
var dead: bool = false
var facing: Vector2 = Vector2.DOWN
var target: Node2D = null

## 由世界/生成器注入（敌人子弹与特效必须挂在常驻层上）
var bullet_layer: Node2D = null
var fx_layer: Node2D = null
## 由世界层注入（Boss 召唤小怪等需要反向 spawn 的入口）
var world_node: Node2D = null
## 死亡动画结束后是否自动释放（测试里设 false，便于断言死亡后的状态）
var auto_free: bool = true

# ---------- 计时器 ----------
var activate_timer: float = G.ENEMY_ACTIVATE_DELAY
var attack_cooldown: float = 0.0
var contact_cooldown_timer: float = 0.0
var stun_timer: float = 0.0
var hit_flash_timer: float = 0.0
var death_timer: float = -1.0
var anim_time: float = 0.0
var state_time: float = 0.0

# ---------- 运动 ----------
## 子类每帧写入的期望速度（基类叠加分离力与击退后执行位移）
var move_velocity: Vector2 = Vector2.ZERO
## 击退等外部冲量，按 KNOCKBACK_DECAY 衰减
var external_velocity: Vector2 = Vector2.ZERO
## 上一帧 move_and_slide 是否撞到墙
var last_collided_wall: bool = false
var separation_force: Vector2 = Vector2.ZERO
## 子类临时提升脚下光晕（远程怪瞄准预警用）：>=0 覆盖默认脉动，-1 表示用默认
var glow_boost: float = -1.0

# ---------- 测试可观测计数 ----------
var hit_count: int = 0
var crit_count: int = 0
var total_damage: float = 0.0
var last_knockback: Vector2 = Vector2.ZERO
var last_source_id: int = 0
var attacks_made: int = 0
var bullets_fired: int = 0
var damage_dealt: float = 0.0
var explosions: int = 0
var interrupts: int = 0
var death_drops: Array = []
var state_log: Array[String] = []
var last_state: State = State.DORMANT

var _sprite: Sprite2D
var _glow: Sprite2D
var _collision: CollisionShape2D
var _frames: Array[Texture2D] = []
var _frame_index: int = 0
var _rng := RandomNumberGenerator.new()
var _wander_timer: float = 0.0
var _wander_direction: Vector2 = Vector2.ZERO

static var _enemy_bullet_textures: Array[Texture2D] = []


# ==================== 装配 ====================

## 在 add_child 之前调用，注入数值表
func configure(enemy_data: EnemyData) -> void:
	data = enemy_data
	if data == null:
		data = EnemyData.new()
	max_health = data.max_health
	health = max_health


func _ready() -> void:
	if data == null:
		data = EnemyData.new()
		max_health = data.max_health
		health = max_health
	add_to_group(CombatUtil.GROUP_ENEMIES)
	collision_layer = G.LAYER_ENEMY
	collision_mask = G.MASK_ENEMY
	_rng.seed = hash(String(data.id) + str(GameState.run_seed) + str(get_instance_id()))
	_build_nodes()
	state_log.append(STATE_NAMES[State.DORMANT])
	EventBus.enemy_spawned.emit(self)


func _build_nodes() -> void:
	_collision = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = maxf(data.body_radius, 3.0)
	_collision.shape = circle
	_collision.position = Vector2(0, 2)
	add_child(_collision)

	_frames = data.frames()

	_glow = Sprite2D.new()
	_glow.texture = Fx.texture("glow_soft_blue" if not data.is_elite() else "glow_hard")
	_glow.centered = true
	_glow.scale = Vector2.ONE * (0.5 if not data.is_elite() else 0.62)
	_glow.modulate = Color(1.0, 0.45, 0.4, 0.0) if not data.is_elite() else Color(1.0, 0.75, 0.35, 0.0)
	_glow.z_index = -1
	_glow.position = data.sprite_offset
	add_child(_glow)

	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.position = data.sprite_offset
	if not _frames.is_empty():
		_sprite.texture = _frames[0]
	add_child(_sprite)


## 立即进入战斗状态（生成器在波次开始或玩家靠近时调用）
func activate() -> void:
	if activated or dead:
		return
	activated = true
	activate_timer = 0.0
	_refresh_target()
	Fx.play(_fx_host(), "dust", global_position + Vector2(0, 4), {"fps": 18.0, "scale": 0.9, "z_index": 5})
	set_state(State.CHASE if target != null else State.IDLE)


func set_target(node: Node2D) -> void:
	target = node


# ==================== 主循环 ====================

func _physics_process(delta: float) -> void:
	if dead:
		_tick_death(delta)
		return

	_tick_timers(delta)

	if not activated:
		activate_timer -= delta
		# 凝聚登场：轻微上下浮动 + 淡入
		_sprite.modulate.a = clampf(1.0 - activate_timer / maxf(G.ENEMY_ACTIVATE_DELAY, 0.01), 0.15, 1.0)
		move_velocity = Vector2.ZERO
		_apply_movement(delta)
		_update_animation(delta)
		if activate_timer <= 0.0:
			activate()
		return

	if stun_timer > 0.0:
		move_velocity = Vector2.ZERO
		if state != State.STUNNED:
			set_state(State.STUNNED)
	elif state == State.STUNNED:
		set_state(State.CHASE if target != null else State.IDLE)

	if state != State.STUNNED:
		_think(delta)

	_apply_movement(delta)
	_post_move(delta)
	_tick_contact_damage()
	_update_animation(delta)


## 子类 AI：读 `target`，写 `move_velocity` / 状态 / 计时器
func _think(_delta: float) -> void:
	_refresh_target()
	if target == null:
		_wander(_delta)
		return
	var to_target: Vector2 = target.global_position - global_position
	facing = to_target.normalized() if to_target.length_squared() > 0.01 else facing
	set_state(State.CHASE)
	move_velocity = facing * data.move_speed


## 位移执行：期望速度 + 分离力 + 击退冲量
func _apply_movement(delta: float) -> void:
	separation_force = _compute_separation()
	velocity = move_velocity + separation_force + external_velocity
	last_collided_wall = false
	move_and_slide()
	last_collided_wall = is_on_wall()
	external_velocity = external_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	if velocity.length_squared() > 1.0:
		var dominant: Vector2 = move_velocity if move_velocity.length_squared() > 0.01 else velocity
		facing = dominant.normalized()
		if absf(facing.x) > 0.05 and _sprite != null:
			_sprite.flip_h = facing.x < 0.0


## 子类钩子：位移之后（用于撞墙眩晕、冲刺命中等判定）
func _post_move(_delta: float) -> void:
	pass


## 贴脸接触伤害：近战怪的持续压迫感，按 contact_cooldown 节流
func _tick_contact_damage() -> void:
	if contact_cooldown_timer > 0.0 or data.contact_damage <= 0.0:
		return
	if target == null or not is_instance_valid(target) or _target_is_dead():
		return
	var reach: float = data.body_radius + CONTACT_PADDING + _body_radius_of(target)
	if global_position.distance_to(target.global_position) > reach:
		return
	var push: Vector2 = (target.global_position - global_position).normalized() * 90.0
	if damage_target(data.contact_damage, push):
		contact_cooldown_timer = data.contact_cooldown
		AudioMgr.play_sfx("hit_flesh", _rng.randf_range(-0.04, 0.04), -8.0)
		Fx.play(_fx_host(), "hit", target.global_position, {"fps": 24.0, "scale": 0.75, "z_index": 12})


func _tick_timers(delta: float) -> void:
	state_time += delta
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	contact_cooldown_timer = maxf(contact_cooldown_timer - delta, 0.0)
	stun_timer = maxf(stun_timer - delta, 0.0)
	if hit_flash_timer > 0.0:
		hit_flash_timer = maxf(hit_flash_timer - delta, 0.0)
		_apply_flash()


func _apply_flash() -> void:
	if _sprite == null:
		return
	if hit_flash_timer > 0.0:
		_sprite.modulate = Color(2.3, 1.7, 1.7, 1.0)
	else:
		_sprite.modulate = Color(1, 1, 1, 1.0)


func _update_animation(delta: float) -> void:
	if _frames.size() < 2 or _sprite == null:
		return
	var moving: bool = move_velocity.length_squared() > 1.0
	var fps: float = data.anim_fps * (1.0 if moving else 0.55)
	anim_time += delta * fps
	var index: int = int(anim_time) % _frames.size()
	if index != _frame_index:
		_frame_index = index
		_sprite.texture = _frames[_frame_index]
	if _glow != null:
		if glow_boost >= 0.0:
			_glow.modulate.a = glow_boost
		else:
			_glow.modulate.a = 0.0 if not data.is_elite() else 0.16 + 0.08 * sin(anim_time * 1.6)


## 没有目标时的小范围游荡（避免敌人僵在原地像贴图）
func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = _rng.randf_range(0.9, 2.2)
		_wander_direction = Vector2.RIGHT.rotated(_rng.randf() * TAU) if _rng.randf() > 0.25 else Vector2.ZERO
	set_state(State.IDLE if _wander_direction.length_squared() < 0.01 else State.CHASE)
	move_velocity = _wander_direction * data.move_speed * 0.45


func _refresh_target() -> void:
	if target != null and is_instance_valid(target) and not _target_is_dead():
		return
	var found: Node2D = CombatUtil.nearest_target(self, global_position, CombatUtil.GROUP_PLAYER, data.sight_range)
	target = found


func _target_is_dead() -> bool:
	if target == null or not is_instance_valid(target):
		return true
	if target.has_method("is_dead_or_disabled"):
		return bool(target.call("is_dead_or_disabled"))
	return false


# ==================== 受击 / 死亡 ====================

## 受击契约（CombatUtil.apply_hit 调用）
func take_hit(amount: float, is_crit: bool, knockback: Vector2, source: int) -> void:
	if dead:
		return
	hit_count += 1
	last_knockback = knockback
	last_source_id = source
	if is_crit:
		crit_count += 1

	var damage: float = maxf(amount - data.armor, 1.0)
	total_damage += damage
	health = maxf(health - damage, 0.0)
	hit_flash_timer = HIT_FLASH_TIME
	_apply_flash()
	queue_redraw()

	if knockback.length_squared() > 0.01:
		var resist: float = clampf(data.knockback_resist, 0.0, 0.9)
		external_velocity += knockback * (1.0 - resist)
		if knockback.length() >= INTERRUPT_KNOCKBACK:
			interrupt()

	AudioMgr.play_sfx(data.sfx_hurt, _rng.randf_range(-0.05, 0.05), -4.0)
	EventBus.enemy_hurt.emit(self, damage, is_crit)

	if health <= 0.0:
		die()


## 打断当前动作（冲锋/瞄准/蓄力）。子类可覆写；自爆怪默认不可打断。
func interrupt() -> void:
	interrupts += 1
	stun_timer = maxf(stun_timer, G.ENEMY_FLINCH_TIME)


## 死亡：先给子类一次"临终动作"（自爆），再结算掉落与表现
func die() -> void:
	if dead:
		return
	# 先置 dead 再执行临终动作：自爆怪在 _on_before_death() 里会走 explode() -> die()，
	# 若不先置位就会递归，导致掉落表与 enemy_died 事件被结算两次
	dead = true
	health = 0.0
	_on_before_death()
	last_state = state
	set_state(State.DEAD)
	velocity = Vector2.ZERO
	move_velocity = Vector2.ZERO
	external_velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	contact_cooldown_timer = 999.0

	death_drops = data.roll_drops(_rng, _luck())
	AudioMgr.play_sfx(data.sfx_die, _rng.randf_range(-0.06, 0.06))
	Fx.play(_fx_host(), "explode" if data.archetype == EnemyData.Archetype.BOMBER else "hit",
			global_position + data.sprite_offset, {"fps": 22.0, "scale": 0.9, "z_index": 12})
	Fx.scatter(_fx_host(), "spark", global_position + data.sprite_offset, 3, 14.0, {"fps": 24.0, "z_index": 12})
	GameState.register_kill(data.score, data.is_elite())
	EventBus.enemy_died.emit(self, global_position)
	EventBus.enemy_dropped.emit(self, global_position, death_drops)
	death_timer = G.ENEMY_DEATH_ANIM_TIME
	queue_redraw()


func _on_before_death() -> void:
	pass


func _tick_death(delta: float) -> void:
	if death_timer < 0.0:
		return
	death_timer -= delta
	var ratio: float = clampf(death_timer / maxf(G.ENEMY_DEATH_ANIM_TIME, 0.01), 0.0, 1.0)
	if _sprite != null:
		_sprite.scale = Vector2.ONE * lerpf(0.35, 1.0, ratio)
		_sprite.modulate = Color(1.0, 1.0, 1.0, ratio)
		_sprite.rotation = lerpf(0.5, 0.0, ratio)
	if _glow != null:
		_glow.modulate.a = 0.0
	if death_timer <= 0.0:
		death_timer = -1.0
		if auto_free:
			queue_free()


func _luck() -> float:
	return float(GameState.stats.get("luck", 0.0))


func is_dead_or_disabled() -> bool:
	return dead


## 造成伤害给当前目标（接触/冲锋/爆炸共用），返回是否命中
func damage_target(amount: float, knockback: Vector2, is_crit: bool = false) -> bool:
	if target == null or not is_instance_valid(target) or amount <= 0.0:
		return false
	var applied: bool = CombatUtil.apply_hit(target, amount, is_crit, knockback, get_instance_id())
	if applied:
		damage_dealt += amount
	return applied


# ==================== 敌人子弹 ====================

## 发射一枚敌方弹丸（默认使用 bullet_e_* 贴图）
func fire_bullet(direction: Vector2, damage: float, speed: float, lifetime: float = 2.4,
		radius: float = 4.0, textures: Array[Texture2D] = []) -> Bullet:
	var bullet := Bullet.new()
	bullet.data = null
	bullet.source = self
	bullet.fx_layer = fx_layer
	bullet.from_player = false
	bullet.custom_textures = textures if not textures.is_empty() else enemy_bullet_textures()
	bullet.fly_velocity = direction.normalized() * maxf(speed, 40.0)
	bullet.damage = damage
	bullet.is_crit = false
	bullet.pierce_left = 0
	bullet.life = lifetime
	bullet.radius = maxf(radius, 2.0)
	bullet.sprite_scale = 1.0
	bullet.trail_enabled = true
	bullet.trail_interval = 0.06
	bullet.flicker_fps = 14.0 if bullet.custom_textures.size() > 1 else 0.0
	bullet.position = _muzzle_position(direction)
	var host: Node2D = _bullet_host()
	host.add_child(bullet)
	if bullet.global_position != bullet.position:
		bullet.global_position = _muzzle_position(direction)
	bullets_fired += 1
	return bullet


static func enemy_bullet_textures() -> Array[Texture2D]:
	if _enemy_bullet_textures.is_empty():
		for frame_name: String in ["bullet_e_0", "bullet_e_1"]:
			var tex: Texture2D = Fx.texture(frame_name)
			if tex != null:
				_enemy_bullet_textures.append(tex)
	return _enemy_bullet_textures


## 释放静态贴图缓存（退出前调用，避免 "resources still in use at exit"）
static func clear_cache() -> void:
	_enemy_bullet_textures.clear()


func _muzzle_position(direction: Vector2) -> Vector2:
	return global_position + direction.normalized() * (data.body_radius + 6.0) + Vector2(0, -4)


func _bullet_host() -> Node2D:
	if bullet_layer != null and is_instance_valid(bullet_layer):
		return bullet_layer
	var parent: Node = get_parent()
	return parent as Node2D if parent is Node2D else self


func _fx_host() -> Node2D:
	if fx_layer != null and is_instance_valid(fx_layer):
		return fx_layer
	return _bullet_host()


# ==================== 分离力（不互相重叠） ====================

func _compute_separation() -> Vector2:
	if not is_inside_tree():
		return Vector2.ZERO
	var force: Vector2 = Vector2.ZERO
	var my_radius: float = data.body_radius
	for node: Node in get_tree().get_nodes_in_group(CombatUtil.GROUP_ENEMIES):
		if node == self or not (node is Node2D) or not is_instance_valid(node):
			continue
		if node.has_method("is_dead_or_disabled") and bool(node.call("is_dead_or_disabled")):
			continue
		var other: Node2D = node
		var min_distance: float = my_radius + _body_radius_of(other) + G.ENEMY_SEPARATION_PADDING
		var offset: Vector2 = global_position - other.global_position
		var distance: float = offset.length()
		if distance >= min_distance:
			continue
		var push: Vector2 = offset / distance if distance > 0.01 else Vector2.RIGHT.rotated(_rng.randf() * TAU)
		force += push * (1.0 - distance / maxf(min_distance, 0.01))
	return force.limit_length(1.0) * minf(G.ENEMY_SEPARATION_MAX, data.move_speed * 1.35)


static func _body_radius_of(node: Node2D) -> float:
	var payload: Variant = node.get("data")
	if payload is EnemyData:
		return (payload as EnemyData).body_radius
	if node.has_method("get") and node.get("BODY_RADIUS") != null:
		return float(node.get("BODY_RADIUS"))
	return 10.0


# ==================== 状态与表现 ====================

func set_state(new_state: State) -> void:
	if state == new_state:
		return
	last_state = state
	state = new_state
	state_time = 0.0
	state_log.append(STATE_NAMES[clampi(int(new_state), 0, STATE_NAMES.size() - 1)])
	if state_log.size() > STATE_LOG_LIMIT:
		state_log.pop_front()


func state_name() -> String:
	return STATE_NAMES[clampi(int(state), 0, STATE_NAMES.size() - 1)]


func stun(duration: float) -> void:
	stun_timer = maxf(stun_timer, duration)


func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = minf(health + amount, max_health)
	queue_redraw()


## 头顶血条（只在掉血后绘制，满血不打扰画面）
func _draw() -> void:
	if dead or health >= max_health - 0.01:
		return
	var width: float = 22.0
	var ratio: float = clampf(health / maxf(max_health, 0.01), 0.0, 1.0)
	var top_left: Vector2 = Vector2(-width * 0.5, -20.0)
	draw_rect(Rect2(top_left, Vector2(width, 3.0)), Color(0.05, 0.04, 0.08, 0.62))
	var fill: Color = Color(0.96, 0.42, 0.36, 0.95) if ratio > 0.34 else Color(0.98, 0.28, 0.24, 0.98)
	if data.is_elite():
		fill = Color(0.86, 0.6, 1.0, 0.95) if ratio > 0.34 else Color(1.0, 0.5, 0.4, 0.98)
	draw_rect(Rect2(top_left + Vector2(0.5, 0.5), Vector2(maxf((width - 1.0) * ratio, 0.5), 2.0)), fill)
