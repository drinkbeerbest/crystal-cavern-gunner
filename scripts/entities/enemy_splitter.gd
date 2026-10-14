class_name EnemySplitter
extends Enemy
## EnemySplitter —— 裂晶虫，**分裂**型（M9 新增原型）。
##
## 击杀它不会结束战斗，而是裂成两只更小的碎片。碎片极脆、不会再生，
## 所以"打掉大虫 → 顺手清两只碎片"是这个原型的完整节奏。
##
## 为什么要有它：原本四种普通怪全是"打掉就没了"，玩家的输出决策只有 DPS 竞赛。
## 分裂型把「该先打谁」变成问题——碎片会从尸体位置向玩家方向散开，
## 逼你选择「追出去清」还是「原地继续输出大虫」。
##
## 平衡约束：碎片不再分裂（否则指数爆炸）；碎片有独立 id（shard），
## 可以单独调血量/掉落；分裂时给一次明显的膨胀特效，告诉玩家"这东西裂开了"。

## 分裂时每只碎片相对母体的血量比例
const SHARD_HEALTH_RATIO: float = 0.34
## 碎片相对母体的速度比例
const SHARD_SPEED_RATIO: float = 1.25
## 分裂出的碎片数量
const SHARD_COUNT: int = 2
## 碎片与母体保持的最小距离（避免叠在尸体上）
const SHARD_SPREAD: float = 26.0

## 观测（测试用）
var splits_done: int = 0
var shards_spawned: Array = []


## 死亡时分裂：在基类结算掉落**之前**执行，所以碎片不会重复触发母体的掉落表
func _on_before_death() -> void:
	if splits_done > 0 or data.split_into.is_empty():
		return
	# 碎片必须由世界层生成（它要挂进实体层、参与 Y 排序、并注入弹道/特效层），
	# 所以这里只做"有没有世界"的前置检查，不要自己去找父节点当宿主。
	if world_node == null or not is_instance_valid(world_node):
		return
	if not world_node.has_method("spawn_enemy"):
		return
	var half: float = data.max_health * SHARD_HEALTH_RATIO
	for i: int in range(SHARD_COUNT):
		var angle: float = TAU * float(i) / float(SHARD_COUNT) + _split_angle_offset()
		var at: Vector2 = global_position + Vector2.from_angle(angle) * SHARD_SPREAD
		var shard: Enemy = world_node.spawn_enemy(data.split_into, at) as Enemy
		if shard == null:
			continue
		# 碎片是独立实例，直接改它的数值即可（不污染 TABLE，也不影响同 id 的其它怪）
		shard.max_health = half
		shard.health = half
		shard.data.max_health = half
		shard.data.move_speed = data.move_speed * SHARD_SPEED_RATIO
		shard.data.contact_damage = data.shard_contact_damage
		shard.set_target(target)
		shards_spawned.append(shard)
	splits_done += 1
	# 明确的"裂开"表现，避免玩家以为这一枪没打中
	AudioMgr.play_sfx("break_crate", 0.04, -6.0)
	Fx.play(_fx_host(), "ring", global_position, {
		"fps": 20.0, "scale": 1.2, "z_index": 12, "tint": Color(0.7, 0.9, 1.0, 0.9),
	})
	Fx.scatter(_fx_host(), "spark", global_position, 6, 24.0,
		{"fps": 26.0, "z_index": 12, "tint": Color(0.7, 0.9, 1.0, 0.8)})


## 让多只母体同帧死亡时碎片不重叠在同一角度
func _split_angle_offset() -> float:
	var seed_value: int = int(global_position.x * 0.7 + global_position.y * 1.3)
	return float(absi(seed_value) % 360) * (PI / 180.0)


## 行为：慢速逼近的血包式敌人，靠"死后分裂"而不是行为取胜。
## 刻意不做复杂的追击 AI——它的威胁完全来自分裂后的清理成本。
func _think(_delta: float) -> void:
	_refresh_target()
	if target == null:
		super._think(_delta)
		return
	var to_target: Vector2 = target.global_position - global_position
	if to_target.length_squared() > 0.01:
		facing = to_target.normalized()
	set_state(State.CHASE)
	move_velocity = facing * data.move_speed
