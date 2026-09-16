extends TestSuite
## test_pickup —— M6「掉落 / 临时天赋 / 炸弹」验收（无头）。
##
## 覆盖六块：
##   1. 七类拾取物各自把效果写进玩家属性 / GameState（金币、能量、血包、护盾、武器、天赋、炸弹）；
##   2. 磁吸吸附 + 满状态不吸附（满血的血包留在地上，不浪费掉落）；
##   3. 到期闪烁并自动回收，世界层的 room_pickups 同步清理；
##   4. 临时天赋：bonus_ 加成生效、槽位上限淘汰、到期整体回收；
##   5. F 键炸弹：消耗枚数、冷却、爆炸伤敌与自伤、无弹时拒绝；
##   6. 祭坛 / 商店的金币换天赋与炸弹，以及存档序列化回传。
##
## run() 是协程：磁吸、到期、换房都要等物理帧让 Area2D 真的动起来。

const G := preload("res://scripts/core/game_const.gd")
const TALENT_DB := preload("res://scripts/core/talent_db.gd")

## 固定种子：布局与掉落内容都可复现
const TEST_SEED: int = 20260915

## 沙包血线：避免测试途中玩家被打死把世界标记成 finished
const TEST_PLAYER_HEALTH: float = 4000.0


func suite_name() -> String:
	return "掉落 · 天赋 · 炸弹 (M6)"


func run(t: Node) -> void:
	await _test_pickup_effects(t)
	await _test_magnet_and_full_state(t)
	await _test_lifetime_and_blink(t)
	await _test_talent_slots(t)
	await _test_bomb_throw(t)
	await _test_altar_offers(t)
	await _test_shop_offers(t)
	await _test_run_serialization(t)


# ==================== 公共工具 ====================

## 建世界：先脱离物理 flush 窗口再 add_child（与 test_dungeon_flow 同一套规避方式）
func _make_world(t: Node, seed_value: int = TEST_SEED) -> GameWorld:
	await t.get_tree().physics_frame
	GameState.new_run(seed_value)
	GameState.clear_talents()
	var world := GameWorld.new()
	world.name = "PickupWorld"
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
	player.stats["energy"] = 0.0
	player.clear_invulnerable()
	return player


## 等待 count 帧；恢复点固定落在 physics_frame 续体，避开 flush queries 窗口
func _frames(t: Node, count: int) -> void:
	for i: int in range(count):
		await t.get_tree().process_frame
		await t.get_tree().physics_frame


## 生成一个不会被撒开的拾取物（scatter_speed = 0），保证距离类断言稳定
func _spawn_still(world: GameWorld, kind: int, amount: float, offset: Vector2,
		extra: Dictionary = {}) -> Pickup:
	var options: Dictionary = extra.duplicate()
	options["scatter_speed"] = 0.0
	return world.spawn_pickup(kind, amount, world.player.global_position + offset, options)


func _find_offer_index(stock: Array, offer_id: String) -> int:
	for i: int in range(stock.size()):
		var entry: Variant = stock[i]
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == offer_id:
			return i
	return -1


func _count_offer(stock: Array, offer_id: String) -> int:
	var n: int = 0
	for entry: Variant in stock:
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == offer_id:
			n += 1
	return n


# ==================== 1. 七类拾取物效果 ====================

func _test_pickup_effects(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 3)
	var player: Player = world.player
	var far := Vector2(240, 0)

	# --- 金币：入账 GameState.gold 并计入世界统计 ---
	var gold_before: int = GameState.gold
	var stat_before: int = world.gold_from_drops
	var coin: Pickup = _spawn_still(world, G.PickupKind.COIN, 5.0, far)
	var coin_result: Dictionary = coin.collect()
	t.eq(GameState.gold, gold_before + 5, "金币拾取物入账 +5")
	t.eq(world.gold_from_drops, stat_before + 5, "世界统计到掉落金币")
	t.eq(int(coin_result.get("gold", -1)), 5, "结算结果带金币数")
	t.check(str(coin_result.get("text", "")) != "", "结算结果带飘字文本")
	t.eq(world.pickup_count(), 0, "拾取后从房间列表移除")

	# --- 能量 ---
	player.stats["energy"] = 0.0
	var energy: Pickup = _spawn_still(world, G.PickupKind.ENERGY, 0.0, far)
	energy.collect()
	t.near(player.energy(), G.PICKUP_ENERGY, 0.01, "能量球按默认值回能")

	# --- 血包 ---
	player.stats["health"] = 40.0
	var heart: Pickup = _spawn_still(world, G.PickupKind.HEALTH, 0.0, far)
	heart.collect()
	t.near(player.health(), 40.0 + G.PICKUP_HEAL, 0.01, "血包按默认值回血")
	player.stats["health"] = TEST_PLAYER_HEALTH

	# --- 大血包：amount 指定回复量 ---
	player.stats["health"] = 40.0
	var big_heart: Pickup = _spawn_still(world, G.PickupKind.HEALTH, G.PICKUP_HEAL_BIG, far)
	big_heart.collect()
	t.near(player.health(), 40.0 + G.PICKUP_HEAL_BIG, 0.01, "大血包按 amount 回血")
	player.stats["health"] = TEST_PLAYER_HEALTH

	# --- 护盾电池 ---
	player.stats["shield"] = 0.0
	var cell: Pickup = _spawn_still(world, G.PickupKind.SHIELD_CELL, 0.0, far)
	cell.collect()
	t.gt(player.shield(), 0.0, "护盾电池补上护盾")
	t.near(player.shield(), G.PICKUP_SHIELD, 0.01, "护盾按默认值结算")

	# --- 随机武器（先腾出空槽位：满槽时 add_weapon 是替换而不是新增） ---
	player.weapons = player.weapons.slice(0, 1)
	player.weapon_index = 0
	var weapon_count: int = player.weapons.size()
	var weapon_gift: Pickup = _spawn_still(world, G.PickupKind.WEAPON, 1.0, far)
	var weapon_result: Dictionary = weapon_gift.collect()
	t.gt(float(player.weapons.size()), float(weapon_count), "武器拾取物进了武器栏")
	t.check(str(weapon_result.get("weapon_name", "")) != "", "结算结果带武器名")

	# --- 临时天赋：持续加成走 bonus_，instant 一次性回复在拾取瞬间结算 ---
	GameState.clear_talents()
	var talent_gift: Pickup = _spawn_still(world, G.PickupKind.TALENT, 1.0, far,
			{"talent": TALENT_DB.create("speed")})
	var talent_result: Dictionary = talent_gift.collect()
	t.eq(GameState.talents.size(), 1, "天赋写入 GameState.talents")
	t.eq(str(talent_result.get("talent_id", "")), "speed", "结算结果带天赋 id")
	t.check(player.stats.has("bonus_move_speed"), "天赋加成写进 bonus_ 属性")
	t.gt(player.stat("move_speed") - float(player.stats.get("move_speed", 0.0)), 0.0,
			"移速加成对玩家实际生效")
	player.stats["health"] = 40.0
	var life_gift: Pickup = _spawn_still(world, G.PickupKind.TALENT, 1.0, far,
			{"talent": TALENT_DB.create("life")})
	var life_result: Dictionary = life_gift.collect()
	t.gt(float(life_result.get("healed", 0.0)), 0.0, "生机：拾取瞬间立即回血")
	t.gt(player.health(), 40.0, "回血真的落到了玩家身上")
	player.stats["health"] = TEST_PLAYER_HEALTH

	# --- 炸弹 ---
	var bombs_before: int = GameState.bombs
	var bomb_gift: Pickup = _spawn_still(world, G.PickupKind.BOMB, 2.0, far)
	bomb_gift.collect()
	t.eq(GameState.bombs, bombs_before + 2, "炸弹拾取物补上 2 枚")

	# --- 满状态时拒绝拾取（不浪费掉落） ---
	player.stats["health"] = player.max_health()
	var full_heart: Pickup = _spawn_still(world, G.PickupKind.HEALTH, 0.0, far)
	t.check(not full_heart.can_collect(), "满血时血包不可拾取")
	t.eq(full_heart.collect().size(), 0, "满血时 collect() 返回空结果")
	t.check(not full_heart.is_collected, "满血时不会标记为已拾取")
	t.eq(world.pickup_count(), 1, "没被吃掉的血包仍留在房间里")
	player.stats["health"] = TEST_PLAYER_HEALTH

	await _free_world(t, world)


# ==================== 2. 磁吸与满状态 ====================

func _test_magnet_and_full_state(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 3)
	var player: Player = world.player

	# 吸附半径内的金币会被拉向玩家
	var coin: Pickup = _spawn_still(world, G.PickupKind.COIN, 3.0, Vector2(60, 0))
	var start_distance: float = coin.global_position.distance_to(player.global_position)
	t.gt(start_distance, float(G.PICKUP_COLLECT_RADIUS), "金币生成时还没到拾取距离")
	await _frames(t, 6)
	var moved: float = 0.0 if not is_instance_valid(coin) else coin.global_position.distance_to(player.global_position)
	t.check(moved < start_distance, "磁吸把金币拉向玩家（%.1f -> %.1f）" % [start_distance, moved])

	# 半径外的金币不动
	var far_coin: Pickup = _spawn_still(world, G.PickupKind.COIN, 3.0, Vector2(120, 0))
	var far_before: float = far_coin.global_position.distance_to(player.global_position)
	await _frames(t, 6)
	if is_instance_valid(far_coin):
		t.near(far_coin.global_position.distance_to(player.global_position), far_before, 1.0,
				"吸附半径外的金币保持原地")

	# 满血时血包既不被吸走也不被吃掉
	player.stats["health"] = player.max_health()
	var heart: Pickup = _spawn_still(world, G.PickupKind.HEALTH, 0.0, Vector2(40, 0))
	var heart_before: float = heart.global_position.distance_to(player.global_position)
	await _frames(t, 30)
	t.check(is_instance_valid(heart), "满血时血包不会被吃掉")
	if is_instance_valid(heart):
		t.check(not heart.is_collected, "满血时血包未标记为已拾取")
		t.near(heart.global_position.distance_to(player.global_position), heart_before, 1.0,
				"满血时血包不会被磁吸")
		# 掉血之后同一枚血包立刻恢复可用
		player.stats["health"] = 40.0
		t.check(heart.can_collect(), "掉血后血包重新可拾取")
		heart.collect()
		t.gt(player.health(), 40.0, "掉血后能吃掉留在地上的血包")
	player.stats["health"] = TEST_PLAYER_HEALTH

	await _free_world(t, world)


# ==================== 3. 到期闪烁与回收 ====================

func _test_lifetime_and_blink(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 3)

	# 剩余时间进入闪烁区间后透明度被压低
	var blinking: Pickup = _spawn_still(world, G.PickupKind.COIN, 2.0, Vector2(200, 0),
			{"lifetime": G.PICKUP_BLINK_TIME * 0.5})
	await _frames(t, 2)
	t.check(is_instance_valid(blinking), "闪烁期间拾取物仍在场")
	if is_instance_valid(blinking):
		t.check(blinking.modulate.a < 1.0, "到期前进入闪烁（alpha=%.2f）" % blinking.modulate.a)

	# 短寿命拾取物到点自动回收，世界层列表同步清理
	var short_lived: Pickup = _spawn_still(world, G.PickupKind.ENERGY, 0.0, Vector2(200, 0),
			{"lifetime": 0.35})
	var count_before: int = world.pickup_count()
	t.gt(float(count_before), 1.0, "回收前房间里有多枚拾取物")
	var frames: int = 0
	while frames < 120 and is_instance_valid(short_lived) and not short_lived.is_expired:
		await t.get_tree().process_frame
		await t.get_tree().physics_frame
		frames += 1
	t.check(frames < 120, "到期后拾取物自动回收（用了 %d 帧）" % frames)
	t.eq(world.pickup_count(), count_before - 1, "过期拾取物从房间列表移除")

	await _free_world(t, world)


# ==================== 4. 临时天赋 ====================

func _test_talent_slots(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 3)
	var player: Player = world.player
	GameState.clear_talents()

	# 单个天赋：加成写进 bonus_，玩家读属性时生效
	var base_speed: float = float(player.stats.get("move_speed", 0.0))
	GameState.add_talent(TALENT_DB.create("speed"))
	t.eq(GameState.talents.size(), 1, "天赋入列")
	t.near(player.stat("move_speed"), base_speed + 46.0, 0.01, "疾风：移速 +46 生效")

	# instant 类天赋的一次性回复由 Pickup 在拾取瞬间结算（见上面的天赋拾取用例），
	# GameState.add_talent 只负责持续加成，这里校验 modifiers 生效
	GameState.add_talent(TALENT_DB.create("life"))
	t.near(player.max_health(), base_max_health(player) + 20.0, 0.01, "生机：生命上限 +20")

	# 同 id 叠加只续时长，不占第二格
	var slots_before: int = GameState.talents.size()
	GameState.add_talent(TALENT_DB.create("speed"))
	t.eq(GameState.talents.size(), slots_before, "重复天赋不额外占槽位")

	# 槽位上限：超出时淘汰剩余时间最短的那个
	GameState.add_talent(TALENT_DB.create("crit"))
	GameState.add_talent(TALENT_DB.create("damage"))
	t.eq(GameState.talents.size(), G.TALENT_MAX_SLOTS, "天赋槽位有上限")
	t.check(not GameState.has_talent("life"), "超限时淘汰剩余时间最短的天赋")
	t.check(GameState.has_talent("speed") and GameState.has_talent("damage"), "较新的天赋被保留")

	# 到期：整体回收 bonus_，属性回到基础值
	var expired_ids: Array = []
	var on_expired: Callable = func(talent_id: String) -> void:
		expired_ids.append(talent_id)
	EventBus.talent_expired.connect(on_expired)
	GameState.tick_talents(60.0)
	EventBus.talent_expired.disconnect(on_expired)
	t.eq(GameState.talents.size(), 0, "到期后天赋列表清空")
	t.gt(float(expired_ids.size()), 0.0, "到期发出 talent_expired 事件")
	t.near(player.stat("move_speed"), base_speed, 0.01, "到期后移速加成消失")
	t.check(not player.stats.has("bonus_move_speed"), "到期后 bonus_ 键被清掉")
	t.check(not player.stats.has("bonus_crit_chance"), "其它天赋的 bonus_ 键一并清掉")

	await _free_world(t, world)


## 生命上限的基础值（天赋加成写在 bonus_max_health 上，扣掉即为裸值）
func base_max_health(player: Player) -> float:
	return float(player.stats.get("max_health", 0.0))


# ==================== 5. 炸弹 ====================

func _test_bomb_throw(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 3)
	var player: Player = world.player
	_tough_player(world)
	GameState.add_bombs(3)
	var bombs_before: int = GameState.bombs
	t.gt(float(bombs_before), 2.0, "测试前至少有 3 枚炸弹")

	# 扔一枚：扣数量、进冷却、生成炸弹实体
	var victim: Enemy = world.spawn_enemy("husk", player.global_position + Vector2(0, -40))
	victim.data.contact_damage = 0.0
	# 让敌人的碰撞体真正进物理空间，area_damage 的 intersect_shape 才查得到它
	await _frames(t, 2)
	player.aim_direction = Vector2(0, -1)
	player.bomb_cooldown_timer = 0.0
	t.check(player.try_throw_bomb(), "有炸弹时可以投掷")
	t.eq(GameState.bombs, bombs_before - 1, "投掷消耗 1 枚")
	t.eq(player.bombs_thrown, 1, "投掷计数 +1")
	t.gt(player.bomb_cooldown_timer, 0.0, "投掷后进入冷却")
	t.check(not player.try_throw_bomb(), "冷却中不能连投")

	var bomb: ThrownBomb = _find_bomb(world)
	t.not_null(bomb, "炸弹实体已生成")
	if bomb == null:
		await _free_world(t, world)
		return
	t.eq(bomb.bounds, world.interior_rect, "炸弹的飞行范围跟着房间走")
	t.gt(bomb.damage, 0.0, "炸弹伤害已按玩家属性结算")
	t.check(bomb.state == ThrownBomb.State.FLYING, "刚出手处于飞行状态")

	# 落地 -> 引信 -> 爆炸
	bomb.land()
	t.check(bomb.state == ThrownBomb.State.FUSED, "落地后进入引信状态")
	t.near(bomb.fuse_remaining(), G.BOMB_FUSE, 0.01, "引信时长正确")
	var health_before: float = victim.health
	var player_health_before: float = player.health()
	var blast: Dictionary = bomb.explode()
	t.check(bomb.is_exploded, "爆炸只结算一次")
	t.gte(float(blast.get("damaged", 0)), 1.0, "爆炸命中了范围内的敌人")
	t.check(victim.health < health_before, "敌人被炸掉血（%.1f -> %.1f）" % [health_before, victim.health])
	t.check(bool(blast.get("self_hit", false)), "贴脸扔会自伤")
	t.check(player.health() < player_health_before, "玩家自伤生效")
	t.gt(player.health(), 0.0, "自伤比例不会把自己炸死")

	# 没弹时拒绝投掷
	GameState.bombs = 0
	player.bomb_cooldown_timer = 0.0
	t.check(not player.try_throw_bomb(), "没炸弹时不能投掷")
	t.check(not player.bomb_ready() or player.bomb_cooldown_timer > 0.0, "空投也会给一点冷却防连点")

	await _free_world(t, world)


func _find_bomb(world: GameWorld) -> ThrownBomb:
	for child: Node in world.entity_root.get_children():
		if child is ThrownBomb:
			return child
	return null


# ==================== 6. 祭坛 ====================

func _test_altar_offers(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 4)
	var player: Player = world.player
	t.eq(world.current_room_kind(), G.RoomKind.START, "开局落在起始房")
	t.not_null(world.altar, "起始房里有祈愿祭坛")
	if world.altar == null:
		await _free_world(t, world)
		return
	var altar: Altar = world.altar
	var flags := {"denied": 0, "exhausted": 0, "purchased": 0}
	altar.denied.connect(func(_a: Altar, _o: Dictionary) -> void: flags["denied"] += 1)
	altar.exhausted.connect(func(_a: Altar) -> void: flags["exhausted"] += 1)
	altar.purchased.connect(func(_a: Altar, _o: Dictionary) -> void: flags["purchased"] += 1)

	t.eq(altar.offers().size(), 2, "祭坛有两档供品")
	t.eq(altar.remaining_uses(), G.ALTAR_USE_LIMIT, "祭坛初始可用次数正确")
	t.check(altar.can_interact(player), "有次数时可以交互")
	t.check(altar.interact_prompt().find("祈愿") >= 0, "交互提示说明是祈愿")

	# 金币不够：拒绝且不扣次数
	GameState.gold = 0
	GameState.clear_talents()
	altar.interact(player)
	t.eq(GameState.gold, 0, "金币不够时不会扣成负数")
	t.eq(int(flags["denied"]), 1, "金币不够时发出 denied")
	t.eq(altar.remaining_uses(), G.ALTAR_USE_LIMIT, "被拒绝时不消耗次数")
	t.eq(GameState.talents.size(), 0, "被拒绝时不会白送天赋")

	# 第一档：随机天赋
	GameState.gold = 200
	altar.cursor = 0
	t.eq(str(altar.current_offer().get("id", "")), "talent", "第一档供品是天赋")
	altar.interact(player)
	t.eq(GameState.gold, 200 - G.ALTAR_TALENT_PRICE, "天赋供品按定价扣款")
	t.eq(GameState.talents.size(), 1, "祈愿到一个天赋")
	t.eq(altar.remaining_uses(), G.ALTAR_USE_LIMIT - 1, "祈愿消耗 1 次")
	t.eq(altar.cursor, 1, "光标自动滚到下一件供品")
	t.eq(int(flags["purchased"]), 1, "成交发出 purchased")

	# 第二档：炸弹 ×2
	var bombs_before: int = GameState.bombs
	t.eq(str(altar.current_offer().get("id", "")), "bomb", "第二档供品是炸弹")
	altar.interact(player)
	t.eq(GameState.gold, 200 - G.ALTAR_TALENT_PRICE - G.ALTAR_BOMB_PRICE, "炸弹供品按定价扣款")
	t.eq(GameState.bombs, bombs_before + 2, "祈愿到 2 枚炸弹")
	t.eq(altar.remaining_uses(), 0, "次数用完")
	t.eq(int(flags["exhausted"]), 1, "用完发出 exhausted")
	t.check(not altar.can_interact(player), "用完后不再响应交互")
	t.eq(int(world.room_data().get("altar_uses", -1)), 0, "用完写回房间数据")

	# 熄灭后再交互：不扣钱不发货
	var gold_after: int = GameState.gold
	altar.interact(player)
	t.eq(GameState.gold, gold_after, "熄灭的祭坛不再收钱")
	t.eq(int(flags["purchased"]), 2, "熄灭的祭坛不再发成交信号")

	await _free_world(t, world)


# ==================== 7. 商店新货架 ====================

func _test_shop_offers(t: Node) -> void:
	var world: GameWorld = await _make_world(t)
	await _frames(t, 3)
	var player: Player = world.player
	var shop_index: int = _first_room_of_kind(world, G.RoomKind.SHOP)
	t.gte(float(shop_index), 0.0, "布局里有商店房")
	if shop_index < 0:
		await _free_world(t, world)
		return
	world.goto_room(shop_index)
	await _frames(t, 4)
	t.not_null(world.shop_pad, "商店房里有售货台")
	if world.shop_pad == null:
		await _free_world(t, world)
		return
	var pad: ShopPad = world.shop_pad
	t.gte(float(pad.stock.size()), float(ShopPad.OFFERS.size() + 2), "默认货架铺满商品并追加武器")
	t.gte(float(_find_offer_index(pad.stock, "talent")), 0.0, "货架上有天赋")
	t.gte(float(_find_offer_index(pad.stock, "bomb")), 0.0, "货架上有炸弹")
	t.gte(float(_find_offer_index(pad.stock, "weapon_specific")), 0.0, "货架上有可购买的武器")

	# 买炸弹：可重复购买
	GameState.gold = 300
	var bombs_before: int = GameState.bombs
	pad.cursor = _find_offer_index(pad.stock, "bomb")
	pad.interact(player)
	t.eq(GameState.gold, 300 - G.SHOP_BOMB_PRICE, "炸弹按定价扣款")
	t.eq(GameState.bombs, bombs_before + 2, "买到 2 枚炸弹")
	t.gte(float(_find_offer_index(pad.stock, "bomb")), 0.0, "炸弹是可重复商品，不下架")

	# 买天赋：一次性商品，买完下架
	GameState.clear_talents()
	GameState.gold = 300
	pad.cursor = _find_offer_index(pad.stock, "talent")
	pad.interact(player)
	t.eq(GameState.gold, 300 - G.SHOP_TALENT_PRICE, "天赋按定价扣款")
	t.eq(GameState.talents.size(), 1, "买到一个天赋")
	t.gt(player.stats.keys().size(), 0.0, "天赋加成写进了玩家属性表")
	t.eq(_find_offer_index(pad.stock, "talent"), -1, "一次性天赋买完即下架")
	t.eq(int(world.room_data(shop_index).get("shop_stock", []).size()), pad.stock.size(),
			"库存变化写回房间数据")

	# 买武器：一次上架一把，付款后装进玩家武器栏并下架。
	# 玩家出生带 3 把核心武器已满槽，买新武器走"替换当前武器"分支，
	# 槽位数不变、但武器栏内含该武器；货架上 weapon_specific 数量减 1。
	var weapon_offers_before: int = _count_offer(pad.stock, "weapon_specific")
	GameState.gold = 9999
	var weapon_offer_idx: int = _find_offer_index(pad.stock, "weapon_specific")
	t.gte(float(weapon_offer_idx), 0.0, "购买前货架有武器")
	if weapon_offer_idx >= 0:
		var offer_weapon: WeaponData = pad.stock[weapon_offer_idx].get("weapon_data") as WeaponData
		t.not_null(offer_weapon, "武器货架携带真实武器数据")
		var weapon_price: int = int(pad.stock[weapon_offer_idx].get("price", 0))
		pad.cursor = weapon_offer_idx
		pad.interact(player)
		t.eq(GameState.gold, 9999 - weapon_price, "武器按定价扣款")
		t.eq(player.weapons.size(), 3, "武器栏槽位数不变（出生 3 把已满槽，买新武器替换）")
		if offer_weapon != null:
			t.check(player.weapons.has(offer_weapon), "买到的武器装进玩家武器栏")
		t.eq(_count_offer(pad.stock, "weapon_specific"), weapon_offers_before - 1,
				"买走的武器从货架下架")

	# 反复进出商店不叠加：离开再回来，货架尺寸不变
	var stock_count: int = pad.stock.size()
	var other_index: int = _first_room_of_kind(world, G.RoomKind.START)
	t.gte(float(other_index), 0.0, "布局里有起始房可用于往返测试")
	if other_index >= 0:
		world.goto_room(other_index)
		await _frames(t, 4)
		world.goto_room(shop_index)
		await _frames(t, 4)
		t.eq(world.shop_pad.stock.size(), stock_count, "反复进出商店不叠加武器货架")

	await _free_world(t, world)


func _first_room_of_kind(world: GameWorld, kind: int) -> int:
	var list: Array = world.layout.rooms_of_kind(kind)
	return int(list[0]["index"]) if not list.is_empty() else -1


# ==================== 8. 存档序列化 ====================

func _test_run_serialization(t: Node) -> void:
	GameState.new_run(TEST_SEED)
	GameState.clear_talents()
	GameState.add_bombs(3)
	GameState.gold = 137
	GameState.add_talent(TALENT_DB.create("crit"))
	GameState.add_talent(TALENT_DB.create("energy"))
	var bombs_saved: int = GameState.bombs
	var talents_saved: int = GameState.talents.size()

	GameState.save_current_run()
	t.check(GameState.has_saved_run(), "存档已写入")
	var data: Dictionary = SaveMgr.load_run()
	t.eq(int(data.get("bombs", -1)), bombs_saved, "炸弹数写进存档")
	t.eq(int((data.get("talents", []) as Array).size()), talents_saved, "天赋列表写进存档")
	t.check(not (data.get("stats", {}) as Dictionary).has("bonus_crit_chance"),
			"临时加成不进存档（只存裸属性）")

	# 开新局再读档：炸弹与天赋都要回传，加成重新生效
	GameState.new_run(TEST_SEED + 77)
	GameState.clear_talents()
	t.neq(GameState.gold, 137, "新局金币已重置")
	t.check(GameState.restore_run(data), "读档成功")
	t.eq(GameState.gold, 137, "金币回传")
	t.eq(GameState.bombs, bombs_saved, "炸弹回传")
	t.eq(GameState.talents.size(), talents_saved, "天赋回传")
	t.check(GameState.has_talent("crit"), "锐眼回传")
	t.gt(float(GameState.stats.get("bonus_crit_chance", 0.0)), 0.0, "回传后加成重新生效")

	# 剩余时间归零的天赋不会被读回来
	var stale: Array = [{"id": "speed", "display_name": "疾风", "duration": 20.0, "remain": 0.0}]
	var stale_data: Dictionary = data.duplicate(true)
	stale_data["talents"] = stale
	GameState.new_run(TEST_SEED + 78)
	GameState.clear_talents()
	GameState.restore_run(stale_data)
	t.eq(GameState.talents.size(), 0, "剩余时间为 0 的天赋被丢弃")

	SaveMgr.clear_run()
	GameState.new_run(TEST_SEED)
	GameState.clear_talents()
