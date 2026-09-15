extends TestSuite
## 地牢生成测试套件（M5）。
##
## DungeonLayout 是纯逻辑（RefCounted），所以这里可以一次性生成上百层做不变量校验：
##   1. 房间规模：每层普通房间数落在 5-10 区间，Boss 房额外一间且全层唯一
##   2. 特殊房型：起始房 / 精英（钥匙）房 / 宝箱房 / 商店房 各一间且互不重叠
##   3. 连通性：从起始房 BFS 能走遍所有房间；门洞双向对称，不存在单向门
##   4. 布局意图：Boss 房是最远死路、精英房也是死路（钥匙要绕路去拿）
##   5. 房间尺寸：起始房 / Boss 房固定尺寸，其余取自 ROOM_SIZES
##   6. 确定性：同一种子两次生成结果完全一致（存档 / 复现的前提）
##   7. 与波次配置衔接：战斗类房型能规划出非空且合法的敌人波次，起始房与商店房不出怪，
##      Boss 房不吃普通波次（留给 Boss 流程），且层数越深同房型敌人越多

const G := preload("res://scripts/core/game_const.gd")

## 每层跑多少个种子（不变量校验的样本量）
const SEEDS_PER_FLOOR: int = 120
const FLOORS: Array[int] = [1, 2, 3]
## 门洞对称性单独抽样（开销更大，样本少一些）
const SYMMETRY_SEEDS: int = 40


func suite_name() -> String:
	return "dungeon"


func run(t: Node) -> void:
	_test_layout_invariants(t)
	_test_room_diversity(t)
	_test_door_symmetry(t)
	_test_determinism(t)
	_test_query_api(t)
	_test_wave_planning(t)


# ==================== 1-5. 逐层不变量 ====================

func _test_layout_invariants(t: Node) -> void:
	var bad_normal: Array[String] = []
	var bad_boss: Array[String] = []
	var bad_special: Array[String] = []
	var bad_reach: Array[String] = []
	var bad_boss_place: Array[String] = []
	var bad_size: Array[String] = []
	var bad_cell: Array[String] = []
	var total: int = 0

	for floor_index: int in FLOORS:
		for i: int in range(SEEDS_PER_FLOOR):
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + i * 17 + floor_index * 977
			var seed_value: int = int(rng.seed)
			var layout: DungeonLayout = DungeonLayout.generate(rng, floor_index)
			total += 1
			var tag: String = "第%d层 种子%d" % [floor_index, seed_value]

			# 1. 普通房间数在 5-10，Boss 房唯一
			var normal: int = layout.normal_room_count()
			if normal < G.MIN_ROOMS_PER_FLOOR or normal > G.MAX_ROOMS_PER_FLOOR:
				bad_normal.append("%s（普通房 %d）" % [tag, normal])
			if layout.rooms_of_kind(G.RoomKind.BOSS).size() != 1 or layout.boss_index < 0:
				bad_boss.append(tag)

			# 2. 特殊房型各一间且互不重叠
			if not _specials_unique(layout):
				bad_special.append("%s（start=%d boss=%d elite=%d treasure=%d shop=%d）" % [
					tag, layout.start_index, layout.boss_index, layout.elite_index,
					layout.treasure_index, layout.shop_index])

			# 3. 连通性
			if not layout.all_reachable():
				bad_reach.append("%s（可达 %d/%d）" % [tag,
					layout.reachable_from(layout.start_index).size(), layout.room_count()])

			# 4. Boss 房与精英房都是死路，且 Boss 房离起点最远
			var dist: Array[int] = layout.bfs_distances(layout.start_index)
			var farthest: int = 0
			for d: int in dist:
				farthest = maxi(farthest, d)
			var boss_neighbors: int = layout.neighbor_indexes(layout.boss_index).size()
			var elite_neighbors: int = layout.neighbor_indexes(layout.elite_index).size()
			if boss_neighbors != 1 or elite_neighbors != 1 or dist[layout.boss_index] != farthest:
				bad_boss_place.append("%s（boss 邻居 %d 距离 %d/%d，elite 邻居 %d）" % [
					tag, boss_neighbors, dist[layout.boss_index], farthest, elite_neighbors])

			# 5. 房间尺寸
			var wrong_size: String = _check_sizes(layout)
			if not wrong_size.is_empty():
				bad_size.append("%s（%s）" % [tag, wrong_size])

			# 格子不重叠（重叠会导致门洞互相穿墙）
			var used: Dictionary = {}
			for entry: Dictionary in layout.rooms:
				var cell: Vector2i = entry["cell"]
				if used.has(cell):
					bad_cell.append(tag)
					break
				used[cell] = true

	t.check(bad_normal.is_empty(), "每层普通房间数都在 %d-%d 区间（异常 %d/%d %s）" % [
		G.MIN_ROOMS_PER_FLOOR, G.MAX_ROOMS_PER_FLOOR, bad_normal.size(), total, _preview(bad_normal)])
	t.check(bad_boss.is_empty(), "每层 Boss 房唯一（异常 %d/%d %s）" % [bad_boss.size(), total, _preview(bad_boss)])
	t.check(bad_special.is_empty(), "起始房/精英房/宝箱房/商店房各一间且不重叠（异常 %d/%d %s）" % [
		bad_special.size(), total, _preview(bad_special)])
	t.check(bad_reach.is_empty(), "从起始房可走遍全部房间（异常 %d/%d %s）" % [
		bad_reach.size(), total, _preview(bad_reach)])
	t.check(bad_boss_place.is_empty(), "Boss 房是最远死路、精英房也是死路（异常 %d/%d %s）" % [
		bad_boss_place.size(), total, _preview(bad_boss_place)])
	t.check(bad_size.is_empty(), "房间尺寸符合房型约定（异常 %d/%d %s）" % [
		bad_size.size(), total, _preview(bad_size)])
	t.check(bad_cell.is_empty(), "生成网格里的房间格子互不重叠（异常 %d/%d %s）" % [
		bad_cell.size(), total, _preview(bad_cell)])


func _specials_unique(layout: DungeonLayout) -> bool:
	var marks: Array[int] = [layout.start_index, layout.boss_index, layout.elite_index,
		layout.treasure_index, layout.shop_index]
	for m: int in marks:
		if m < 0 or m >= layout.room_count():
			return false
	var seen: Dictionary = {}
	for m: int in marks:
		if seen.has(m):
			return false
		seen[m] = true
	return layout.room_kind(layout.start_index) == G.RoomKind.START \
			and layout.room_kind(layout.boss_index) == G.RoomKind.BOSS \
			and layout.room_kind(layout.elite_index) == G.RoomKind.ELITE \
			and layout.room_kind(layout.treasure_index) == G.RoomKind.TREASURE \
			and layout.room_kind(layout.shop_index) == G.RoomKind.SHOP


## 返回第一个不合规的尺寸描述，全部合规则返回空串
func _check_sizes(layout: DungeonLayout) -> String:
	for entry: Dictionary in layout.rooms:
		var kind: int = int(entry["kind"])
		var size: Vector2i = entry["size"]
		if kind == G.RoomKind.START:
			if size != G.START_ROOM_SIZE:
				return "起始房尺寸 %s" % str(size)
		elif kind == G.RoomKind.BOSS:
			if size != G.BOSS_ROOM_SIZE:
				return "Boss 房尺寸 %s" % str(size)
		elif not _in_room_sizes(size):
			return "房间 %d 尺寸 %s 不在 ROOM_SIZES 里" % [int(entry["index"]), str(size)]
	return ""


func _in_room_sizes(size: Vector2i) -> bool:
	for candidate: Vector2i in G.ROOM_SIZES:
		if candidate == size:
			return true
	return false


# ==================== 房间数分布 ====================

func _test_room_diversity(t: Node) -> void:
	var normal_min: int = 999
	var normal_max: int = -1
	var combat_min: int = 999
	var total_rooms_min: int = 999
	var total_rooms_max: int = -1
	for floor_index: int in FLOORS:
		for i: int in range(SEEDS_PER_FLOOR):
			var rng := RandomNumberGenerator.new()
			rng.seed = 7000 + i * 31 + floor_index * 149
			var layout: DungeonLayout = DungeonLayout.generate(rng, floor_index)
			normal_min = mini(normal_min, layout.normal_room_count())
			normal_max = maxi(normal_max, layout.normal_room_count())
			total_rooms_min = mini(total_rooms_min, layout.room_count())
			total_rooms_max = maxi(total_rooms_max, layout.room_count())
			combat_min = mini(combat_min, layout.rooms_of_kind(G.RoomKind.COMBAT).size())

	t.eq(normal_min, G.MIN_ROOMS_PER_FLOOR, "样本里出现过最少普通房间数（下限可达）")
	t.eq(normal_max, G.MAX_ROOMS_PER_FLOOR, "样本里出现过最多普通房间数（上限可达）")
	t.eq(total_rooms_min, G.MIN_ROOMS_PER_FLOOR + 1, "总房间数下限 = 普通房下限 + Boss 房")
	t.eq(total_rooms_max, G.MAX_ROOMS_PER_FLOOR + 1, "总房间数上限 = 普通房上限 + Boss 房")
	t.gte(float(combat_min), 1.0, "每层至少留一间纯战斗房（特殊房型不挤占战斗内容）")


# ==================== 门洞对称性 ====================

func _test_door_symmetry(t: Node) -> void:
	var bad_doors: Array[String] = []
	var bad_neighbors: Array[String] = []
	var checked: int = 0
	for i: int in range(SYMMETRY_SEEDS):
		var rng := RandomNumberGenerator.new()
		rng.seed = 424242 + i * 13
		var layout: DungeonLayout = DungeonLayout.generate(rng, (i % 3) + 1)
		checked += 1
		for index: int in range(layout.room_count()):
			for dir: int in layout.door_dirs(index):
				var other: int = layout.neighbor_in_direction(index, dir)
				if other < 0:
					bad_doors.append("房 %d 朝 %s 有门但没有邻居" % [index, DungeonLayout.dir_key(dir)])
					continue
				var back: int = DungeonLayout.opposite_dir(dir)
				if not layout.door_dirs(other).has(back):
					bad_doors.append("房 %d -> 房 %d 单向门（对面缺 %s）" % [
						index, other, DungeonLayout.dir_key(back)])
				if not layout.neighbor_indexes(index).has(other):
					bad_neighbors.append("房 %d 的门通向 %d 但邻居表里没有" % [index, other])
			# 邻居表里的每个房间都应能在某个方向上找到
			for neighbor: Variant in layout.neighbor_indexes(index):
				if layout.direction_to(index, int(neighbor)) < 0:
					bad_neighbors.append("房 %d 的邻居 %d 不在任何方向上" % [index, int(neighbor)])

	t.check(bad_doors.is_empty(), "门洞双向对称（抽检 %d 层，异常 %d %s）" % [
		checked, bad_doors.size(), _preview(bad_doors)])
	t.check(bad_neighbors.is_empty(), "门洞与邻居表一致（抽检 %d 层，异常 %d %s）" % [
		checked, bad_neighbors.size(), _preview(bad_neighbors)])


# ==================== 确定性 ====================

func _test_determinism(t: Node) -> void:
	var mismatch: Array[String] = []
	for i: int in range(20):
		var seed_value: int = 90210 + i * 7
		var first: DungeonLayout = DungeonLayout.generate(_rng(seed_value), 2)
		var second: DungeonLayout = DungeonLayout.generate(_rng(seed_value), 2)
		if first.describe() != second.describe():
			mismatch.append("种子 %d 摘要不同" % seed_value)
			continue
		for index: int in range(first.room_count()):
			var a: Dictionary = first.room(index)
			var b: Dictionary = second.room(index)
			if int(a["kind"]) != int(b["kind"]) or (a["cell"] as Vector2i) != (b["cell"] as Vector2i) \
					or (a["size"] as Vector2i) != (b["size"] as Vector2i):
				mismatch.append("种子 %d 房间 %d 不一致" % [seed_value, index])
				break
	t.check(mismatch.is_empty(), "同一种子两次生成结果完全一致（异常 %d %s）" % [
		mismatch.size(), _preview(mismatch)])

	var random_a: DungeonLayout = DungeonLayout.generate(null, 1)
	t.check(random_a != null and random_a.room_count() > 0, "不传 rng 时也能生成有效地牢")


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# ==================== 查询 API ====================

func _test_query_api(t: Node) -> void:
	var layout: DungeonLayout = DungeonLayout.generate(_rng(20260914), 1)
	t.gte(float(layout.room_count()), float(G.MIN_ROOMS_PER_FLOOR + 1), "样本层房间数达到下限")
	t.eq(layout.start_index, 0, "起始房固定为 0 号房")
	t.eq(layout.floor_index, 1, "记录了所属层数")

	var dist: Array[int] = layout.bfs_distances(layout.start_index)
	t.eq(dist[layout.start_index], 0, "起始房到自己的距离为 0")
	var unreachable: int = 0
	for d: int in dist:
		if d < 0:
			unreachable += 1
	t.eq(unreachable, 0, "所有房间的距离都已算出（无 -1）")
	t.eq(layout.reachable_from(layout.boss_index).size(), layout.room_count(),
			"从 Boss 房反向也能走遍全图")

	var first_neighbor: int = int(layout.neighbor_indexes(layout.start_index)[0])
	var dir: int = layout.direction_to(layout.start_index, first_neighbor)
	t.neq(dir, -1, "起始房到相邻房间能算出方向")
	t.eq(layout.neighbor_in_direction(layout.start_index, dir), first_neighbor,
			"按方向反查邻居能回到同一个房间")
	t.eq(layout.direction_to(first_neighbor, layout.start_index), DungeonLayout.opposite_dir(dir),
			"反向方向正好是对向")
	t.eq(layout.direction_to(layout.start_index, layout.start_index), -1, "自己对自己没有方向")
	t.eq(layout.neighbor_in_direction(layout.start_index, 99), -1, "非法方向返回 -1")
	t.check(layout.room(-1).is_empty(), "越界房间返回空字典")
	t.eq(layout.room_kind(9999), -1, "越界房型返回 -1")
	t.eq(layout.rooms_of_kind(G.RoomKind.START).size(), 1, "按房型筛选：起始房一间")
	var boss_neighbor: int = int(layout.neighbor_indexes(layout.boss_index)[0])
	var boss_dir: int = layout.direction_to(boss_neighbor, layout.boss_index)
	t.check(layout.is_boss_door(boss_neighbor, boss_dir), "通往 Boss 房的那扇门被标记为 Boss 门（需要钥匙）")
	t.check(not layout.is_boss_door(layout.boss_index, layout.direction_to(layout.boss_index, boss_neighbor)),
			"Boss 房朝外的门不算 Boss 门")
	var boss_doors: int = 0
	for index: int in range(layout.room_count()):
		for door_dir: int in layout.door_dirs(index):
			if layout.is_boss_door(index, door_dir):
				boss_doors += 1
	t.eq(boss_doors, 1, "全层只有一扇 Boss 门")
	t.check(layout.has_key_room(), "本层存在掉钥匙的精英房")
	t.check(layout.describe().contains("rooms="), "describe() 给出可读摘要：%s" % layout.describe())


# ==================== 与波次配置衔接 ====================

func _test_wave_planning(t: Node) -> void:
	var empty_wave: Array[String] = []
	var unknown_enemy: Array[String] = []
	var unexpected_wave: Array[String] = []
	var boss_wave_leak: Array[String] = []
	var created: Array[Node] = []
	for i: int in range(12):
		var floor_index: int = (i % 3) + 1
		var layout: DungeonLayout = DungeonLayout.generate(_rng(555 + i * 101), floor_index)
		for entry: Dictionary in layout.rooms:
			var kind: int = int(entry["kind"])
			var wave: Array = EnemyDB.wave_for_room(_rng(31337 + i), floor_index, kind)
			match kind:
				G.RoomKind.START, G.RoomKind.SHOP:
					# 起始房与商店房是安全区，普通波次表不该出怪
					if not wave.is_empty():
						unexpected_wave.append("第%d层 %s 房出了怪" % [floor_index, _kind_name(kind)])
				G.RoomKind.BOSS:
					# Boss 房的敌人由 Boss 流程（M8）单独投放，这里只校验它不吃普通波次
					if not wave.is_empty():
						boss_wave_leak.append("第%d层 Boss 房走了普通波次" % floor_index)
				_:
					if wave.is_empty():
						empty_wave.append("第%d层 %s 房没有敌人" % [floor_index, _kind_name(kind)])
						continue
					for enemy_id: Variant in wave:
						var instance: Enemy = EnemyDB.create(str(enemy_id), floor_index)
						if instance == null:
							unknown_enemy.append(str(enemy_id))
						else:
							created.append(instance)

	# 递增难度：同一房型、同一个 rng 起点，第 3 层的敌人数量要多于第 1 层
	var shallow: int = EnemyDB.wave_count(_rng(4242), 1, G.RoomKind.COMBAT)
	var deep: int = EnemyDB.wave_count(_rng(4242), G.TOTAL_FLOORS, G.RoomKind.COMBAT)

	t.check(empty_wave.is_empty(), "战斗类房型都能规划出非空波次（异常 %d %s）" % [
		empty_wave.size(), _preview(empty_wave)])
	t.check(unexpected_wave.is_empty(), "起始房与商店房不出怪（异常 %d %s）" % [
		unexpected_wave.size(), _preview(unexpected_wave)])
	t.check(boss_wave_leak.is_empty(), "Boss 房不吃普通波次（留给 Boss 流程投放，异常 %d %s）" % [
		boss_wave_leak.size(), _preview(boss_wave_leak)])
	t.gt(float(deep), float(shallow), "层数越深同房型敌人越多（第1层 %d → 第%d层 %d）" % [
		shallow, G.TOTAL_FLOORS, deep])
	t.check(unknown_enemy.is_empty(), "波次里的敌人 id 都能建出实例（异常 %d %s）" % [
		unknown_enemy.size(), _preview(unknown_enemy)])

	# 上面为了校验工厂而 new 出来的敌人没有进场景树，必须手动释放，否则整轮跑完会泄漏几百个节点
	for instance: Node in created:
		instance.free()


func _kind_name(kind: int) -> String:
	match kind:
		G.RoomKind.START: return "起始"
		G.RoomKind.COMBAT: return "战斗"
		G.RoomKind.ELITE: return "精英"
		G.RoomKind.TREASURE: return "宝箱"
		G.RoomKind.SHOP: return "商店"
		G.RoomKind.BOSS: return "Boss"
	return "未知"


## 失败样本只展示前 3 条，避免刷屏
func _preview(list: Array[String]) -> String:
	if list.is_empty():
		return ""
	var shown: Array[String] = []
	for i: int in range(mini(3, list.size())):
		shown.append(list[i])
	return str(shown)
