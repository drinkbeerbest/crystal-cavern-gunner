class_name CombatUtil
extends RefCounted
## CombatUtil —— 战斗通用工具（M3）。
##
## 统一"造成伤害"的入口与形状查询，供玩家子弹、激光、爆炸、技能、
## 敌人自爆（M4）、Boss 冲撞（M7）复用，避免每个来源各写一套命中逻辑。
##
## 受击契约：任何可受伤对象实现
##   `take_hit(amount: float, is_crit: bool, knockback: Vector2, source: int) -> void`
## 即可被本工具伤害（Player / TrainingDummy / Enemy / Boss 都遵守）。

const G := preload("res://scripts/core/game_const.gd")

const GROUP_ENEMIES: String = "enemies"
const GROUP_PLAYER: String = "player"
const GROUP_INTERACTABLE: String = "interactable"

## 形状查询单次最多返回的结果数
const MAX_SHAPE_RESULTS: int = 64
## 贯穿射线最多穿透的目标数
const MAX_RAY_PIERCE: int = 24


## 对一个目标施加伤害。返回是否真正命中（目标实现了受击契约）。
static func apply_hit(target: Node, amount: float, is_crit: bool, knockback: Vector2, source: int) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.has_method("take_hit"):
		return false
	target.take_hit(amount, is_crit, knockback, source)
	_request_damage_number(target, amount, is_crit)
	return true


## 统一飘字入口：目标自身不必各自发信号，由世界层监听后生成 DamageNumber
static func _request_damage_number(target: Node, amount: float, is_crit: bool) -> void:
	if amount <= 0.0 or not (target is Node2D):
		return
	var anchor: Vector2 = (target as Node2D).global_position + Vector2(0, -14)
	# is_player_damage = "飘字属于玩家受伤"，DamageNumber 据此染红
	var is_player_damage: bool = target.is_in_group(GROUP_PLAYER)
	EventBus.damage_number_requested.emit(anchor, amount, is_crit, is_player_damage)


## 暴击判定
static func roll_crit(rng: RandomNumberGenerator, chance: float) -> bool:
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	return rng.randf() < chance


## 带浮动的最终伤害
static func roll_damage(rng: RandomNumberGenerator, base: float, multiplier: float, variance: float, is_crit: bool, crit_multiplier: float) -> float:
	var value: float = base * multiplier
	if variance > 0.0:
		value *= rng.randf_range(1.0 - variance, 1.0 + variance)
	if is_crit:
		value *= crit_multiplier
	return maxf(roundf(value * 10.0) / 10.0, 1.0)


## 圆形范围伤害（爆炸 / 技能冲击波 / 自爆）。
## 返回被命中的节点数组。伤害按距离线性衰减到 50%。
static func area_damage(host: Node, center: Vector2, radius: float, damage: float, is_crit: bool,
		knockback: float, source: int, target_mask: int, ignore_nodes: Array = []) -> Array:
	var space: PhysicsDirectSpaceState2D = _space(host)
	if space == null or radius <= 0.0:
		return []
	var shape := CircleShape2D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, center)
	params.collision_mask = target_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var hits: Array = space.intersect_shape(params, MAX_SHAPE_RESULTS)
	var damaged: Array = []
	for hit: Dictionary in hits:
		var target: Variant = hit.get("collider")
		if target == null or not (target is Node2D) or not is_instance_valid(target):
			continue
		if ignore_nodes.has(target) or damaged.has(target):
			continue
		var node: Node2D = target
		var offset: Vector2 = node.global_position - center
		var distance: float = offset.length()
		if distance > radius:
			continue
		var dir: Vector2 = offset.normalized() if distance > 0.5 else Vector2.UP
		var falloff: float = lerpf(1.0, 0.5, clampf(distance / maxf(radius, 1.0), 0.0, 1.0))
		if apply_hit(node, damage * falloff, is_crit, dir * knockback, source):
			damaged.append(node)
	return damaged


## 贯穿射线：返回沿线的全部命中点，元素为
## {collider: Node2D, position: Vector2, normal: Vector2, blocked: bool}
## blocked=true 表示命中的是不可穿透的世界碰撞（墙体），其后不再有结果。
static func ray_hits_all(host: Node, from: Vector2, to: Vector2, mask: int, ignore_nodes: Array = []) -> Array:
	var space: PhysicsDirectSpaceState2D = _space(host)
	if space == null:
		return []
	var results: Array = []
	var exclude: Array[RID] = []
	for i: int in range(MAX_RAY_PIERCE):
		var query := PhysicsRayQueryParameters2D.create(from, to, mask, exclude)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		var rid: Variant = hit.get("rid")
		if rid != null:
			exclude.append(rid)
		var collider: Variant = hit.get("collider")
		if collider == null or not (collider is Node2D) or not is_instance_valid(collider):
			continue
		var is_damageable: bool = (collider as Node).has_method("take_hit")
		results.append({
			"collider": collider,
			"position": hit.get("position", to),
			"normal": hit.get("normal", Vector2.ZERO),
			"blocked": not is_damageable,
		})
		if not is_damageable:
			break
	return results


## 射线伤害：沿 from->to 对所有可受伤目标造成伤害，返回命中数与终点（用于画光束）。
static func ray_damage(host: Node, from: Vector2, to: Vector2, mask: int, damage: float,
		is_crit: bool, knockback: float, source: int, ignore_nodes: Array = []) -> Dictionary:
	var dir: Vector2 = to - from
	var length: float = dir.length()
	if length < 0.5:
		return {"hits": 0, "end": to}
	var hits: Array = ray_hits_all(host, from, to, mask, ignore_nodes)
	var count: int = 0
	var end: Vector2 = to
	for hit: Dictionary in hits:
		end = hit["position"]
		if bool(hit.get("blocked", false)):
			continue
		var target: Node2D = hit["collider"]
		if ignore_nodes.has(target):
			continue
		var kb_dir: Vector2 = dir.normalized()
		if apply_hit(target, damage, is_crit, kb_dir * knockback, source):
			count += 1
	return {"hits": count, "end": end}


## 找最近的敌人（追踪弹 / 敌人 AI 共用）
static func nearest_target(host: Node, from: Vector2, group: String, max_distance: float, ignore: Node = null) -> Node2D:
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return null
	var best: Node2D = null
	var best_distance: float = max_distance
	for node: Node in host.get_tree().get_nodes_in_group(group):
		if node == ignore or not (node is Node2D) or not is_instance_valid(node):
			continue
		if node.has_method("is_dead_or_disabled") and bool(node.call("is_dead_or_disabled")):
			continue
		var distance: float = from.distance_to((node as Node2D).global_position)
		if distance <= best_distance:
			best_distance = distance
			best = node
	return best


## 扇形范围内可受伤目标（近战挥砍）。只做筛选，不造成伤害。
static func arc_targets(host: Node, origin: Vector2, facing: Vector2, radius: float, half_arc_deg: float,
		target_mask: int, ignore_nodes: Array = []) -> Array:
	var out: Array = []
	var facing_dir: Vector2 = facing.normalized() if facing.length() > 0.01 else Vector2.RIGHT
	for node: Node in _query_nodes(host, origin, radius, target_mask, ignore_nodes):
		if not node.has_method("take_hit"):
			continue
		var offset: Vector2 = (node as Node2D).global_position - origin
		if offset.length() < 0.001 or absf(rad_to_deg(facing_dir.angle_to(offset.normalized()))) <= half_arc_deg:
			out.append(node)
	return out


## 纯形状查询（不造成伤害）
static func _query_nodes(host: Node, center: Vector2, radius: float, mask: int, ignore_nodes: Array) -> Array:
	var space: PhysicsDirectSpaceState2D = _space(host)
	if space == null:
		return []
	var shape := CircleShape2D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, center)
	params.collision_mask = mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var out: Array = []
	for hit: Dictionary in space.intersect_shape(params, MAX_SHAPE_RESULTS):
		var target: Variant = hit.get("collider")
		if target is Node2D and is_instance_valid(target) and not ignore_nodes.has(target) and not out.has(target):
			out.append(target)
	return out


## 近战挥砍：对扇形内目标造成伤害，返回命中数
static func melee_swing(host: Node, origin: Vector2, facing: Vector2, radius: float, half_arc_deg: float,
		damage: float, is_crit: bool, knockback: float, source: int, target_mask: int, ignore_nodes: Array = []) -> int:
	var targets: Array = arc_targets(host, origin, facing, radius, half_arc_deg, target_mask, ignore_nodes)
	var count: int = 0
	var facing_dir: Vector2 = facing.normalized() if facing.length() > 0.01 else Vector2.RIGHT
	for node: Node in targets:
		if apply_hit(node as Node2D, damage, is_crit, facing_dir * knockback, source):
			count += 1
	return count


static func _space(host: Node) -> PhysicsDirectSpaceState2D:
	if host == null or not is_instance_valid(host) or not (host is Node2D):
		return null
	var viewport: Viewport = (host as Node2D).get_viewport()
	if viewport == null:
		return null
	return viewport.world_2d.direct_space_state
