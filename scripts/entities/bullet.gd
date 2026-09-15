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
	if _age >= life:
		_expire()
		return

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
	var query := PhysicsRayQueryParameters2D.create(origin, target, _target_mask, [get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = false
	return space_state.intersect_ray(query)


func _hit_target(target: Node, hit_position: Vector2) -> void:
	_hit_targets.append(target)
	var knockback_force: float = data.knockback if data != null else 0.0
	CombatUtil.apply_hit(target, damage, is_crit, fly_velocity.normalized() * knockback_force, _source_id())
	_spawn_hit_fx(hit_position)
	AudioMgr.play_sfx("hit_crit" if is_crit else "hit_flesh", 0.05)

	if pierce_left > 0:
		pierce_left -= 1
		return
	_destroy()


func _impact(hit_position: Vector2, normal: Vector2) -> void:
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
