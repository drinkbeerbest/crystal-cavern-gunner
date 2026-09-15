class_name EnemySpawner
extends Node
## EnemySpawner —— 房间敌人生成器与波次调度（M4）。
##
## 职责：
##   1. 在房间内部矩形里挑选合法生成点（避开墙体/障碍、避开玩家贴脸、避开已有敌人）；
##   2. 按 `EnemyDB.wave_for_room()` 的规划把一波敌人切成若干批次投放（批次间隔 G.WAVE_BATCH_DELAY）；
##   3. 把世界的实体层/弹道层/特效层注入每个敌人，并在生成后立即激活；
##   4. 统计存活数量，全部清完后发出 `wave_cleared`，供房间开门（M5）与 HUD 使用。
##
## 用法（世界层）：
##   spawner.setup(self, interior_rect, GameState.floor_index, G.RoomKind.COMBAT, seed)
##   spawner.start_wave()                      # 让 EnemyDB 按房型/层数自动规划
##   spawner.start_wave(["husk", "hexeye_elite"])  # 或显式指定（测试 / Boss 房小怪）

const G := preload("res://scripts/core/game_const.gd")

signal wave_started(ids: Array)
signal batch_spawned(batch_index: int, ids: Array)
signal wave_cleared

## 生成点尝试次数（失败则逐步放宽条件）
const SPAWN_ATTEMPTS: int = 48
## 放宽条件后的第二轮尝试次数（忽略与玩家的最小距离）
const SPAWN_ATTEMPTS_RELAXED: int = 24

var world: Node2D = null
var interior: Rect2 = Rect2()
var rng := RandomNumberGenerator.new()
var floor_index: int = 1
var room_kind: int = G.RoomKind.COMBAT

## 生成后是否立即 activate()（false 时交给基类的凝聚登场计时）
var activate_on_spawn: bool = true
## 死亡动画结束后是否自动释放节点（测试里设 false 便于断言）
var auto_free: bool = true

# ---------- 波次状态 ----------
var wave_ids: Array = []
var batches: Array = []
var pending_batches: Array = []
var spawned: Array = []
var batch_timer: float = -1.0
var active: bool = false
var cleared: bool = false
var total_spawned: int = 0
var batches_spawned: int = 0

var _entity_root: Node2D = null
var _bullet_layer: Node2D = null
var _fx_layer: Node2D = null
var _player: Node2D = null


# ==================== 装配 ====================

## 注入世界与房间内部矩形。world 需具备 entity_root / bullet_root / fx_root / player 属性。
func setup(p_world: Node2D, p_interior: Rect2, p_floor_index: int = 1,
		p_room_kind: int = G.RoomKind.COMBAT, p_seed: int = 0) -> void:
	world = p_world
	interior = p_interior
	floor_index = maxi(p_floor_index, 1)
	room_kind = p_room_kind
	_entity_root = _node2d_prop(p_world, "entity_root")
	_bullet_layer = _node2d_prop(p_world, "bullet_root")
	_fx_layer = _node2d_prop(p_world, "fx_root")
	_player = _node2d_prop(p_world, "player")
	rng.seed = p_seed if p_seed != 0 else hash(str(p_floor_index) + str(p_room_kind) + str(p_interior))


static func _node2d_prop(node: Node, prop: String) -> Node2D:
	if node == null:
		return null
	var value: Variant = node.get(prop)
	return value as Node2D if value is Node2D else null


func host() -> Node2D:
	if _entity_root != null and is_instance_valid(_entity_root):
		return _entity_root
	return world


func set_player(node: Node2D) -> void:
	_player = node


func player_node() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	if world != null:
		_player = _node2d_prop(world, "player")
	return _player


# ==================== 波次调度 ====================

## 开始一波。ids 为空时按房型/层数自动规划。返回本波全部敌人 id。
func start_wave(ids: Array = []) -> Array:
	wave_ids = ids.duplicate() if not ids.is_empty() else EnemyDB.wave_for_room(rng, floor_index, room_kind)
	batches = EnemyDB.split_batches(wave_ids, G.WAVE_BATCHES)
	pending_batches = batches.duplicate()
	spawned.clear()
	total_spawned = 0
	batches_spawned = 0
	batch_timer = -1.0
	cleared = false

	if wave_ids.is_empty():
		active = false
		cleared = true
		wave_cleared.emit()
		return wave_ids

	active = true
	_spawn_next_batch()
	wave_started.emit(wave_ids)
	return wave_ids


func _spawn_next_batch() -> void:
	if pending_batches.is_empty():
		return
	var batch: Array = pending_batches.pop_front()
	batches_spawned += 1
	for enemy_id: Variant in batch:
		spawn_enemy(str(enemy_id))
	batch_spawned.emit(batches_spawned, batch)
	if not pending_batches.is_empty():
		batch_timer = G.WAVE_BATCH_DELAY


## 生成单个敌人；at_position 为空时自动选点。返回 null 表示 id 未知或没有宿主。
func spawn_enemy(enemy_id: String, at_position: Variant = null) -> Enemy:
	var enemy: Enemy = EnemyDB.create(enemy_id, floor_index)
	if enemy == null:
		return null
	var host_node: Node2D = host()
	if host_node == null:
		return null
	var radius: float = enemy.data.body_radius
	var position_value: Vector2
	if at_position is Vector2:
		position_value = at_position
	else:
		position_value = pick_spawn_position(radius)
	enemy.position = position_value
	enemy.bullet_layer = _bullet_layer
	enemy.fx_layer = _fx_layer
	enemy.world_node = world
	enemy.auto_free = auto_free
	host_node.add_child(enemy)
	enemy.set_target(player_node())
	if activate_on_spawn:
		enemy.activate()
	spawned.append(enemy)
	total_spawned += 1
	return enemy


func _process(delta: float) -> void:
	prune_freed()
	if not active:
		return
	if batch_timer >= 0.0:
		batch_timer -= delta
		if batch_timer <= 0.0:
			batch_timer = -1.0
			_spawn_next_batch()
		return
	# 所有批次都已投放，且场上没有存活敌人 -> 本波清空
	if pending_batches.is_empty() and alive_count() == 0:
		active = false
		cleared = true
		wave_cleared.emit()


# ==================== 生成点选择 ====================

## 在房间内部挑一个合法生成点：不压墙/障碍、不贴脸玩家、不与已有敌人重叠
func pick_spawn_position(radius: float = 8.0) -> Vector2:
	var shrunk: Rect2 = interior.grow(-maxf(G.WAVE_SPAWN_MARGIN, radius + 2.0))
	if shrunk.size.x <= 1.0 or shrunk.size.y <= 1.0:
		shrunk = interior
	var fallback: Vector2 = shrunk.get_center()
	var player_node: Node2D = player_node()

	for attempt: int in range(SPAWN_ATTEMPTS):
		var candidate := Vector2(
				rng.randf_range(shrunk.position.x, shrunk.end.x),
				rng.randf_range(shrunk.position.y, shrunk.end.y))
		if _is_valid_spawn(candidate, radius, player_node, true):
			return candidate

	# 放宽：不再要求与玩家保持距离（小房间里可能无处可躲）
	for attempt: int in range(SPAWN_ATTEMPTS_RELAXED):
		var candidate := Vector2(
				rng.randf_range(shrunk.position.x, shrunk.end.x),
				rng.randf_range(shrunk.position.y, shrunk.end.y))
		if _is_valid_spawn(candidate, radius, player_node, false):
			return candidate

	# 最后兜底：只要不压墙就行
	for attempt: int in range(SPAWN_ATTEMPTS_RELAXED):
		var candidate := Vector2(
				rng.randf_range(shrunk.position.x, shrunk.end.x),
				rng.randf_range(shrunk.position.y, shrunk.end.y))
		if not _position_blocked(candidate, radius):
			return candidate
	return fallback


func _is_valid_spawn(candidate: Vector2, radius: float, player_node: Node2D, respect_player_distance: bool) -> bool:
	if _position_blocked(candidate, radius):
		return false
	if respect_player_distance and player_node != null and is_instance_valid(player_node):
		if candidate.distance_to(player_node.global_position) < G.WAVE_MIN_DISTANCE_TO_PLAYER:
			return false
	return not _overlaps_enemies(candidate, radius)


## 是否与墙体/障碍重叠（用圆形形状查询世界层）
func _position_blocked(candidate: Vector2, radius: float) -> bool:
	var space: PhysicsDirectSpaceState2D = _space()
	if space == null:
		return false
	var shape := CircleShape2D.new()
	shape.radius = radius + 2.0
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, candidate)
	params.collision_mask = G.LAYER_WORLD
	params.collide_with_bodies = true
	params.collide_with_areas = true
	return not space.intersect_shape(params, 4).is_empty()


func _space() -> PhysicsDirectSpaceState2D:
	var node: Node = world if world != null else self
	if node == null or not node.is_inside_tree():
		return null
	var world_2d: World2D = node.get_world_2d()
	return world_2d.direct_space_state if world_2d != null else null


## 是否与已生成的敌人靠得太近（分离力能推开，但生成时就重叠很难看）
func _overlaps_enemies(candidate: Vector2, radius: float) -> bool:
	for entry: Variant in spawned:
		# 先判 is_instance_valid 再用 `is`：对已释放对象做 `is` 会直接抛脚本错误
		if not is_instance_valid(entry) or not (entry is Enemy):
			continue
		var other: Enemy = entry
		if other.dead:
			continue
		var min_distance: float = radius + other.data.body_radius + G.ENEMY_SEPARATION_PADDING
		if candidate.distance_to(other.global_position) < min_distance:
			return true
	return false


# ==================== 状态查询 ====================

## 清掉 spawned 里已被释放的引用。
## 敌人死亡动画播完会 queue_free，列表里却仍留着旧引用；
## 不清理的话每次查询都在遍历幽灵对象（且 `is` 判定会报脚本错误）。
func prune_freed() -> void:
	var keep: Array = []
	for entry: Variant in spawned:
		if is_instance_valid(entry):
			keep.append(entry)
	if keep.size() != spawned.size():
		spawned = keep


## 场上存活敌人数（含尚未激活的）
func alive_count() -> int:
	var count: int = 0
	for entry: Variant in spawned:
		if is_instance_valid(entry) and entry is Enemy and not (entry as Enemy).dead:
			count += 1
	return count


func alive_enemies() -> Array:
	var out: Array = []
	for entry: Variant in spawned:
		if is_instance_valid(entry) and entry is Enemy and not (entry as Enemy).dead:
			out.append(entry)
	return out


func enemies_of_archetype(archetype: int) -> Array:
	var out: Array = []
	for enemy: Variant in alive_enemies():
		if (enemy as Enemy).data != null and (enemy as Enemy).data.archetype == archetype:
			out.append(enemy)
	return out


## 立即杀掉全部存活敌人（调试 / 清房用），返回击杀数量
func kill_all() -> int:
	var count: int = 0
	for enemy: Variant in alive_enemies():
		(enemy as Enemy).die()
		count += 1
	return count


## 移除全部敌人节点（换房间时用），不触发死亡结算
func despawn_all() -> void:
	for entry: Variant in spawned:
		if is_instance_valid(entry):
			(entry as Node).queue_free()
	spawned.clear()
	active = false
	cleared = true
	pending_batches.clear()
	batch_timer = -1.0
