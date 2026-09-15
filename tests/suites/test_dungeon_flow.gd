extends TestSuite
## test_dungeon_flow —— M5 地牢「房间流程」验收（无头）。
##
## test_dungeon.gd 验的是纯逻辑布局不变量（房间数、Boss 唯一、连通性、确定性）；
## 本套件验的是把布局接进 GameWorld 之后的真实运行流程：
##   1. 起始房：落地即安全房、门全开、相机 bounds 跟随房间尺寸；
##   2. 战斗房：进房关门开波 -> 清怪 -> 标记 cleared -> 重新开门；
##   3. 门传送：走进开着的门真的换房，落脚点在新房门内侧；
##   4. 精英房：清怪掉地牢钥匙，踩上去写入 GameState.has_floor_key；
##   5. Boss 门：上锁不放行；有钥匙时开门、消耗钥匙并进入 Boss 房；
##   6. Boss 房清空 -> 传送门激活 -> 踩上去换层，金币/武器/生命跨层保留（含 25% 回血）；
##   7. 特殊房型：宝箱房开箱结算、商店房花钱买货并把库存写回房间数据；
##   8. 层内进度：已清空的房间走回头路不再刷怪、门保持开启。
##
## run() 是协程：换房、开门、钥匙、传送门都要等物理帧让 Area2D 真的检出重叠。

const G := preload("res://scripts/core/game_const.gd")

## 固定种子：布局与房间内容都可复现
const TEST_SEED: int = 20260915

## 沙包血线：避免测试途中玩家被打死把世界标记成 finished
const TEST_PLAYER_HEALTH: float = 4000.0


func suite_name() -> String:
	return "地牢房间流程 (M5)"


func run(t: Node) -> void:
	await _test_start_room(t)
	await _test_combat_room_doors(t)
	await _test_door_travel(t)
	await _test_elite_key(t)
	await _test_boss_door_lock(t)
	await _test_portal_and_floor_advance(t)
	await _test_treasure_and_shop(t)
	await _test_revisit_cleared_room(t)


# ==================== 公共工具 ====================

## 建世界：先脱离物理 flush 窗口再 add_child。
## 房间拆建会动碰撞形状，若 _ready 落在引擎 flush queries 期间会刷
## "Can't change this state while flushing queries"，所以这里显式等一帧。
func _make_world(t: Node, seed_value: int = TEST_SEED) -> GameWorld:
	await t.get_tree().physics_frame
	GameState.new_run(seed_value)
	var world := GameWorld.new()
	world.name = "DungeonWorld"
	# 必须在 add_child 之前打开：_ready 里按这个开关决定走地牢还是试验场
	world.dungeon_mode = true
	t.add_child(world)
	_tough_player(world)
	return world


func _free_world(t: Node, world: GameWorld) -> void:
	if world == null:
		return
	world.clear_entities(false)
	world.queue_free()
	await t.get_tree().process_frame
	await t.get_tree().physics_frame


func _tough_player(world: GameWorld) -> Player:
	var player: Player = world.player
	player.stats["shield"] = 0.0
	player.stats["health"] = TEST_PLAYER_HEALTH
	player.clear_invulnerable()
	return player


## 等待 count 帧。恢复点固定落在 physics_frame 续体（物理步开头），
## 此时引擎不在 flush queries，测试里才能安全改碰撞/节点状态。
func _frames(t: Node, count: int) -> void:
	for i: int in range(count):
		await t.get_tree().process_frame
		await t.get_tree().physics_frame


## 轮询等待条件成立，返回用掉的帧数（超时则返回 max_frames）
func _wait_until(t: Node, condition: Callable, max_frames: int = 240) -> int:
	var frames: int = 0
	while frames < max_frames and not bool(condition.call()):
		await t.get_tree().process_frame
		await t.get_tree().physics_frame
		frames += 1
	return frames


## rooms_of_kind 返回的是房间数据字典，取里面的 index
func _first_room_of_kind(world: GameWorld, kind: int) -> int:
	var list: Array = world.layout.rooms_of_kind(kind)
	return int(list[0]["index"]) if not list.is_empty() else -1


func _door_to(world: GameWorld, target_index: int) -> Door:
	for entry: Variant in world.doors:
		if is_instance_valid(entry) and (entry as Door).target_index == target_index:
			return entry
	return null


## 门口 -> 房间内侧的偏移（用来把玩家"站"进门洞里）
func _inward_offset(dir: int) -> Vector2:
	match dir:
		0: return Vector2(0, 12)    # 北门：往 +Y 进屋
		1: return Vector2(0, -12)   # 南门
		2: return Vector2(12, 0)    # 西门
		3: return Vector2(-12, 0)   # 东门
	return Vector2.ZERO


# ==================== 1. 起始房 ====================

func _test_start_room(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 4)
	t.not_null(world.layout, "地牢世界生成了布局")
	t.check(world.dungeon_mode and not world.arena_mode, "地牢模式下试验场被关闭")
	t.eq(world.current_room_index, world.layout.start_index, "开局落在起始房")
	t.eq(world.current_room_kind(), G.RoomKind.START, "当前房型 = 起始房")
	t.eq(Vector2(world.room.get("size", Vector2i.ZERO)), Vector2(G.START_ROOM_SIZE), "起始房用的是起始房尺寸")
	t.check(bool(world.room_data()["cleared"]), "起始房默认已清空（安全房）")
	t.check(world.doors.size() > 0, "起始房有门（%d 扇）" % world.doors.size())
	t.eq(world.open_door_count(), world.doors.size(), "起始房门全部开启")
	t.eq(world.spawner.alive_count(), 0, "起始房不出怪")
	t.check(world.interior_rect.grow(8.0).has_point(world.player.position), "玩家落在起始房可行走区内")
	t.check(world.camera.has_bounds, "相机绑定了房间边界")
	t.eq(world.camera.bounds.size, Vector2(world.room["size"]) * float(G.TILE_SIZE), "相机 bounds 等于房间像素尺寸")
	await _free_world(t, world)


# ==================== 2. 战斗房：关门开波 -> 清怪开门 ====================

func _test_combat_room_doors(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 4)
	var combat: int = _first_room_of_kind(world, G.RoomKind.COMBAT)
	t.check(combat >= 0, "布局里有纯战斗房")
	world.goto_room(combat)
	await _frames(t, 8)
	t.eq(world.current_room_index, combat, "已切入战斗房")
	t.check(not bool(world.room_data()["cleared"]), "没清怪前房间不算清空")
	t.eq(world.open_door_count(), 0, "开波后门全部关闭")
	t.check(world.spawner.alive_count() > 0, "战斗房刷出了敌人（%d 只）" % world.spawner.alive_count())
	world.clear_current_room()
	await _frames(t, 6)
	t.check(bool(world.room_data()["cleared"]), "清怪后房间标记为已清空")
	t.eq(world.spawner.alive_count(), 0, "清怪后场上没有敌人")
	t.eq(world.open_door_count(), world.doors.size(), "清怪后门重新开启")
	t.check(world.rooms_cleared >= 1, "已清空房间计数递增（%d）" % world.rooms_cleared)
	await _free_world(t, world)


# ==================== 3. 门传送 ====================

func _test_door_travel(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	# 等过换房锁与门的 ARM_DELAY，门才真的会响应重叠
	await _frames(t, 30)
	var from_index: int = world.current_room_index
	var door: Door = world.doors[0]
	var target: int = door.target_index
	t.check(door.is_open, "起始房的门是开着的（可通行）")
	t.neq(target, from_index, "门指向另一间房")
	world.player.position = door.global_position + _inward_offset(door.dir) * 0.5
	await _wait_until(t, func() -> bool: return world.current_room_index == target, 60)
	t.eq(world.current_room_index, target, "走进开着的门 -> 切换到邻房")
	t.check(world.interior_rect.grow(12.0).has_point(world.player.position), "换房后玩家落在新房内部")
	t.check(world.doors.size() > 0, "新房也有门（%d 扇）" % world.doors.size())
	t.not_null(_door_to(world, from_index), "新房里有一扇能走回原来那间房的门（双向连通）")
	t.check(bool(world.room_data(from_index)["visited"]), "走过的房间被标记为已访问")
	# 走回头路：从新房的门回到起始房
	var back: Door = _door_to(world, from_index)
	if back != null and back.is_open:
		world.player.position = back.global_position + _inward_offset(back.dir)
		await _wait_until(t, func() -> bool: return world.current_room_index == from_index, 60)
		t.eq(world.current_room_index, from_index, "原路返回也能换房（门双向可用）")
	await _free_world(t, world)


# ==================== 4. 精英房掉钥匙 ====================

func _test_elite_key(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 4)
	var elite: int = world.layout.elite_index
	t.check(elite >= 0, "布局里有精英房（钥匙房）")
	GameState.set_floor_key(false)
	world.goto_room(elite)
	await _frames(t, 8)
	t.eq(world.current_room_kind(), G.RoomKind.ELITE, "已切入精英房")
	t.check(world.floor_key == null, "没清怪前钥匙不出现")
	t.check(world.spawner.alive_count() > 0, "精英房有守卫")
	world.clear_current_room()
	await _frames(t, 6)
	t.not_null(world.floor_key, "精英房清怪后掉出地牢钥匙")
	t.check(not GameState.has_floor_key, "钥匙还在地上，没被拾取")
	t.check(world.floor_key.position.distance_to(world.room.get("center", Vector2.ZERO)) < 40.0,
			"钥匙掉在房间中央附近（不是被浮动基准点甩到地图外）")
	world.player.position = world.floor_key.position
	await _wait_until(t, func() -> bool: return GameState.has_floor_key, 90)
	t.check(GameState.has_floor_key, "踩上钥匙 -> GameState.has_floor_key 置真")
	t.check(world.floor_key == null, "钥匙被拾取后从世界里移除")
	t.check(bool(world.room_data(elite).get("key_taken", false)), "钥匙已拾取写进房间数据（不会重复刷）")
	await _free_world(t, world)


# ==================== 5. Boss 门前置锁 ====================

func _test_boss_door_lock(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 4)
	var boss: int = world.layout.boss_index
	var neighbors: Array = world.layout.neighbor_indexes(boss)
	t.check(not neighbors.is_empty(), "Boss 房有邻居房间")
	var gate_room: int = int(neighbors[0])
	world.goto_room(gate_room)
	await _frames(t, 6)
	# 先把守卫清掉，免得 knocked-back 把玩家从门口推开影响判定
	world.clear_current_room()
	await _frames(t, 6)
	var boss_door: Door = _door_to(world, boss)
	t.not_null(boss_door, "Boss 房邻居里有一扇通往 Boss 房的门")
	if boss_door == null:
		await _free_world(t, world)
		return
	t.check(boss_door.is_boss_door, "该门被标记为 Boss 门")
	t.check(boss_door.is_locked(), "没钥匙时 Boss 门上锁")
	t.check(not boss_door.is_open, "清怪后 Boss 门依然关闭（不随普通门一起开）")
	GameState.set_floor_key(false)
	world._key_toast_timer = 0.0
	# 真机路径：把玩家推进锁着的 Boss 门里，靠 Area 轮询触发"撞门"反馈
	world.player.position = boss_door.global_position + _inward_offset(boss_door.dir)
	await _frames(t, 30)
	t.eq(world.current_room_index, gate_room, "没钥匙撞 Boss 门不放行")
	t.check(not GameState.has_floor_key, "没钥匙时不会凭空多出钥匙")
	# 捡到钥匙后继续贴着门：下一次轮询就该把门打开并消耗钥匙
	GameState.set_floor_key(true)
	await _wait_until(t, func() -> bool: return world.current_room_index == boss, 90)
	t.eq(world.current_room_index, boss, "有钥匙撞 Boss 门 -> 进入 Boss 房")
	t.check(not GameState.has_floor_key, "开门消耗掉地牢钥匙")
	t.eq(world.current_room_kind(), G.RoomKind.BOSS, "当前房型 = Boss 房")
	await _free_world(t, world)


# ==================== 6. Boss 房清空 -> 传送门 -> 换层 ====================

func _test_portal_and_floor_advance(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 4)
	# 跨层要保留的状态：金币 / 武器 / 生命
	GameState.add_gold(120)
	var gold_before: int = GameState.gold
	var weapons_before: int = world.player.weapons.size()
	world.player.stats["health"] = world.player.max_health() * 0.4
	var health_before: float = world.player.health()
	var floor_before: int = GameState.floor_index
	var seed_before: int = GameState.run_seed

	world.goto_room(world.layout.boss_index)
	await _frames(t, 2)
	t.eq(world.current_room_kind(), G.RoomKind.BOSS, "已切入 Boss 房")
	# M7 起 Boss 实体真实接入：先等 Boss 投放，击杀后房间才判清空
	#（_wait_until 返回用掉的帧数：0 = 第一帧就成立，所以拿到值后要再看存活数）
	await _wait_until(t,
			func() -> bool: return world.spawner.alive_count() >= 1, 150)
	var boss_arrived: bool = world.spawner.alive_count() >= 1
	t.check(boss_arrived, "Boss 房投放出 Boss 实体（%d 只）" % world.spawner.alive_count())
	if boss_arrived:
		var boss: EnemyBoss = world.spawner.alive_enemies()[0] as EnemyBoss
		t.check(boss is EnemyBoss, "投放的是 EnemyBoss 实例")
		boss.take_hit(999999.0, false, Vector2.ZERO, 0)
	await _wait_until(t,
			func() -> bool: return world.boss_room_cleared, 200)
	t.check(world.boss_room_cleared, "击杀 Boss 后房间清空判定通过")
	t.check(bool(world.room_data()["cleared"]), "Boss 房标记为已清空")
	t.not_null(world.portal, "Boss 房清空后出现传送门")
	if world.portal == null:
		await _free_world(t, world)
		return
	t.check(world.portal.is_active, "传送门处于激活状态")
	t.eq(world.portal.target_floor, floor_before + 1, "传送门指向下一层")
	# 先把玩家挪开，避免断言过程中 ARM_DELAY 到点自动换层
	world.player.position = world.portal.position + Vector2(140.0, 0.0)
	await _frames(t, 4)
	t.eq(GameState.floor_index, floor_before, "没踩上传送门前不会换层")

	world.player.position = world.portal.position
	await _wait_until(t, func() -> bool: return GameState.floor_index == floor_before + 1, 150)
	t.eq(GameState.floor_index, floor_before + 1, "踩上传送门进入下一层")
	t.eq(GameState.run_seed, seed_before, "换层不换局（run_seed 保持）")
	t.eq(world.layout.floor_index, GameState.floor_index, "新布局的层数与 GameState 同步")
	t.eq(world.current_room_index, world.layout.start_index, "新层从起始房开始")
	t.check(not world.boss_room_cleared, "新层的 Boss 房清空标记被重置")
	t.eq(world.rooms_cleared, 0, "新层的清空计数被重置")
	# 层间状态保留
	t.eq(GameState.gold, gold_before, "跨层保留金币")
	t.eq(world.player.weapons.size(), weapons_before, "跨层保留武器")
	t.near(world.player.health(), world.player.max_health() * 0.65, 1.0,
			"跨层保留生命并按四分之一上限回血（实测 %.1f/%.1f）" % [
					world.player.health(), world.player.max_health()])
	t.gte(world.player.health(), health_before, "换层不会掉血")
	t.check(not GameState.has_floor_key, "换层后钥匙清空（每层重新找）")
	t.check(world.interior_rect.grow(12.0).has_point(world.player.position), "换层后玩家已落到新起始房内")
	await _free_world(t, world)


# ==================== 7. 宝箱房与商店房 ====================

func _test_treasure_and_shop(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 4)
	# --- 宝箱房 ---
	var treasure: int = _first_room_of_kind(world, G.RoomKind.TREASURE)
	t.check(treasure >= 0, "布局里有宝箱房")
	world.goto_room(treasure)
	await _frames(t, 6)
	t.not_null(world.chest, "宝箱房里生成了宝箱")
	t.check(world.spawner.alive_count() > 0, "宝箱房有守卫（要先清怪）")
	t.eq(world.open_door_count(), 0, "宝箱房开波后关门")
	world.clear_current_room()
	await _frames(t, 6)
	t.eq(world.open_door_count(), world.doors.size(), "清怪后宝箱房门重新开启")
	if world.chest != null:
		t.check(not world.chest.is_opened, "宝箱初始是关着的")
		t.check(not world.chest.reward.is_empty(), "宝箱已摇好奖励（%s）" % str(world.chest.reward.get("kind", "?")))
		var gold_before: int = GameState.gold
		world.chest.reward = {"kind": "gold", "amount": 37}
		world.chest.interact(world.player)
		await _frames(t, 4)
		t.eq(GameState.gold, gold_before + 37, "开箱结算金币奖励")
		t.check(world.chest.is_opened, "开箱后宝箱标记为已开启")
		t.check(bool(world.room_data(treasure).get("chest_taken", false)), "开箱写进房间数据")
	# 走回头路：开过的宝箱不会复活
	world.goto_room(world.layout.start_index)
	await _frames(t, 4)
	world.goto_room(treasure)
	await _frames(t, 4)
	t.check(world.chest == null or not is_instance_valid(world.chest), "已开过的宝箱房不再刷出宝箱")

	# --- 商店房 ---
	var shop: int = _first_room_of_kind(world, G.RoomKind.SHOP)
	t.check(shop >= 0, "布局里有商店房")
	world.goto_room(shop)
	await _frames(t, 6)
	t.not_null(world.shop_pad, "商店房里生成了商店垫")
	t.eq(world.spawner.alive_count(), 0, "商店房是安全房，不出怪")
	if world.shop_pad != null:
		t.check(world.shop_pad.stock.size() > 0, "商店有货（%d 件）" % world.shop_pad.stock.size())
		var offer: Dictionary = world.shop_pad.current_offer()
		t.check(not offer.is_empty(), "商店当前选中了一件商品")
		var price: int = int(offer.get("price", 0))
		GameState.add_gold(price)
		var gold_shop: int = GameState.gold
		world.player.stats["health"] = world.player.max_health() * 0.5
		world.shop_pad.interact(world.player)
		await _frames(t, 4)
		t.eq(GameState.gold, gold_shop - price, "购买扣掉对应金币")
		t.check(world.room_data(shop).has("shop_stock"), "库存写回房间数据（走出再回来不会复活）")
		# 没钱时拒绝交易
		GameState.gold = 0
		var denied_gold: int = GameState.gold
		world.shop_pad.interact(world.player)
		await _frames(t, 4)
		t.eq(GameState.gold, denied_gold, "金币不够时不会扣成负数")
	await _free_world(t, world)


# ==================== 8. 层内进度：回头路不重复刷怪 ====================

func _test_revisit_cleared_room(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 4)
	var combat: int = _first_room_of_kind(world, G.RoomKind.COMBAT)
	world.goto_room(combat)
	await _frames(t, 8)
	t.check(world.spawner.alive_count() > 0, "战斗房第一次进来会刷怪")
	world.clear_current_room()
	await _frames(t, 6)
	var cleared_count: int = world.rooms_cleared
	# 出去再回来
	world.goto_room(world.layout.start_index)
	await _frames(t, 6)
	world.goto_room(combat)
	await _frames(t, 8)
	t.eq(world.spawner.alive_count(), 0, "已清空的房间回头路不再刷怪")
	t.eq(world.open_door_count(), world.doors.size(), "已清空的房间门保持开启")
	t.eq(world.rooms_cleared, cleared_count, "重复进已清空房间不会重复计数")
	await _free_world(t, world)
