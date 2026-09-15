class_name DungeonLayout
extends RefCounted
## DungeonLayout —— 一层地牢的房间图（纯数据 + 生成算法）。
##
## 为什么是 RefCounted 而不是 Node：地牢生成只关心「有几间房、怎么连、各是什么房型」，
## 与节点树无关。保持纯逻辑后，无头测试可以一次生成上百层做不变量校验；
## 真实游玩时由 GameWorld 按当前房间逐间搭建（复用 RoomBuilder），换房只重建可见的那一间。
##
## 生成流程（见 generate）：
##   1. 在 GRID_SIDE x GRID_SIDE 的格子里随机游走长出一棵树：N 个普通房 + 1 个 Boss 房，
##      门洞只开在父子格之间，天然连通且不会有孤岛、不会有环；
##   2. 死路（只有 1 个邻居的房间）不够时重摇，保证 Boss 房与钥匙房都能落在支路末端；
##   3. BFS 求每格到起点的距离，最远的死路作 Boss 房，次远的死路作精英房（掉「地牢钥匙」）；
##   4. 宝箱房、商店房放在中段死路，其余为战斗房；
##   5. 按房型挑尺寸（起始房 / Boss 房固定，战斗房随机）。
##
## 房间字典字段：
##   index      房间序号（0 固定是起始房）
##   kind       G.RoomKind 的整数值
##   cell       在生成网格里的格子坐标（Vector2i）
##   size       房间瓦片尺寸（含四周一圈墙）
##   doors      {方向 int -> true}，方向见 Dir
##   neighbors  相邻房间序号数组
##   cleared    是否已清空（起始房初始为 true）
##   visited    玩家是否进去过

const G := preload("res://scripts/core/game_const.gd")

## 方向枚举：北 / 南 / 西 / 东（与 DIR_OFFSETS 一一对应）
enum Dir { NORTH, SOUTH, WEST, EAST }

const DIR_OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const DIR_KEYS: Array[String] = ["north", "south", "west", "east"]
const OPPOSITE_DIR: Array[int] = [Dir.SOUTH, Dir.NORTH, Dir.EAST, Dir.WEST]

## 生成网格边长：容纳「10 普通房 + 1 Boss 房」的随机游走仍有余量
const GRID_SIDE: int = 7
## 游走失败时的保护上限，避免极端随机数下死循环
const GROW_GUARD_MULTIPLIER: int = 240
## 一次游走可能长出近乎直线的树（死路太少），重试到死路数量够用为止
const GROW_ATTEMPTS: int = 16
## 至少要有几个「起始房以外的死路」：Boss 房与钥匙房都必须落在死路上，多留一个余量
const MIN_DEAD_ENDS: int = 3

var floor_index: int = 1
var seed_value: int = 0
var rooms: Array = []
var start_index: int = 0
var boss_index: int = -1
var elite_index: int = -1
var treasure_index: int = -1
var shop_index: int = -1


# ==================== 生成 ====================

## 生成一层地牢。rng 为空时自行随机（测试请传定种子的 rng 以便复现）。
static func generate(rng: RandomNumberGenerator = null, floor_index: int = 1) -> DungeonLayout:
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var layout := DungeonLayout.new()
	layout.floor_index = floor_index
	layout.seed_value = int(r.seed)
	var normal_target: int = r.randi_range(G.MIN_ROOMS_PER_FLOOR, G.MAX_ROOMS_PER_FLOOR)
	layout._build_rooms(_grow_best_tree(r, normal_target + 1), r)
	return layout


## 反复游走，取第一棵「死路数量达标」的树；都不达标就用死路最多的那棵。
## 重试消耗的随机数同样取自传入的 rng，因此同一种子仍然完全可复现。
static func _grow_best_tree(r: RandomNumberGenerator, total: int) -> Dictionary:
	var best: Dictionary = {}
	var best_dead_ends: int = -1
	for attempt: int in range(GROW_ATTEMPTS):
		var tree: Dictionary = _grow_tree(r, total)
		var dead_ends: int = _count_dead_ends(tree)
		if dead_ends >= MIN_DEAD_ENDS:
			return tree
		if dead_ends > best_dead_ends:
			best_dead_ends = dead_ends
			best = tree
	return best


## 随机游走长出一棵树：每次从已有格子里挑一个，往未占用方向扩一格。
## 返回 {"cells": Array[Vector2i], "parents": Array[int]}，parents[i] 是 i 的父格序号（起点为 -1）。
## 只保留父子关系意味着整层是一棵树：任意两间房之间只有一条通路，BFS 距离唯一，
## 而且「离起点最远的房间」必然是死路——Boss 房与掉钥匙的精英房正好要落在这种支路末端。
static func _grow_tree(r: RandomNumberGenerator, total: int) -> Dictionary:
	var start_cell := Vector2i(GRID_SIDE / 2, GRID_SIDE / 2)
	var cells: Array[Vector2i] = [start_cell]
	var parents: Array[int] = [-1]
	var cell_to_index: Dictionary = {start_cell: 0}
	var frontier: Array[int] = [0]
	var guard: int = maxi(total, 1) * GROW_GUARD_MULTIPLIER
	while cells.size() < total and guard > 0:
		guard -= 1
		if frontier.is_empty():
			break
		var pick: int = r.randi_range(0, frontier.size() - 1)
		var base_index: int = frontier[pick]
		var base: Vector2i = cells[base_index]
		var dirs: Array[int] = [Dir.NORTH, Dir.SOUTH, Dir.WEST, Dir.EAST]
		_shuffle_ints(dirs, r)
		var grew: bool = false
		for d: int in dirs:
			var candidate: Vector2i = base + DIR_OFFSETS[d]
			if cell_to_index.has(candidate):
				continue
			if candidate.x < 0 or candidate.y < 0 or candidate.x >= GRID_SIDE or candidate.y >= GRID_SIDE:
				continue
			cell_to_index[candidate] = cells.size()
			parents.append(base_index)
			cells.append(candidate)
			frontier.append(cells.size() - 1)
			grew = true
			break
		if not grew:
			# 这个格子四周都被占满，从待扩列表里摘掉
			frontier.remove_at(pick)
	return {"cells": cells, "parents": parents}


## 数一数有几个「没有子格」的房间（起始房不算，它不参与特殊房型挑选）
static func _count_dead_ends(tree: Dictionary) -> int:
	var parents: Array = tree.get("parents", [])
	var has_child: Dictionary = {}
	for p: Variant in parents:
		if int(p) >= 0:
			has_child[int(p)] = true
	var count: int = 0
	for i: int in range(parents.size()):
		if i == 0 or has_child.has(i):
			continue
		count += 1
	return count


func _build_rooms(tree: Dictionary, r: RandomNumberGenerator) -> void:
	rooms.clear()
	var cells: Array = tree.get("cells", [])
	var parents: Array = tree.get("parents", [])
	for i: int in range(cells.size()):
		rooms.append({
			"index": i,
			"kind": G.RoomKind.COMBAT,
			"cell": cells[i],
			"size": G.ROOM_SIZES[0],
			"doors": {},
			"neighbors": [],
			"cleared": false,
			"visited": false,
		})

	# 门洞只开在父子格之间，且双向对称登记
	for i: int in range(1, rooms.size()):
		var parent: int = int(parents[i]) if i < parents.size() else -1
		if parent < 0 or parent >= rooms.size():
			continue
		var d: int = direction_to(parent, i)
		if d >= 0:
			_link_doors(parent, i, d)

	var dist: Array[int] = bfs_distances(start_index)

	# 起始房
	rooms[start_index]["kind"] = G.RoomKind.START
	rooms[start_index]["size"] = G.START_ROOM_SIZE
	rooms[start_index]["cleared"] = true
	rooms[start_index]["visited"] = true

	# Boss 房：离起点最远的死路（玩家要穿过大半个地牢才碰得到）
	boss_index = _pick_room(dist, r, [], "far")
	# 精英房：掉「地牢钥匙」，开 Boss 房门的前置条件
	elite_index = _pick_room(dist, r, [boss_index], "far")
	# 宝箱房 / 商店房：放在中段，鼓励探索支线
	treasure_index = _pick_room(dist, r, [boss_index, elite_index], "mid")
	shop_index = _pick_room(dist, r, [boss_index, elite_index, treasure_index], "mid")

	_assign(boss_index, G.RoomKind.BOSS, G.BOSS_ROOM_SIZE)
	_assign(elite_index, G.RoomKind.ELITE, Vector2i.ZERO)
	_assign(treasure_index, G.RoomKind.TREASURE, Vector2i.ZERO)
	_assign(shop_index, G.RoomKind.SHOP, Vector2i.ZERO)

	# 其余战斗房随机挑尺寸
	for entry: Dictionary in rooms:
		if int(entry["kind"]) == G.RoomKind.COMBAT:
			entry["size"] = G.ROOM_SIZES[r.randi_range(0, G.ROOM_SIZES.size() - 1)]


## 写入房型；size 为 ZERO 表示沿用随机尺寸，index 非法时什么也不做
func _assign(index: int, kind: int, size: Vector2i) -> void:
	if index < 0 or index >= rooms.size():
		return
	rooms[index]["kind"] = kind
	if size != Vector2i.ZERO:
		rooms[index]["size"] = size


## 双向登记一扇门（含邻居表），避免出现单向门
func _link_doors(from_index: int, to_index: int, dir: int) -> void:
	(rooms[from_index]["doors"] as Dictionary)[dir] = true
	(rooms[to_index]["doors"] as Dictionary)[OPPOSITE_DIR[dir]] = true
	var forward: Array = rooms[from_index]["neighbors"]
	if not forward.has(to_index):
		forward.append(to_index)
	var backward: Array = rooms[to_index]["neighbors"]
	if not backward.has(from_index):
		backward.append(from_index)


## 按策略挑一间还没被占用的房：
##   far -> 距离最远（Boss / 精英）
##   mid -> 中段（宝箱 / 商店）
## 优先挑死路（只有 1 个邻居），死路被占完了才退回普通房间；
## 起始房与 excluded 里的房间永远不参与，保证四种特殊房型互不覆盖。
## 返回 -1 表示确实无房可挑（生成阶段已保证死路数量，正常不会发生）。
func _pick_room(dist: Array[int], r: RandomNumberGenerator, excluded: Array, mode: String) -> int:
	var dead_ends: Array[int] = []
	var others: Array[int] = []
	for i: int in range(rooms.size()):
		if i == start_index or excluded.has(i):
			continue
		if (rooms[i]["neighbors"] as Array).size() == 1:
			dead_ends.append(i)
		else:
			others.append(i)
	var candidates: Array[int] = dead_ends if not dead_ends.is_empty() else others
	if candidates.is_empty():
		return -1
	candidates.sort_custom(func(a: int, b: int) -> bool: return dist[a] > dist[b])
	if mode == "far":
		return candidates[0]
	var mid: int = candidates.size() / 2
	return candidates[r.randi_range(maxi(mid - 1, 0), mini(mid + 1, candidates.size() - 1))]


static func _shuffle_ints(list: Array[int], r: RandomNumberGenerator) -> void:
	for i: int in range(list.size() - 1, 0, -1):
		var j: int = r.randi_range(0, i)
		var tmp: int = list[i]
		list[i] = list[j]
		list[j] = tmp


# ==================== 查询 ====================

func room_count() -> int:
	return rooms.size()


## 普通房间数（不含 Boss 房）——验收口径里的「5-10 个普通房间」
func normal_room_count() -> int:
	return rooms.size() - (1 if boss_index >= 0 else 0)


func room(index: int) -> Dictionary:
	if index < 0 or index >= rooms.size():
		return {}
	return rooms[index]


func room_kind(index: int) -> int:
	return int(room(index).get("kind", -1))


func room_at_cell(cell: Vector2i) -> int:
	for i: int in range(rooms.size()):
		if (rooms[i]["cell"] as Vector2i) == cell:
			return i
	return -1


func rooms_of_kind(kind: int) -> Array:
	var out: Array = []
	for entry: Dictionary in rooms:
		if int(entry["kind"]) == kind:
			out.append(entry)
	return out


func neighbor_indexes(index: int) -> Array:
	return room(index).get("neighbors", [])


func door_dirs(index: int) -> Array[int]:
	var out: Array[int] = []
	for key: Variant in (room(index).get("doors", {}) as Dictionary).keys():
		out.append(int(key))
	out.sort()
	return out


## from_index 看向 to_index 的方向；不相邻返回 -1
func direction_to(from_index: int, to_index: int) -> int:
	if from_index < 0 or to_index < 0 or from_index >= rooms.size() or to_index >= rooms.size():
		return -1
	var delta: Vector2i = (rooms[to_index]["cell"] as Vector2i) - (rooms[from_index]["cell"] as Vector2i)
	for d: int in range(DIR_OFFSETS.size()):
		if DIR_OFFSETS[d] == delta:
			return d
	return -1


## 该方向的门是否通往 Boss 房（Boss 房门需要钥匙）
func is_boss_door(from_index: int, dir: int) -> bool:
	var target: int = neighbor_in_direction(from_index, dir)
	return target == boss_index


func neighbor_in_direction(from_index: int, dir: int) -> int:
	if dir < 0 or dir >= DIR_OFFSETS.size():
		return -1
	return room_at_cell((room(from_index).get("cell", Vector2i(-99, -99)) as Vector2i) + DIR_OFFSETS[dir])


## BFS 距离表（不可达为 -1）
func bfs_distances(from_index: int) -> Array[int]:
	var dist: Array[int] = []
	dist.resize(rooms.size())
	dist.fill(-1)
	if from_index < 0 or from_index >= rooms.size():
		return dist
	dist[from_index] = 0
	var queue: Array[int] = [from_index]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next_index: Variant in neighbor_indexes(current):
			var n: int = int(next_index)
			if dist[n] < 0:
				dist[n] = dist[current] + 1
				queue.append(n)
	return dist


func reachable_from(index: int) -> Array[int]:
	var out: Array[int] = []
	var dist: Array[int] = bfs_distances(index)
	for i: int in range(dist.size()):
		if dist[i] >= 0:
			out.append(i)
	return out


## 从起始房能否走遍所有房间（连通性验收）
func all_reachable() -> bool:
	return reachable_from(start_index).size() == rooms.size()


func has_key_room() -> bool:
	return elite_index >= 0 and elite_index < rooms.size()


## 调试 / 测试用的一行摘要
func describe() -> String:
	var kinds: Dictionary = {}
	for entry: Dictionary in rooms:
		var k: int = int(entry["kind"])
		kinds[k] = int(kinds.get(k, 0)) + 1
	return "floor=%d rooms=%d(normal=%d) kinds=%s start=%d boss=%d elite=%d treasure=%d shop=%d reachable=%s" % [
		floor_index, rooms.size(), normal_room_count(), str(kinds),
		start_index, boss_index, elite_index, treasure_index, shop_index, str(all_reachable()),
	]


# ==================== 方向工具 ====================

static func opposite_dir(dir: int) -> int:
	if dir < 0 or dir >= OPPOSITE_DIR.size():
		return -1
	return OPPOSITE_DIR[dir]


static func dir_key(dir: int) -> String:
	if dir < 0 or dir >= DIR_KEYS.size():
		return ""
	return DIR_KEYS[dir]


static func dir_offset(dir: int) -> Vector2i:
	if dir < 0 or dir >= DIR_OFFSETS.size():
		return Vector2i.ZERO
	return DIR_OFFSETS[dir]
