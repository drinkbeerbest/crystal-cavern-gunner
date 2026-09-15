class_name EnemyBoss
extends Enemy
## EnemyBoss —— Boss 战实体（M7）。
##
## 两种 Boss 共用本类，技能池按 data.id 区分：
##   warden（晶核监守者）：冲撞 + 环形弹幕 + 召唤矿工；阶段 2 解锁扇形弹幕。
##   weaver（织弹者）  ：扇形/螺旋弹幕强化型；阶段 2 解锁环形弹幕。
##
## 行为链：
##   走位（绕玩家环游保持距离） -> 冷却结束按轮转选技能
##       -> 预警（windup，脚下 ring 提示，玩家可走位） -> 执行（active） -> 冷却
## 血量低于 phase_threshold 时进入阶段 2：移速/射速/弹数提升，并解锁新技能，
## 同时广播 boss_phase_changed（HUD 播阶段横幅）。
##
## Boss 特有的两点：
##   1. 免疫击退打断：覆写 interrupt() 只计数不硬直（基类 INTERRUPT_KNOCKBACK 会打断冲锋/瞄准）；
##   2. 召唤物由 world_node.spawn_enemy() 注入世界，死亡时同步清场，
##      场上小怪清零会广播 boss_minions_cleared（HUD toast「小怪已清空」）。

enum Skill { NONE, RADIAL, FAN, SPIRAL, CHARGE, SUMMON, SLAM }

const SKILL_NAMES: Array[String] = ["none", "radial", "fan", "spiral", "charge", "summon", "slam"]

## 冲刺命中后追加的结算延迟（帧数），避免与撞墙眩晕同时触发
const CHARGE_HIT_KNOCKBACK: float = 300.0
## 螺旋弹幕的起始预警时长
const SPIRAL_WINDUP: float = 0.3

## 技能轮转探测圈数：找冷却就绪的技能时最多绕池子几圈
const ROTATION_PASSES: int = 2

# ---------- HUD 需要的暴露属性 ----------
var display_name: String = ""
var max_health_value: float = 1.0

# ---------- 阶段 ----------
var phase_index: int = 1

# ---------- 技能状态机 ----------
var skill_context: Skill = Skill.NONE
var skill_phase: String = ""          ## "windup" / "active"
var skill_timer: float = 0.0
var skill_cooldowns: Dictionary = {}  ## Skill -> 剩余冷却秒
var _rotation_index: int = 0

# ---------- 技能执行参数 ----------
var _shot_dir: Vector2 = Vector2.RIGHT
var _shot_angle: float = 0.0
var _burst_left: int = 0
var _wave_left: int = 0
var _tick_left: int = 0

# ---------- 测试可观测计数 ----------
var radials_fired: int = 0
var fans_fired: int = 0
var spirals_fired: int = 0
var charges_done: int = 0
var summons_done: int = 0
var slams_done: int = 0
var phase_switches: int = 0
var summons_blocked_by_cap: int = 0

# ---------- 召唤 ----------
var _minions: Array = []
var _had_minions: bool = false


# ==================== 生命周期 ====================

func configure(enemy_data: EnemyData) -> void:
	super.configure(enemy_data)
	display_name = data.display_name
	max_health_value = max_health


func _ready() -> void:
	super._ready()
	max_health_value = max_health
	if absf(data.boss_sprite_scale - 1.0) > 0.001 and _sprite != null:
		_sprite.scale = Vector2.ONE * data.boss_sprite_scale
	# 登场：封门咆哮 + 血条出现
	AudioMgr.play_sfx("boss_roar", 0.0, -4.0)
	Fx.play(_fx_host(), "level_ring", global_position, {
		"fps": 12.0, "scale": 2.2, "z_index": 13, "tint": Color(1.0, 0.55, 0.35, 0.85),
	})
	# 每个技能各自独立的冷却表
	skill_cooldowns = {
		Skill.RADIAL: 0.0, Skill.FAN: 1.0, Skill.SPIRAL: 1.6,
		Skill.CHARGE: 0.8, Skill.SUMMON: 2.4, Skill.SLAM: 0.0,
	}
	EventBus.boss_spawned.emit(self)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_track_minions()


## 战斗血条只有 HUD 的大血条，不画头顶小条
func _draw() -> void:
	pass


# ==================== 打断与受击 ====================

## Boss 免疫击退打断：只计数不断技能（避免小手枪把 Boss 技能全打断）
func interrupt() -> void:
	interrupts += 1


## 受击：转发给基类后广播血量变化；跨过阈值时切阶段 2
func take_hit(amount: float, is_crit: bool, knockback: Vector2, source: int) -> void:
	super.take_hit(amount, is_crit, knockback, source)
	if dead:
		return
	EventBus.boss_health_changed.emit(health, max_health_value)
	_check_phase_switch()


func _check_phase_switch() -> void:
	if phase_index >= 2 or health / maxf(max_health_value, 1.0) > data.phase_threshold:
		return
	phase_index = 2
	phase_switches += 1
	AudioMgr.play_sfx("boss_roar", 0.0, -2.0)
	Fx.play(_fx_host(), "level_ring", global_position, {
		"fps": 14.0, "scale": 3.0, "z_index": 14, "tint": Color(1.0, 0.35, 0.25, 0.95),
	})
	# 阶段切换刷新进攻节奏：清掉当前技能冷却，立刻能放新技能
	for key: Variant in skill_cooldowns.keys():
		skill_cooldowns[key] = -1.0
	EventBus.boss_phase_changed.emit(self, phase_index)


## 死亡：先清场召唤物（保证 wave_cleared 正常触发 -> 传送门），再走基类死亡链
func die() -> void:
	if dead:
		return
	_kill_minions()
	super.die()
	EventBus.boss_died.emit(self)


# ==================== 主 AI ====================

func _think(delta: float) -> void:
	_tick_cooldowns(delta)
	if skill_context != Skill.NONE:
		_tick_skill(delta)
		return
	_refresh_target()
	if target == null:
		super._think(delta)
		return

	var to_target: Vector2 = target.global_position - global_position
	var distance: float = to_target.length()
	facing = to_target.normalized() if distance > 0.01 else facing

	# 贴脸时优先砸地（AoE 反打窗口，玩家需要拉开）
	if distance <= data.slam_trigger_range and _cd_ready(Skill.SLAM):
		_start_skill(Skill.SLAM)
		return

	# 普通技能的喘息节奏
	if attack_cooldown <= 0.0:
		var chosen: Skill = _choose_skill(distance)
		if chosen != Skill.NONE:
			_start_skill(chosen)
			return

	# 走位：绕玩家环形游走，保持中等交战距离
	_strafe_move(delta)
	set_state(State.CHASE)


func _tick_cooldowns(delta: float) -> void:
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	for key: Variant in skill_cooldowns.keys():
		if float(skill_cooldowns[key]) > 0.0:
			skill_cooldowns[key] = float(skill_cooldowns[key]) - delta


func _cd_ready(kind: Skill) -> bool:
	return float(skill_cooldowns.get(kind, 0.0)) <= 0.0


func _cooldown_mult() -> float:
	return data.phase2_cooldown_mul if phase_index >= 2 else 1.0


func _move_speed() -> float:
	return data.move_speed * (data.phase2_speed_mul if phase_index >= 2 else 1.0)


## 按 Boss 类型给出技能池（阶段 2 解锁新技能）
func _skill_pool() -> Array:
	var pool: Array
	if str(data.id) == "weaver":
		pool = [Skill.FAN, Skill.SPIRAL, Skill.SUMMON]
		if phase_index >= 2:
			pool.append(Skill.RADIAL)
	else:
		pool = [Skill.RADIAL, Skill.CHARGE, Skill.SUMMON]
		if phase_index >= 2:
			pool.append(Skill.FAN)
	return pool


## 轮转选择下一个就绪技能：从上次位置开始绕池子找冷却好的；
## 没有就绪技能时返回 NONE（继续走位等冷却）
func _choose_skill(distance: float) -> Skill:
	var pool: Array = _skill_pool()
	if pool.is_empty():
		return Skill.NONE
	for pass_index: int in range(ROTATION_PASSES):
		for i: int in range(pool.size()):
			var index: int = (_rotation_index + i) % pool.size()
			var kind: Skill = pool[index]
			if not _cd_ready(kind):
				continue
			if kind == Skill.CHARGE and distance > data.charge_trigger_range * 1.15:
				continue  # 太远冲过去浪费，留给距离近时再冲
			_rotation_index = (index + 1) % pool.size()
			return kind
		# 全程都在冷却：略过当前一项再试一圈，保持轮转不会卡死
		_rotation_index = (_rotation_index + 1) % maxi(pool.size(), 1)
	return Skill.NONE


# ==================== 技能执行 ====================

## 进入技能：先预警（windup），预警结束再执行（active）
func _start_skill(kind: Skill) -> void:
	skill_context = kind
	skill_phase = "windup"
	set_state(State.ATTACK)
	move_velocity = Vector2.ZERO
	match kind:
		Skill.RADIAL:
			skill_timer = data.radial_telegraph
			_windup_ring(128.0, 0.75, Color(0.95, 0.5, 0.35, 0.8))
		Skill.FAN:
			skill_timer = data.fan_aim_time
			_shot_dir = _dir_to_target()
			_windup_ring(104.0, 0.6, Color(1.0, 0.62, 0.4, 0.8))
		Skill.SPIRAL:
			skill_timer = SPIRAL_WINDUP
			_shot_angle = _dir_to_target().angle()
			_windup_ring(96.0, 0.55, Color(0.72, 0.55, 1.0, 0.8))
		Skill.CHARGE:
			skill_timer = data.charge_windup
			_shot_dir = _dir_to_target()
			_windup_ring(58.0, 0.7, Color(1.0, 0.85, 0.4, 0.9))
			AudioMgr.play_sfx("boss_charge", 0.0, -6.0)
		Skill.SUMMON:
			skill_timer = data.summon_windup
			_windup_ring(86.0, 0.8, Color(0.6, 1.0, 0.75, 0.85))
			AudioMgr.play_sfx("boss_summon", 0.0, -6.0)
		Skill.SLAM:
			skill_timer = data.slam_windup
			_windup_ring(data.slam_radius, 0.95, Color(1.0, 0.45, 0.3, 0.9))
			AudioMgr.play_sfx("boss_charge", 0.0, -8.0)
		_:
			pass


## 预警脚下的 ring（靠近 Boss/技能落点的提示圈）
func _windup_ring(radius: float, alpha: float, tint: Color) -> void:
	Fx.play(_fx_host(), "ring", global_position, {
		"fps": 10.0, "scale": radius / 34.0, "z_index": 8, "tint": tint,
	})


func _tick_skill(delta: float) -> void:
	if skill_phase == "windup":
		skill_timer -= delta
		move_velocity = Vector2.ZERO
		if _sprite != null:
			_sprite.modulate = Color(1.0 + 0.25 * (1.0 - maxf(skill_timer, 0.0) / 0.2), 1.0, 1.0, 1.0)
		if skill_timer <= 0.0:
			_enter_skill_active()
		return

	# active 阶段：不同技能各自推进
	match skill_context:
		Skill.RADIAL:
			_tick_radial(delta)
		Skill.FAN:
			_tick_fan(delta)
		Skill.SPIRAL:
			_tick_spiral(delta)
		Skill.CHARGE:
			_tick_charge(delta)
		Skill.SUMMON:
			_tick_summon(delta)
		Skill.SLAM:
			# SLAM 在 _enter_skill_active 里即时执行并结束，这里只兜底防残留
			_finish_skill()
		_:
			_finish_skill()


## 预警结束 -> 初始化执行状态（播攻击音效）
func _enter_skill_active() -> void:
	skill_phase = "active"
	if _sprite != null:
		_sprite.modulate = Color.WHITE
	match skill_context:
		Skill.RADIAL:
			_wave_left = data.radial_waves
			skill_timer = 0.0
			_shot_angle = _dir_to_target().angle()
			AudioMgr.play_sfx("boss_charge", 0.0, -8.0)
		Skill.FAN:
			_burst_left = data.fan_bursts
			skill_timer = 0.0
			AudioMgr.play_sfx("boss_charge", 0.0, -6.0)
		Skill.SPIRAL:
			_tick_left = data.spiral_ticks
			skill_timer = 0.0
			AudioMgr.play_sfx("boss_charge", 0.0, -5.0)
		Skill.CHARGE:
			_charge_dir = _dir_to_target()
			skill_timer = data.charge_duration
			AudioMgr.play_sfx("boss_charge", 0.0, -2.0)
		Skill.SUMMON:
			_do_summon()
			_finish_skill()
			return
		Skill.SLAM:
			_do_slam()
			_finish_skill()
			return
		_:
			_finish_skill()
			return


# ---------- 具体技能 ----------

## 环形弹幕：一圈一圈向外均匀扩散（相邻圈错位半格）
func _tick_radial(delta: float) -> void:
	skill_timer -= delta
	if skill_timer <= 0.0:
		var count: int = data.radial_count + (data.phase2_extra_bullets if phase_index >= 2 else 0)
		var offset: float = 0.0 if _wave_left % 2 == 0 else PI / float(maxi(count, 2))
		_shot_angle = _dir_to_target().angle() + offset
		for i: int in range(count):
			var angle: float = _shot_angle + TAU * float(i) / float(count)
			_fire_boss_bullet(Vector2.from_angle(angle), data.radial_damage, data.radial_speed)
		_wave_left -= 1
		skill_timer = data.radial_wave_interval
		if _wave_left <= 0:
			radials_fired += 1
			_finish_skill()


## 扇形弹幕：锁定玩家方向连喷若干波
func _tick_fan(delta: float) -> void:
	skill_timer -= delta
	if skill_timer <= 0.0:
		var count: int = data.fan_count + (data.phase2_extra_bullets if phase_index >= 2 else 0)
		var base_angle: float = _dir_to_target().angle()
		var spread: float = deg_to_rad(data.fan_spread_deg)
		for i: int in range(count):
			var t: float = (float(i) / maxf(float(count - 1), 1.0)) - 0.5
			var angle: float = base_angle + t * spread
			_fire_boss_bullet(Vector2.from_angle(angle), data.fan_damage, data.fan_speed)
		_burst_left -= 1
		skill_timer = data.fan_burst_interval
		if _burst_left <= 0:
			fans_fired += 1
			_finish_skill()


## 螺旋弹幕：多臂同步旋转吐弹，覆盖移动路线
func _tick_spiral(delta: float) -> void:
	skill_timer -= delta
	if skill_timer <= 0.0:
		var arms: int = data.spiral_arms
		for i: int in range(arms):
			var angle: float = _shot_angle + TAU * float(i) / float(maxi(arms, 1))
			_fire_boss_bullet(Vector2.from_angle(angle), data.spiral_damage, data.spiral_speed)
		_shot_angle += deg_to_rad(data.spiral_step_deg)
		_tick_left -= 1
		skill_timer = data.spiral_interval
		if _tick_left <= 0:
			spirals_fired += 1
			_finish_skill()


## 冲撞：锁定方向高速直线突进；撞墙眩晕给反打窗口，命中玩家造成伤害并停下
var _charge_dir: Vector2 = Vector2.RIGHT
var _charge_hit_invuln: float = 0.0

func _tick_charge(delta: float) -> void:
	move_velocity = _charge_dir * data.charge_speed
	_charge_hit_invuln = maxf(_charge_hit_invuln - delta, 0.0)
	if target != null and is_instance_valid(target) and not _target_is_dead() \
			and _charge_hit_invuln <= 0.0:
		var reach: float = data.body_radius + _body_radius_of(target) + 10.0
		if global_position.distance_to(target.global_position) <= reach:
			damage_target(data.charge_damage, _charge_dir * CHARGE_HIT_KNOCKBACK)
			charges_done += 1
			_finish_skill()
			return
	if last_collided_wall:
		charges_done += 1
		stun_timer = maxf(stun_timer, data.charge_stun_on_wall)
		_finish_skill()
		return
	skill_timer -= delta
	if skill_timer <= 0.0:
		charges_done += 1
		_finish_skill()


## 召唤小怪：到上限则跳过（不推进召唤计数）
func _do_summon() -> void:
	var alive_minions: int = _minions_alive()
	if alive_minions >= data.summon_cap:
		summons_blocked_by_cap += 1
		return
	var to_spawn: int = mini(data.summon_count, data.summon_cap - alive_minions)
	for i: int in range(to_spawn):
		var minion_id: String = _pick_minion_id()
		var minion: Enemy = _summon_one(minion_id)
		if minion != null:
			_minions.append(minion)
			_had_minions = true
	summons_done += 1


func _tick_summon(_delta: float) -> void:
	_do_summon()
	_finish_skill()


## 砸地：范围内伤害 + 强击退，配震屏与烟尘
func _do_slam() -> void:
	if target != null and is_instance_valid(target) and not _target_is_dead():
		var reach: float = data.slam_radius + _body_radius_of(target)
		if global_position.distance_to(target.global_position) <= reach:
			damage_target(data.slam_damage, (target.global_position - global_position).normalized() * data.slam_knockback)
	slams_done += 1
	AudioMgr.play_sfx("boss_slam", 0.0, -4.0)
	Fx.play(_fx_host(), "ring", global_position, {
		"fps": 12.0, "scale": data.slam_radius / 34.0, "z_index": 13,
		"tint": Color(1.0, 0.55, 0.3, 0.9),
	})
	Fx.scatter(_fx_host(), "dust", global_position, 10, 22.0, {"fps": 18.0, "z_index": 9})


# ---------- 技能收尾 ----------

## 一个技能结束：进冷却 + 喘息 -> 回到走位
func _finish_skill() -> void:
	if skill_context != Skill.NONE:
		match skill_context:
			Skill.RADIAL:
				skill_cooldowns[Skill.RADIAL] = data.radial_cooldown * _cooldown_mult()
			Skill.FAN:
				skill_cooldowns[Skill.FAN] = data.fan_cooldown * _cooldown_mult()
			Skill.SPIRAL:
				skill_cooldowns[Skill.SPIRAL] = data.spiral_cooldown * _cooldown_mult()
			Skill.CHARGE:
				skill_cooldowns[Skill.CHARGE] = data.charge_cooldown * _cooldown_mult()
			Skill.SUMMON:
				skill_cooldowns[Skill.SUMMON] = data.summon_cooldown * _cooldown_mult()
			Skill.SLAM:
				skill_cooldowns[Skill.SLAM] = data.slam_cooldown * _cooldown_mult()
			_:
				pass
	skill_context = Skill.NONE
	skill_phase = ""
	skill_timer = 0.0
	attack_cooldown = data.skill_interval
	move_velocity = Vector2.ZERO
	if _sprite != null:
		_sprite.modulate = Color.WHITE
	set_state(State.CHASE)


# ---------- 移动 ----------

## 绕玩家环形游走：太远靠近、太近拉开、适中横向绕圈
func _strafe_move(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var to_target: Vector2 = target.global_position - global_position
	var distance: float = to_target.length()
	var direction: Vector2 = to_target.normalized() if distance > 0.01 else facing
	var lateral: Vector2 = Vector2(-direction.y, direction.x) * data.strafe_speed
	lateral *= 1.0 if _rng.randf() > 0.5 else -1.0
	_strafe_flip(delta)
	lateral *= _strafe_sign
	var wanted: Vector2 = lateral
	if distance < 130.0:
		wanted = -direction * _move_speed() * 0.9 + lateral * 0.5
	elif distance > 260.0:
		wanted = direction * _move_speed() + lateral * 0.3
	move_velocity = wanted


var _strafe_sign: float = 1.0
var _strafe_flip_timer: float = 1.6

func _strafe_flip(delta: float) -> void:
	_strafe_flip_timer -= delta
	if _strafe_flip_timer <= 0.0:
		_strafe_flip_timer = _rng.randf_range(1.2, 2.4)
		_strafe_sign = -_strafe_sign


# ---------- 弹幕 ----------

func _dir_to_target() -> Vector2:
	if target != null and is_instance_valid(target):
		var to_target: Vector2 = target.global_position - global_position
		if to_target.length_squared() > 0.01:
			return to_target.normalized()
	return facing


func _fire_boss_bullet(direction: Vector2, damage: float, speed: float) -> void:
	var textures: Array[Texture2D] = []
	var tex: Texture2D = Fx.texture("bullet_boss")
	if tex != null:
		textures.append(tex)
	fire_bullet(direction, damage, speed, data.bullet_lifetime if data.bullet_lifetime > 0.0 else 2.6,
			5.5, textures)


# ---------- 召唤 ----------

func _pick_minion_id() -> String:
	var ids: Array = data.summon_ids if not data.summon_ids.is_empty() else ["husk"]
	return str(ids[abs(_rng.randi()) % ids.size()])


func _summon_one(minion_id: String) -> Enemy:
	if world_node == null or not is_instance_valid(world_node):
		return null
	var position_value: Vector2 = global_position + Vector2.RIGHT.rotated(_rng.randf() * TAU) \
			* _rng.randf_range(70.0, 120.0)
	var minion: Enemy = world_node.spawn_enemy(minion_id, position_value)
	if minion != null:
		# 召唤物呈现立场：血条粒子淡蓝色
		_glow_minion(minion)
	return minion


func _glow_minion(minion: Enemy) -> void:
	if minion == null:
		return
	if minion.get("_glow") != null:
		var glow: Node = minion.get("_glow")
		if glow is Sprite2D:
			(glow as Sprite2D).modulate = Color(0.55, 0.9, 1.0, 0.5)


## 场上的存活召唤物数量（测试与 HUD 共用）
func minions_alive() -> int:
	return _minions_alive()


func _minions_alive() -> int:
	var count: int = 0
	for entry: Variant in _minions:
		if is_instance_valid(entry) and (entry as Enemy) is Enemy and not (entry as Enemy).dead:
			count += 1
	return count


func _kill_minions() -> void:
	for entry: Variant in _minions:
		if is_instance_valid(entry) and (entry as Enemy) is Enemy and not (entry as Enemy).dead:
			(entry as Enemy).die()
	_minions.clear()
	_had_minions = false


## 场上小怪从有到无：广播「小怪已清空」（HUD 用它做提示）
func _track_minions() -> void:
	if dead or not activated or _minions.is_empty():
		return
	var alive: int = _minions_alive()
	if _had_minions and alive == 0:
		_had_minions = false
		EventBus.boss_minions_cleared.emit(self)
	elif alive > 0:
		_had_minions = true