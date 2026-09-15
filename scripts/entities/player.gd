class_name Player
extends CharacterBody2D
## Player —— 玩家角色与战斗核心（M3）。
##
## 职责：
##   1. 八向移动 + 鼠标瞄准（CharacterBody2D，与墙体/敌人碰撞）；
##   2. 射击：按当前武器的弹道类型分派（投射 / 激光 / 爆炸 / 追踪 / 近战）；
##   3. 冲刺（含无敌帧与冷却）、技能（冲击波）、交互（E 键）；
##   4. 属性：生命 / 护盾（延迟自动回复）/ 能量（持续回复）/ 暴击 / 各类加成。
##
## 属性的单一事实来源是 `stats` 字典——它直接引用 GameState.stats，
## 因此换层、存档、天赋加成都不需要额外同步。
##
## 受击契约（与 CombatUtil 配合）：
##   take_hit(amount: float, is_crit: bool, knockback: Vector2, source: int) -> void

const G := preload("res://scripts/core/game_const.gd")

const SPRITE_DIR: String = "res://assets/sprites/player/"
const DIRS: Array[String] = ["down", "up", "left", "right"]
const FRAMES_PER_DIR: int = 4

const BODY_RADIUS: float = 6.0
const BODY_OFFSET: Vector2 = Vector2(0, 4)

const ANIM_FPS_MOVE: float = 11.0
const ANIM_FPS_IDLE: float = 4.5
const STEP_INTERVAL: float = 0.34
const KNOCKBACK_DECAY: float = 980.0
const HIT_FLASH_TIME: float = 0.16

# ---------- 运行期状态 ----------
## 属性字典（通常直接引用 GameState.stats）
var stats: Dictionary = {}
## 手动瞄准模式：为 true 时忽略鼠标，使用 set_aim_direction() 给的方向（测试 / 手柄）
var manual_aim: bool = false
## 当前瞄准方向（单位向量）
var aim_direction: Vector2 = Vector2.RIGHT
## 子弹/特效挂载层（由 GameWorld 注入；缺省用父节点）
var bullet_layer: Node2D = null
var fx_layer: Node2D = null

## 炸弹投掷的活动范围（世界层按当前房间的 interior_rect 注入，撞墙即落地）
var throw_bounds: Rect2 = Rect2()
## 死亡标记
var dead: bool = false
## 无敌中（冲刺帧 / 受击后短暂无敌 / 出生保护）
var invulnerable: bool = false

# ---------- 武器 ----------
var weapons: Array = []
var weapon_index: int = 0

# ---------- 计时器 ----------
var fire_cooldown: float = 0.0
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var skill_cooldown_timer: float = 0.0
var invulnerable_timer: float = 0.0
var shield_regen_timer: float = 0.0
var hit_flash_timer: float = 0.0
var step_timer: float = 0.0
var anim_time: float = 0.0
var interact_cooldown: float = 0.0
var bomb_cooldown_timer: float = 0.0

# ---------- 测试可观测计数 ----------
var shots_fired: int = 0
var last_shot_crit: bool = false
var last_shot_damage: float = 0.0
var last_shot_pellets: int = 0
var last_fire_blocked_reason: String = ""
var dashes_used: int = 0
var skills_used: int = 0
var bombs_thrown: int = 0
var damage_taken_total: float = 0.0

# ---------- 内部 ----------
var _dash_direction: Vector2 = Vector2.RIGHT
var _external_velocity: Vector2 = Vector2.ZERO
var _move_input: Vector2 = Vector2.ZERO
var _body_sprite: Sprite2D
var _weapon_sprite: Sprite2D
var _glow: Sprite2D
var _collision: CollisionShape2D
var _frames: Dictionary = {}
var _focused_interactable: Node = null
var _rng_fallback := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(CombatUtil.GROUP_PLAYER)
	collision_layer = G.LAYER_PLAYER
	collision_mask = G.MASK_PLAYER

	if stats.is_empty():
		stats = GameState.stats if not GameState.stats.is_empty() else G.DEFAULT_PLAYER_STATS.duplicate(true)
	_clamp_resources()

	_build_nodes()
	_refresh_weapon_sprite()

	if GameState.weapons.is_empty() and weapons.is_empty():
		add_weapon(WeaponDB.starter())
	elif not GameState.weapons.is_empty() and weapons.is_empty():
		for w: Variant in GameState.weapons:
			weapons.append(w)
		weapon_index = clampi(GameState.weapon_index, 0, weapons.size() - 1)

	invulnerable = true
	invulnerable_timer = G.SPAWN_PROTECTION
	EventBus.player_invulnerable_changed.emit(true)
	EventBus.player_spawned.emit(self)
	_broadcast_all()


func _build_nodes() -> void:
	_collision = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BODY_RADIUS
	_collision.shape = circle
	_collision.position = BODY_OFFSET
	add_child(_collision)

	_body_sprite = Sprite2D.new()
	_body_sprite.centered = true
	_body_sprite.position = Vector2(0, -2)
	_body_sprite.z_index = 0
	add_child(_body_sprite)

	_weapon_sprite = Sprite2D.new()
	_weapon_sprite.centered = true
	_weapon_sprite.z_index = 1
	add_child(_weapon_sprite)

	_glow = Sprite2D.new()
	_glow.texture = _load_texture("res://assets/fx/glow_soft_blue.png")
	_glow.centered = true
	_glow.scale = Vector2.ONE * 0.55
	_glow.modulate = Color(1, 1, 1, 0.0)
	_glow.z_index = -1
	add_child(_glow)

	for dir_name: String in DIRS:
		var list: Array[Texture2D] = []
		for i: int in range(FRAMES_PER_DIR):
			var tex: Texture2D = _load_texture(SPRITE_DIR + "%s_%d.png" % [dir_name, i])
			if tex != null:
				list.append(tex)
		if not list.is_empty():
			_frames[dir_name] = list


static func _load_texture(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _physics_process(delta: float) -> void:
	if dead:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
		move_and_slide()
		return

	_tick_timers(delta)
	_update_aim()
	_handle_movement(delta)
	_handle_actions()
	_tick_regeneration(delta)
	_update_animation(delta)

	move_and_slide()
	_after_move()


func _tick_timers(delta: float) -> void:
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)
	skill_cooldown_timer = maxf(skill_cooldown_timer - delta, 0.0)
	interact_cooldown = maxf(interact_cooldown - delta, 0.0)
	bomb_cooldown_timer = maxf(bomb_cooldown_timer - delta, 0.0)
	hit_flash_timer = maxf(hit_flash_timer - delta, 0.0)
	step_timer = maxf(step_timer - delta, 0.0)

	if invulnerable_timer > 0.0:
		invulnerable_timer = maxf(invulnerable_timer - delta, 0.0)
		if invulnerable_timer <= 0.0:
			invulnerable = false
			EventBus.player_invulnerable_changed.emit(false)

	_body_sprite.modulate = Color(1, 1, 1, 1) if hit_flash_timer <= 0.0 else Color(1.6, 1.1, 1.1, 1)
	_glow.modulate.a = 0.45 if invulnerable else 0.0

	GameState.tick_talents(delta)


## 瞄准：默认跟随鼠标，manual_aim 时由外部/测试指定
func _update_aim() -> void:
	if manual_aim:
		return
	if not is_inside_tree():
		return
	var mouse_position: Vector2 = get_global_mouse_position()
	var to_mouse: Vector2 = mouse_position - global_position
	if to_mouse.length_squared() > 1.0:
		aim_direction = to_mouse.normalized()


func _handle_movement(delta: float) -> void:
	if dash_timer > 0.0:
		dash_timer = maxf(dash_timer - delta, 0.0)
		velocity = _dash_direction * _stat("dash_speed")
		_external_velocity = Vector2.ZERO
		Fx.single(_fx_host(), "dash_trail", global_position, {
			"life": 0.22, "tint": Color(0.6, 0.95, 1.0, 0.55), "z_index": 3, "scale": 1.1,
		})
		if dash_timer <= 0.0:
			AudioMgr.play_sfx("land", 0.06)
			Fx.play(_fx_host(), "dust", global_position + Vector2(0, 6), {"fps": 16.0, "scale": 0.8, "z_index": 3})
		return

	_move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed: float = _stat("move_speed")
	var wanted: Vector2 = _move_input * speed
	velocity = velocity.move_toward(wanted, speed * 9.0 * delta)
	velocity += _external_velocity
	_external_velocity = _external_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)


func _after_move() -> void:
	if _move_input.length_squared() > 0.01 and step_timer <= 0.0:
		step_timer = STEP_INTERVAL
		AudioMgr.play_sfx("step", 0.12, -14.0)


func _handle_actions() -> void:
	if Input.is_action_just_pressed("dash"):
		try_dash()
	if Input.is_action_just_pressed("skill"):
		try_skill()
	if Input.is_action_pressed("shoot"):
		var weapon: WeaponData = current_weapon()
		if weapon == null or weapon.auto_fire or Input.is_action_just_pressed("shoot"):
			try_fire()
	if Input.is_action_just_pressed("interact") and interact_cooldown <= 0.0:
		try_interact()
	if Input.is_action_just_pressed("throw_bomb"):
		try_throw_bomb()
	_handle_weapon_switching()
	_update_interactable_focus()


func _handle_weapon_switching() -> void:
	for i: int in range(3):
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			set_weapon_slot(i)
	if Input.is_action_just_pressed("weapon_next"):
		cycle_weapon(1)
	if Input.is_action_just_pressed("weapon_prev"):
		cycle_weapon(-1)


func _tick_regeneration(delta: float) -> void:
	var energy_regen: float = _stat("energy_regen")
	if energy_regen > 0.0:
		var before: float = float(stats.get("energy", 0.0))
		stats["energy"] = clampf(before + energy_regen * delta, 0.0, _stat("max_energy"))
		if not is_equal_approx(before, float(stats["energy"])):
			EventBus.player_energy_changed.emit(float(stats["energy"]), _stat("max_energy"))

	if shield_regen_timer > 0.0:
		shield_regen_timer = maxf(shield_regen_timer - delta, 0.0)
		return
	var max_shield: float = _stat("max_shield")
	var shield: float = float(stats.get("shield", 0.0))
	if max_shield > 0.0 and shield < max_shield:
		var rate: float = _stat("shield_regen_rate")
		stats["shield"] = minf(shield + rate * delta, max_shield)
		EventBus.player_shield_changed.emit(float(stats["shield"]), max_shield)
		if shield <= 0.0 and rate > 0.0:
			AudioMgr.play_sfx("shield_regen", 0.0, -10.0)


func _update_animation(delta: float) -> void:
	var moving: bool = _move_input.length_squared() > 0.01 or dash_timer > 0.0
	anim_time += delta * (ANIM_FPS_MOVE if moving else ANIM_FPS_IDLE)

	var dir_name: String = _facing_dir_name()
	var list: Array = _frames.get(dir_name, [])
	if list.is_empty():
		return
	var index: int = int(anim_time) % list.size()
	_body_sprite.texture = list[index]

	var weapon: WeaponData = current_weapon()
	if weapon == null:
		_weapon_sprite.texture = null
		return
	var offset_distance: float = 7.0 + (2.0 if weapon.is_melee() else 0.0)
	_weapon_sprite.position = aim_direction * offset_distance + Vector2(0, -1)
	_weapon_sprite.flip_h = aim_direction.x < -0.05
	_weapon_sprite.z_index = -1 if aim_direction.y < -0.45 else 1
	_weapon_sprite.rotation = 0.0


func _facing_dir_name() -> String:
	if absf(aim_direction.y) > absf(aim_direction.x):
		return "up" if aim_direction.y < 0.0 else "down"
	return "left" if aim_direction.x < 0.0 else "right"


# ==================== 射击 ====================

## 尝试开火。返回是否真的打出一发。
func try_fire() -> bool:
	last_fire_blocked_reason = ""
	if dead:
		last_fire_blocked_reason = "dead"
		return false
	var weapon: WeaponData = current_weapon()
	if weapon == null:
		last_fire_blocked_reason = "no_weapon"
		return false
	if fire_cooldown > 0.0:
		last_fire_blocked_reason = "cooldown"
		return false
	var cost: float = weapon.energy_cost
	if cost > 0.0 and float(stats.get("energy", 0.0)) < cost:
		last_fire_blocked_reason = "energy"
		AudioMgr.play_sfx("empty", 0.03)
		EventBus.ammo_or_energy_lacking.emit()
		fire_cooldown = 0.28
		return false

	if cost > 0.0:
		spend_energy(cost)
	fire_cooldown = weapon.fire_interval() / maxf(_stat("attack_speed_multiplier"), 0.1)

	var crit_chance: float = clampf(_stat("crit_chance") + weapon.crit_bonus, 0.0, 1.0)
	var is_crit: bool = CombatUtil.roll_crit(_rng(), crit_chance)
	var damage: float = CombatUtil.roll_damage(_rng(), weapon.damage, _stat("damage_multiplier"),
			weapon.damage_variance, is_crit, _stat("crit_multiplier"))
	last_shot_crit = is_crit
	last_shot_damage = damage
	last_shot_pellets = weapon.pellets

	match weapon.kind:
		WeaponData.Kind.HITSCAN:
			_fire_hitscan(weapon, damage, is_crit)
		WeaponData.Kind.MELEE:
			_fire_melee(weapon, damage, is_crit)
		_:
			_fire_projectiles(weapon, damage, is_crit)

	_apply_recoil(weapon)
	_muzzle_fx(weapon)
	AudioMgr.play_sfx(weapon.sfx, 0.05)
	if not weapon.is_melee():
		EventBus.request_screen_shake.emit(weapon.shake, 0.12)
	shots_fired += 1
	EventBus.weapon_fired.emit(weapon, is_crit)
	return true


func _fire_projectiles(weapon: WeaponData, damage: float, is_crit: bool) -> void:
	var pellets: int = maxi(weapon.pellets, 1)
	var spread: float = deg_to_rad(weapon.spread_deg)
	var origin: Vector2 = _muzzle_position(weapon)
	var speed: float = weapon.bullet_speed * _stat("bullet_speed_multiplier")
	for i: int in range(pellets):
		var t: float = 0.5 if pellets == 1 else float(i) / float(pellets - 1)
		var angle_offset: float = lerpf(-spread, spread, t)
		if pellets > 1:
			angle_offset += _rng().randf_range(-spread * 0.22, spread * 0.22)
		var direction: Vector2 = aim_direction.rotated(angle_offset)
		_spawn_bullet(weapon, damage, is_crit, origin, direction, speed)


func _spawn_bullet(weapon: WeaponData, damage: float, is_crit: bool, origin: Vector2, direction: Vector2, speed: float) -> Bullet:
	var bullet := Bullet.new()
	bullet.data = weapon
	bullet.source = self
	bullet.fx_layer = fx_layer
	bullet.from_player = true
	bullet.fly_velocity = direction * maxf(speed, 40.0)
	bullet.damage = damage
	bullet.is_crit = is_crit
	bullet.pierce_left = weapon.pierce
	bullet.life = weapon.bullet_lifetime
	bullet.radius = 3.0 + minf(weapon.damage * 0.04, 3.0)
	bullet.sprite_scale = 1.0 + minf(weapon.damage * 0.008, 0.5)
	bullet.flicker_fps = 16.0 if weapon.projectile_frames.size() > 1 else 0.0
	bullet.trail_enabled = weapon.kind != WeaponData.Kind.MELEE
	if weapon.kind == WeaponData.Kind.EXPLOSIVE:
		bullet.explode_radius = weapon.explosion_radius
		bullet.explode_damage_ratio = G.EXPLOSION_SELF_RATIO
		bullet.trail_interval = 0.035
	if weapon.kind == WeaponData.Kind.HOMING:
		bullet.homing = weapon.homing_strength
	bullet.position = origin
	_bullet_host().add_child(bullet)
	if bullet.global_position != origin:
		bullet.global_position = origin
	return bullet


func _fire_hitscan(weapon: WeaponData, damage: float, is_crit: bool) -> void:
	var origin: Vector2 = _muzzle_position(weapon)
	var reach: float = weapon.beam_range * _stat("bullet_speed_multiplier")
	var end: Vector2 = origin + aim_direction * maxf(reach, 40.0)
	var result: Dictionary = CombatUtil.ray_damage(self, origin, end,
			G.LAYER_ENEMY | G.LAYER_WORLD, damage, is_crit, weapon.knockback, get_instance_id(), [self])
	var hit_end: Vector2 = result.get("end", end)
	var beam := LaserBeam.new()
	beam.setup(origin.distance_to(hit_end), 7.0,
			Color(1.0, 0.42, 0.45) if not is_crit else Color(1.0, 0.82, 0.35), 0.13)
	beam.rotation = aim_direction.angle()
	beam.position = origin
	_fx_host().add_child(beam)


func _fire_melee(weapon: WeaponData, damage: float, is_crit: bool) -> void:
	var origin: Vector2 = global_position + aim_direction * (weapon.melee_range * 0.35)
	var hits: int = CombatUtil.melee_swing(self, origin, aim_direction, weapon.melee_range,
			weapon.melee_arc_deg * 0.5, damage, is_crit, weapon.knockback, get_instance_id(),
			G.LAYER_ENEMY, [self])
	last_shot_pellets = hits
	Fx.play(_fx_host(), "slash", origin + aim_direction * 8.0, {
		"fps": 30.0, "angle": aim_direction.angle(), "scale": 1.15, "z_index": 11,
	})
	if hits > 0:
		EventBus.request_screen_shake.emit(weapon.shake, 0.1)


func _muzzle_position(weapon: WeaponData) -> Vector2:
	return global_position + aim_direction * weapon.muzzle_offset + Vector2(0, -2)


func _apply_recoil(weapon: WeaponData) -> void:
	if weapon.recoil <= 0.0:
		return
	_external_velocity -= aim_direction * weapon.recoil


func _muzzle_fx(weapon: WeaponData) -> void:
	if weapon.is_melee():
		return
	var position_offset: Vector2 = _muzzle_position(weapon)
	Fx.play(_fx_host(), "muzzle", position_offset, {
		"fps": 34.0, "angle": aim_direction.angle(), "scale": 0.85, "z_index": 11,
	})


func _bullet_host() -> Node2D:
	if bullet_layer != null and is_instance_valid(bullet_layer):
		return bullet_layer
	return get_parent() as Node2D if get_parent() is Node2D else self


func _fx_host() -> Node2D:
	if fx_layer != null and is_instance_valid(fx_layer):
		return fx_layer
	return _bullet_host()


# ==================== 冲刺 / 技能 / 交互 ====================

func try_dash() -> bool:
	if dead or dash_cooldown_timer > 0.0 or dash_timer > 0.0:
		return false
	var direction: Vector2 = _move_input
	if direction.length_squared() < 0.01:
		direction = aim_direction
	_dash_direction = direction.normalized()
	dash_timer = _stat("dash_duration")
	dash_cooldown_timer = _stat("dash_cooldown")
	set_invulnerable(dash_timer + 0.06)
	dashes_used += 1
	AudioMgr.play_sfx("dash", 0.06)
	Fx.play(_fx_host(), "dust", global_position + Vector2(0, 6), {
		"fps": 18.0, "scale": 0.9, "angle": _dash_direction.angle(), "z_index": 3,
	})
	EventBus.player_dashed.emit()
	return true


func dash_ready() -> bool:
	return dash_cooldown_timer <= 0.0 and dash_timer <= 0.0


func try_skill() -> bool:
	if dead or skill_cooldown_timer > 0.0:
		return false
	if float(stats.get("energy", 0.0)) < G.SKILL_ENERGY_COST:
		AudioMgr.play_sfx("empty", 0.03)
		EventBus.ammo_or_energy_lacking.emit()
		skill_cooldown_timer = 0.4
		return false
	spend_energy(G.SKILL_ENERGY_COST)
	skill_cooldown_timer = _stat("skill_cooldown")
	skills_used += 1

	var damage: float = G.SKILL_DAMAGE * _stat("damage_multiplier")
	var is_crit: bool = CombatUtil.roll_crit(_rng(), _stat("crit_chance"))
	if is_crit:
		damage *= _stat("crit_multiplier")
	var damaged: Array = CombatUtil.area_damage(self, global_position, G.SKILL_RADIUS, damage, is_crit,
			G.SKILL_KNOCKBACK, get_instance_id(), G.LAYER_ENEMY, [self])
	last_shot_damage = damage
	last_shot_crit = is_crit
	last_shot_pellets = damaged.size()

	AudioMgr.play_sfx("skill", 0.05)
	Fx.play(_fx_host(), "ring", global_position, {"fps": 20.0, "scale": 2.6, "z_index": 11})
	Fx.play(_fx_host(), "level_ring", global_position, {"fps": 18.0, "scale": 1.5, "z_index": 11})
	EventBus.request_screen_shake.emit(3.2, 0.22)
	EventBus.player_skill_used.emit(G.SKILL_ID)
	return true


func skill_ready() -> bool:
	return skill_cooldown_timer <= 0.0


# ==================== 炸弹（M6） ====================

## F 键：投掷炸弹。消耗 GameState.bombs，冷却 G.BOMB_COOLDOWN。
## 炸弹挂到玩家所在的实体层（带 Y 排序），飞满射程或撞出房间范围就落地起爆。
func try_throw_bomb() -> bool:
	if dead or bomb_cooldown_timer > 0.0:
		return false
	if GameState.bombs <= 0:
		AudioMgr.play_sfx("empty", 0.03)
		EventBus.ammo_or_energy_lacking.emit()
		bomb_cooldown_timer = 0.25
		return false
	GameState.use_bomb()
	bomb_cooldown_timer = G.BOMB_COOLDOWN
	bombs_thrown += 1

	var bomb: ThrownBomb = ThrownBomb.create(aim_direction * G.BOMB_THROW_SPEED + _external_velocity * 0.25)
	bomb.position = global_position + aim_direction.normalized() * 9.0 + Vector2(0, -2)
	bomb.target_player = self
	bomb.fx_layer = _fx_host()
	bomb.thrower_id = get_instance_id()
	bomb.damage = G.BOMB_DAMAGE * _stat("damage_multiplier")
	bomb.bounds = throw_bounds
	_bomb_host().add_child(bomb)

	AudioMgr.play_sfx("swing_blade", 0.0, -8.0)
	Fx.play(_fx_host(), "dust", global_position + Vector2(0, 4), {"fps": 14.0, "scale": 0.6, "z_index": 3})
	return true


func bomb_ready() -> bool:
	return bomb_cooldown_timer <= 0.0


## 炸弹宿主：优先玩家父节点（entity_root），退化时用特效层
func _bomb_host() -> Node2D:
	var parent_node: Node = get_parent()
	if parent_node is Node2D:
		return parent_node as Node2D
	return _fx_host()


## E 键交互：把请求交给当前聚焦的可交互物
func try_interact() -> bool:
	if dead:
		return false
	interact_cooldown = 0.25
	var target: Node = _focused_interactable
	if target == null:
		return false
	if target.has_method("interact"):
		target.call("interact", self)
	EventBus.interact_requested.emit(target)
	return true


func _update_interactable_focus() -> void:
	var found: Node = null
	var best_distance: float = G.INTERACT_RADIUS
	for node: Node in get_tree().get_nodes_in_group(CombatUtil.GROUP_INTERACTABLE):
		if node == self or not (node is Node2D) or not is_instance_valid(node):
			continue
		if node.has_method("can_interact") and not bool(node.call("can_interact", self)):
			continue
		var distance: float = global_position.distance_to((node as Node2D).global_position)
		if distance <= best_distance:
			best_distance = distance
			found = node
	if found == _focused_interactable:
		return
	_focused_interactable = found
	if found == null:
		EventBus.interactable_blurred.emit()
	else:
		var prompt: String = "按 E 交互"
		if found.has_method("interact_prompt"):
			prompt = str(found.call("interact_prompt"))
		EventBus.interactable_focused.emit(prompt)


# ==================== 属性 / 受击 ====================

## 读取属性（含天赋加成）
func _stat(key: String) -> float:
	return float(stats.get(key, 0.0)) + float(stats.get("bonus_" + key, 0.0))


func stat(key: String) -> float:
	return _stat(key)


func max_health() -> float:
	return _stat("max_health")


func health() -> float:
	return float(stats.get("health", 0.0))


func max_shield() -> float:
	return _stat("max_shield")


func shield() -> float:
	return float(stats.get("shield", 0.0))


func max_energy() -> float:
	return _stat("max_energy")


func energy() -> float:
	return float(stats.get("energy", 0.0))


func is_dead_or_disabled() -> bool:
	return dead


## 受击契约实现
func take_hit(amount: float, is_crit: bool, knockback: Vector2, _source: int) -> void:
	if dead or invulnerable:
		return
	var damage: float = maxf(amount - _stat("armor"), 1.0)
	damage_taken_total += damage

	if knockback.length_squared() > 0.01:
		_external_velocity += knockback * _stat("knockback_multiplier")

	var from_shield: bool = false
	var shield_value: float = float(stats.get("shield", 0.0))
	if shield_value > 0.0:
		from_shield = true
		var absorbed: float = minf(shield_value, damage)
		stats["shield"] = shield_value - absorbed
		damage -= absorbed
		EventBus.player_shield_changed.emit(float(stats["shield"]), _stat("max_shield"))
		Fx.play(_fx_host(), "shield_pop", global_position, {"fps": 22.0, "scale": 1.1, "z_index": 12})
		if float(stats["shield"]) <= 0.0:
			AudioMgr.play_sfx("shield_break", 0.04)

	if damage > 0.0:
		stats["health"] = maxf(float(stats.get("health", 0.0)) - damage, 0.0)
		EventBus.player_health_changed.emit(health(), _stat("max_health"))
		AudioMgr.play_sfx("player_hurt", 0.05)
		Fx.play(_fx_host(), "hit", global_position, {"fps": 24.0, "scale": 1.0, "z_index": 12})

	hit_flash_timer = HIT_FLASH_TIME
	shield_regen_timer = _stat("shield_regen_delay")
	set_invulnerable(G.INVULN_AFTER_HIT)
	EventBus.player_hurt.emit(amount, from_shield)
	# 飘字由 CombatUtil.apply_hit 统一发出，这里不再重复发信号（否则一次受击会出现两个数字）
	EventBus.request_screen_shake.emit(2.4, 0.16)

	if health() <= 0.0:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	velocity = Vector2.ZERO
	_external_velocity = Vector2.ZERO
	invulnerable = true
	collision_layer = 0
	_body_sprite.modulate = Color(1, 1, 1, 0.4)
	_weapon_sprite.visible = false
	AudioMgr.play_sfx("player_die", 0.0)
	Fx.play(_fx_host(), "explode", global_position, {"fps": 16.0, "scale": 1.2, "z_index": 14})
	Fx.play(_fx_host(), "smoke", global_position, {"fps": 10.0, "scale": 1.4, "z_index": 13})
	EventBus.request_screen_shake.emit(5.0, 0.4)
	EventBus.player_died.emit()


func set_invulnerable(duration: float) -> void:
	invulnerable = true
	invulnerable_timer = maxf(invulnerable_timer, duration)
	EventBus.player_invulnerable_changed.emit(true)


func heal(amount: float) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var before: float = health()
	stats["health"] = clampf(before + amount, 0.0, _stat("max_health"))
	var gained: float = health() - before
	if gained > 0.0:
		EventBus.player_health_changed.emit(health(), _stat("max_health"))
		EventBus.player_healed.emit(gained)
		Fx.play(_fx_host(), "heal", global_position, {"fps": 14.0, "scale": 1.0, "z_index": 12})
	return gained


func add_shield(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before: float = shield()
	stats["shield"] = clampf(before + amount, 0.0, _stat("max_shield"))
	var gained: float = shield() - before
	if gained > 0.0:
		EventBus.player_shield_changed.emit(shield(), _stat("max_shield"))
	return gained


func spend_energy(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if float(stats.get("energy", 0.0)) < amount:
		return false
	stats["energy"] = float(stats["energy"]) - amount
	EventBus.player_energy_changed.emit(energy(), _stat("max_energy"))
	return true


func add_energy(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before: float = energy()
	stats["energy"] = clampf(before + amount, 0.0, _stat("max_energy"))
	var gained: float = energy() - before
	if gained > 0.0:
		EventBus.player_energy_changed.emit(energy(), _stat("max_energy"))
	return gained


func _clamp_resources() -> void:
	stats["health"] = clampf(float(stats.get("health", _stat("max_health"))), 0.0, _stat("max_health"))
	stats["shield"] = clampf(float(stats.get("shield", _stat("max_shield"))), 0.0, _stat("max_shield"))
	stats["energy"] = clampf(float(stats.get("energy", _stat("max_energy"))), 0.0, _stat("max_energy"))


func _broadcast_all() -> void:
	EventBus.player_health_changed.emit(health(), _stat("max_health"))
	EventBus.player_shield_changed.emit(shield(), _stat("max_shield"))
	EventBus.player_energy_changed.emit(energy(), _stat("max_energy"))
	EventBus.player_gold_changed.emit(GameState.gold)
	EventBus.player_stats_changed.emit(stats)


# ==================== 武器管理 ====================

func add_weapon(weapon: WeaponData) -> bool:
	if weapon == null:
		return false
	if weapons.size() >= G.MAX_WEAPON_SLOTS:
		weapons[weapon_index] = weapon
	else:
		weapons.append(weapon)
		weapon_index = weapons.size() - 1
	_sync_weapons_to_state()
	_refresh_weapon_sprite()
	EventBus.weapon_list_changed.emit(weapons)
	EventBus.weapon_equipped.emit(weapon, weapon_index)
	return true


func set_weapon_slot(index: int) -> bool:
	if index < 0 or index >= weapons.size() or index == weapon_index:
		return false
	weapon_index = index
	fire_cooldown = maxf(fire_cooldown, G.WEAPON_SWITCH_DELAY)
	_sync_weapons_to_state()
	_refresh_weapon_sprite()
	AudioMgr.play_sfx("reload", 0.05, -8.0)
	EventBus.weapon_switched.emit(weapon_index)
	return true


func cycle_weapon(direction: int) -> bool:
	if weapons.size() < 2:
		return false
	return set_weapon_slot(posmod(weapon_index + direction, weapons.size()))


func current_weapon() -> WeaponData:
	if weapons.is_empty():
		return null
	return weapons[clampi(weapon_index, 0, weapons.size() - 1)]


func _sync_weapons_to_state() -> void:
	GameState.weapons = weapons
	GameState.weapon_index = weapon_index


func _refresh_weapon_sprite() -> void:
	var weapon: WeaponData = current_weapon()
	_weapon_sprite.texture = weapon.held_texture() if weapon != null else null


# ==================== 其他 ====================

## 测试 / 手柄用：直接指定瞄准方向
func set_aim_direction(direction: Vector2) -> void:
	manual_aim = true
	if direction.length_squared() > 0.0001:
		aim_direction = direction.normalized()


## 强制结束无敌（出生保护跳过）
func clear_invulnerable() -> void:
	invulnerable = false
	invulnerable_timer = 0.0
	EventBus.player_invulnerable_changed.emit(false)


func _rng() -> RandomNumberGenerator:
	return GameState.rng if GameState.rng != null else _rng_fallback


## 换层前把当前实时数值写回 GameState 快照
func snapshot_to_state() -> void:
	GameState.snapshot_stats(stats)
	GameState.weapon_index = weapon_index


## 换层/读档后把 GameState 快照写回实时属性。
## 只覆盖非 bonus_ 键：天赋加成（bonus_*）由天赋系统自己维护，不能被快照冲掉。
func restore_from_state() -> void:
	for key: String in GameState.stats.keys():
		if key.begins_with("bonus_"):
			continue
		stats[key] = GameState.stats[key]
	_clamp_resources()
	_broadcast_all()
