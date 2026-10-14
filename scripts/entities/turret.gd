class_name Turret
extends Node2D
## Turret —— 哨戒工程机的主动技能产物（可自动开火的固定炮台）。
##
## 它是「工程机」这个角色的立身之本：另外两个角色的技能都是**一次性爆发**，
## 只有炮台是「先占位、后收租」。冷却 12 秒意味着你必须提前想好往哪丢，
## 而不是被围住了才按技能。
##
## 实现上刻意做得很"笨"：固定不动、逐个瞄准、逐发开火。
## 它不该变成一台会走位会预判的怪物 AI——玩家的乐趣来自"放的位置好不好"。

const G := preload("res://scripts/core/game_const.gd")

## 部署时的一次性提示特效时长
const DEPLOY_FX_TIME: float = 0.5

var damage: float = 12.0
var fire_interval: float = 0.22
var life: float = 9.0
var seek_radius: float = 260.0
var bullet_speed: float = 420.0
## 归属者（用于伤害归属与"自家人不打自己人"）
var owner_id: int = 0

var bullet_layer: Node2D = null
var fx_layer: Node2D = null

## 观测计数（测试用）
var shots_fired: int = 0
var targets_engaged: int = 0

var _age: float = 0.0
var _cooldown: float = 0.0
var _flash: float = 0.0
var _rng := RandomNumberGenerator.new()
var _sprite: Sprite2D = null
var _base_ring: Sprite2D = null


func _ready() -> void:
	_rng.seed = hash("turret" + str(get_instance_id()) + str(GameState.run_seed))
	z_index = 2
	_build_nodes()


func _build_nodes() -> void:
	_base_ring = Sprite2D.new()
	_base_ring.texture = Fx.texture("glow_soft_blue")
	_base_ring.modulate = Color(0.6, 1.0, 0.7, 0.3)
	_base_ring.scale = Vector2.ONE * 0.5
	_base_ring.z_index = -1
	add_child(_base_ring)

	_sprite = Sprite2D.new()
	_sprite.texture = _tex_abs("res://assets/ui/icon_skill.png")
	_sprite.scale = Vector2.ONE * 0.9
	_sprite.position = Vector2(0, -8)
	add_child(_sprite)

	Fx.play(_fx_host(), "level_ring", position, {"fps": 16.0, "scale": 0.7, "z_index": 12})


static func _tex_abs(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _process(delta: float) -> void:
	_age += delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
	if _age >= life:
		_expire()
		return
	# 剩余寿命越少，底光越暗——给玩家一个"快没了"的视觉提示
	if _base_ring != null:
		var remain: float = clampf(1.0 - _age / maxf(life, 0.001), 0.0, 1.0)
		_base_ring.modulate = Color(0.6, 1.0, 0.7, 0.12 + 0.2 * remain * (0.6 + 0.4 * sin(_age * 4.0)))
		_base_ring.scale = Vector2.ONE * (0.4 + 0.14 * remain)
	if _sprite != null:
		# 开火瞬间闪一下，给玩家"这座炮台在干活"的反馈
		_sprite.modulate = Color(1, 1, 1).lerp(Color(2.2, 2.2, 2.2), clampf(_flash / 0.08, 0.0, 1.0))

	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown > 0.0:
		return
	var target: Node2D = _find_target()
	if target == null:
		return
	_fire_at(target.global_position)
	_cooldown = fire_interval


func _find_target() -> Node2D:
	var tree: SceneTree = get_tree()
	if tree == null or not is_inside_tree():
		return null
	var best: Node2D = null
	var best_distance: float = seek_radius
	for node: Node in tree.get_nodes_in_group(CombatUtil.GROUP_ENEMIES):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		if node.has_method("is_dead_or_disabled") and bool(node.call("is_dead_or_disabled")):
			continue
		var distance: float = (node as Node2D).global_position.distance_to(global_position)
		if distance <= best_distance:
			best_distance = distance
			best = node as Node2D
	return best


func _fire_at(target_position: Vector2) -> void:
	var direction: Vector2 = (target_position - global_position)
	if direction.length() < 0.01:
		return
	shots_fired += 1
	targets_engaged += 1
	_flash = 0.08
	var bullet := Bullet.new()
	bullet.from_player = true
	bullet.source = self
	bullet.fx_layer = fx_layer
	bullet.fly_velocity = direction.normalized() * bullet_speed
	bullet.damage = damage
	bullet.is_crit = false
	bullet.life = 1.2
	bullet.radius = 3.0
	bullet.trail_enabled = true
	bullet.position = global_position + direction.normalized() * 12.0 + Vector2(0, -6)
	var host: Node2D = _bullet_host()
	host.add_child(bullet)
	AudioMgr.play_sfx("shoot_smg", 0.02, -18.0)
	Fx.play(_fx_host(), "muzzle", bullet.position, {
		"fps": 30.0, "angle": direction.angle(), "scale": 0.6, "z_index": 11,
	})


func _expire() -> void:
	Fx.play(_fx_host(), "spark", global_position, {"fps": 24.0, "scale": 0.8, "z_index": 12})
	AudioMgr.play_sfx("empty", 0.02, -20.0)
	queue_free()


## 剩余寿命比例（HUD / 测试用）
func remain_ratio() -> float:
	return clampf(1.0 - _age / maxf(life, 0.001), 0.0, 1.0)


func _bullet_host() -> Node2D:
	if bullet_layer != null and is_instance_valid(bullet_layer):
		return bullet_layer
	var parent: Node = get_parent()
	return parent as Node2D if parent is Node2D else self


func _fx_host() -> Node2D:
	if fx_layer != null and is_instance_valid(fx_layer):
		return fx_layer
	return _bullet_host()
