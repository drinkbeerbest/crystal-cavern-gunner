extends TestSuite
## test_enemy —— M4 敌人 AI 与波次验收（无头）。
##
## 覆盖六块：
##   1. 数值表：三类原型参数齐全、精英叠加、层数成长、贴图存在、掉落摇奖与波次规划；
##   2. 生成装配：世界注入、生成点合法、休眠与凝聚登场；
##   3. 受击契约：掉血、闪白、击退、暴击/护甲、死亡 -> 掉落 -> 金币入账（且只结算一次）；
##   4. 三类行为可区分：近战冲锋（撞墙眩晕 / 强击退打断）、远程射击（预警 / 敌弹 / 精英三连 / 拉开距离）、
##      自爆（不可打断 / 蓄力档位 / 爆炸伤害 / 临终引爆与连锁）；
##   5. 分离力：挤成一团时会被推开，不互相重叠；
##   6. 波次调度：分批投放、批次间隔、清场判定、空波次（起始房）。
##
## run() 是协程：需要 await 物理帧让 AI 真正跑起来（起手、冲刺、引信、批次计时）。

const G := preload("res://scripts/core/game_const.gd")

## 行为测试里把玩家血线拉高，避免测试途中触发死亡结算把世界标记为 finished
const TEST_PLAYER_HEALTH: float = 4000.0


func suite_name() -> String:
	return "敌人 AI 与波次 (M4)"


func run(t: Node) -> void:
	_test_enemy_table(t)
	await _test_spawn_and_activation(t)
	await _test_hit_and_death_drops(t)
	await _test_melee_charge(t)
	await _test_ranged_shooter(t)
	await _test_bomber_fuse(t)
	await _test_separation(t)
	await _test_wave_scheduling(t)


# ==================== 公共工具 ====================

func _make_world(t: Node) -> GameWorld:
	GameState.new_run(20260914)
	var world := GameWorld.new()
	world.name = "TestGameWorld"
	# 演示波次由 _test_wave_scheduling 专门验证，其余用例需要"干净"的房间
	world.auto_demo_wave = false
	t.add_child(world)
	# 死亡动画结束后保留节点，便于断言死亡后的状态与掉落
	world.spawner.auto_free = false
	return world


func _free_world(t: Node, world: GameWorld) -> void:
	if world == null:
		return
	world.clear_entities(false)
	world.queue_free()
	await t.get_tree().process_frame
	await t.get_tree().physics_frame


## 把玩家变成"打不死但仍会受伤"的沙包：护盾清零 + 血线拉高 + 解除无敌
func _tough_player(world: GameWorld) -> Player:
	var player: Player = world.player
	player.stats["shield"] = 0.0
	player.stats["health"] = TEST_PLAYER_HEALTH
	player.clear_invulnerable()
	return player


func _frames(t: Node, count: int) -> void:
	for i: int in range(count):
		await t.get_tree().physics_frame
		await t.get_tree().process_frame


## 轮询等待条件成立，返回用掉的帧数（超时则返回 max_frames）
func _wait_until(t: Node, condition: Callable, max_frames: int = 240) -> int:
	var frames: int = 0
	while frames < max_frames and not bool(condition.call()):
		await t.get_tree().physics_frame
		await t.get_tree().process_frame
		frames += 1
	return frames


func _first_enemy_bullet(world: GameWorld) -> Bullet:
	for child: Node in world.bullet_root.get_children():
		var bullet: Bullet = child as Bullet
		if bullet != null and not bullet.from_player:
			return bullet
	return null


func _clear_bullets(world: GameWorld) -> void:
	for child: Node in world.bullet_root.get_children():
		child.free()


# ==================== 1. 数值表与波次规划 ====================

func _test_enemy_table(t: Node) -> void:
	var husk: EnemyData = EnemyDB.create_data("husk")
	var hexeye: EnemyData = EnemyDB.create_data("hexeye")
	var bloom: EnemyData = EnemyDB.create_data("bloom")
	t.not_null(husk, "EnemyDB 能创建 husk（近战）")
	t.not_null(hexeye, "EnemyDB 能创建 hexeye（远程）")
	t.not_null(bloom, "EnemyDB 能创建 bloom（自爆）")
	if husk == null or hexeye == null or bloom == null:
		return
	t.check(EnemyDB.create_data("no_such_enemy") == null, "未知 id 返回 null")

	# --- 三类原型：行为参数各自齐全，且互不相同 ---
	t.eq(husk.archetype, EnemyData.Archetype.MELEE, "husk 为近战原型")
	t.eq(hexeye.archetype, EnemyData.Archetype.RANGED, "hexeye 为远程原型")
	t.eq(bloom.archetype, EnemyData.Archetype.BOMBER, "bloom 为自爆原型")
	t.neq(EnemyDB.script_for(husk), EnemyDB.script_for(hexeye), "近战与远程使用不同子类脚本")
	t.neq(EnemyDB.script_for(hexeye), EnemyDB.script_for(bloom), "远程与自爆使用不同子类脚本")
	t.eq(husk.max_health, 34.0, "husk 生命 34")
	t.gt(husk.charge_trigger_range, 0.0, "husk 有冲锋起手距离")
	t.gt(husk.charge_damage, 0.0, "husk 有撞击伤害")
	t.gt(husk.charge_stun_on_wall, 0.0, "husk 撞墙会眩晕")
	t.gt(hexeye.aim_time, 0.0, "hexeye 开火前有预警时间")
	t.gt(hexeye.bullet_speed, 0.0, "hexeye 有弹速")
	t.gt(hexeye.preferred_range, hexeye.keep_distance_min, "hexeye 理想距离大于最小距离")
	t.eq(hexeye.burst_count, 1, "普通 hexeye 一轮 1 发")
	t.gt(bloom.fuse_time, 0.0, "bloom 有引信时长")
	t.gt(bloom.explosion_radius, 0.0, "bloom 有爆炸半径")
	t.check(bloom.explode_on_death, "bloom 被击杀也会引爆")
	t.near(bloom.death_explosion_ratio, 0.7, 0.001, "临终引爆伤害为 70%")
	t.neq(husk.move_speed, bloom.move_speed, "三类敌人移速不同")
	t.gt(bloom.move_speed, hexeye.move_speed, "自爆怪跑得比远程怪快")

	# --- 精英：叠加覆盖而非独立表 ---
	var elite: EnemyData = EnemyDB.create_data("husk_elite")
	t.not_null(elite, "能创建精英 husk")
	t.check(elite.is_elite(), "精英档位标记正确")
	t.eq(elite.display_name, "精英·晶壳行者", "精英名称带前缀")
	t.eq(EnemyDB.base_id_of("husk_elite"), "husk", "精英 id 能还原基础 id")
	t.check(EnemyDB.is_elite_id("bloom_elite"), "bloom_elite 被识别为精英")
	t.check(not EnemyDB.is_elite_id("husk"), "husk 不是精英")
	t.gt(elite.max_health, husk.max_health, "精英血量更高")
	t.gt(elite.armor, husk.armor, "精英有护甲")
	t.gt(elite.score, husk.score, "精英得分更高")
	t.eq(EnemyDB.create_data("hexeye_elite").burst_count, 3, "精英 hexeye 一轮三连发")
	t.eq(EnemyDB.ids().size(), 8, "共 8 个敌人 id（3 基础 + 3 精英 + 2 Boss）")

	# --- 层数成长 ---
	var late: EnemyData = EnemyDB.create_data("husk", 3)
	t.near(late.max_health, 58.0, 0.01, "第 3 层 husk 血量 = round(34*(1+0.35*2)) = 58")
	t.gt(late.charge_damage, husk.charge_damage, "层数越高撞击越痛")
	t.gt(late.move_speed, husk.move_speed, "层数越高跑得越快")
	t.gt(late.gold_max, husk.gold_max, "层数越高金币越多")
	t.near(EnemyDB.create_data("husk", 1).max_health, 34.0, 0.001, "第 1 层为基准不放大")

	# --- 贴图：普通帧与自爆蓄力帧都必须真实存在 ---
	for enemy_data: EnemyData in [husk, hexeye, bloom, elite]:
		t.check(ResourceLoader.exists(enemy_data.sprite_path(0)), "贴图存在：%s" % enemy_data.sprite_path(0))
		t.eq(enemy_data.frames().size(), enemy_data.frame_count, "%s 帧数与配置一致" % enemy_data.id)
	t.eq(bloom.charge_frames(3).size(), bloom.frame_count, "bloom 三档蓄力贴图齐全")
	t.neq(bloom.charge_frames(1)[0], bloom.frames()[0], "蓄力贴图与普通贴图不同")

	# --- 掉落摇奖：金币必出且排最前，幸运值放大其它掉落 ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260914
	var drops: Array = husk.roll_drops(rng, 0.0)
	t.check(not drops.is_empty(), "击杀必定有掉落")
	t.eq(int((drops[0] as Dictionary)["kind"]), G.PickupKind.COIN, "金币排在掉落列表最前")
	t.gte(float((drops[0] as Dictionary)["amount"]), 2.0, "金币数量不低于 gold_min")
	t.lte(float((drops[0] as Dictionary)["amount"]), 5.0, "金币数量不超过 gold_max")
	t.check(EnemyData.count_kinds(drops).has(G.PickupKind.COIN), "count_kinds 能统计金币")

	var plain := RandomNumberGenerator.new()
	plain.seed = 4242
	var lucky := RandomNumberGenerator.new()
	lucky.seed = 4242
	var plain_extra: int = 0
	var lucky_extra: int = 0
	for i: int in range(200):
		plain_extra += EnemyData.count_kinds(husk.roll_drops(plain, 0.0)).size() - 1
		lucky_extra += EnemyData.count_kinds(husk.roll_drops(lucky, 4.0)).size() - 1
	t.gt(float(lucky_extra), float(plain_extra), "幸运值放大非金币掉落")

	# --- 波次规划 ---
	var wave_rng := RandomNumberGenerator.new()
	wave_rng.seed = 777
	t.eq(EnemyDB.wave_count(wave_rng, 1, G.RoomKind.START), 0, "起始房不出怪")
	t.eq(EnemyDB.wave_count(wave_rng, 1, G.RoomKind.SHOP), 0, "商店房不出怪")
	t.eq(EnemyDB.wave_count(wave_rng, 1, G.RoomKind.BOSS), 0, "Boss 房由 Boss 战单独调度")
	var combat_wave: Array = EnemyDB.wave_for_room(wave_rng, 1, G.RoomKind.COMBAT)
	t.gte(float(combat_wave.size()), 3.0, "第 1 层战斗房 3~5 只")
	t.lte(float(combat_wave.size()), 5.0, "第 1 层战斗房不超过 5 只")
	var elite_wave: Array = EnemyDB.wave_for_room(wave_rng, 2, G.RoomKind.ELITE)
	t.gte(float(elite_wave.size()), 5.0, "精英房敌人更多（5~7 只）")
	t.lte(float(elite_wave.size()), 7.0, "精英房不超过 7 只")
	t.gte(float(EnemyDB.wave_for_room(wave_rng, 3, G.RoomKind.COMBAT).size()), 5.0,
			"层数越高同一房型的敌人越多")

	var invalid: int = 0
	var all_ids: Array = combat_wave + elite_wave
	for i: int in range(60):
		all_ids.append(EnemyDB.roll_enemy_id(wave_rng, 3))
	for enemy_id: Variant in all_ids:
		if not EnemyDB.has_enemy(str(enemy_id)):
			invalid += 1
	t.eq(invalid, 0, "波次摇出的 id 全部合法")

	# 第 1 层不出精英，第 3 层会出现精英
	var early_elite: int = 0
	var late_elite: int = 0
	var elite_rng := RandomNumberGenerator.new()
	elite_rng.seed = 99
	for i: int in range(120):
		if EnemyDB.is_elite_id(EnemyDB.roll_enemy_id(elite_rng, 1)):
			early_elite += 1
		if EnemyDB.is_elite_id(EnemyDB.roll_enemy_id(elite_rng, 3)):
			late_elite += 1
	t.eq(early_elite, 0, "第 1 层不会摇出精英")
	t.gt(float(late_elite), 0.0, "第 3 层会摇出精英")

	# --- 分批投放 ---
	var batches: Array = EnemyDB.split_batches(["a", "b", "c", "d", "e"], 2)
	t.eq(batches.size(), 2, "5 个敌人切成 2 批")
	var total: int = 0
	for batch: Variant in batches:
		total += (batch as Array).size()
	t.eq(total, 5, "分批后总数不变")
	t.eq((batches[0] as Array).size(), 3, "第一批 3 只（交替分配）")
	t.eq(EnemyDB.split_batches(["a"], 2).size(), 1, "数量不足时合成一批")


# ==================== 2. 生成与激活 ====================

func _test_spawn_and_activation(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = world.player
	t.not_null(world.spawner, "世界已装配敌人生成器")
	t.eq(world.spawner.interior, world.interior_rect, "生成器拿到房间内部矩形")
	t.eq(world.spawner.player_node(), player, "生成器绑定玩家")
	t.eq(world.spawner.floor_index, GameState.floor_index, "生成器知道当前层数")

	var spawned_events: Array = []
	var on_spawned := func(enemy: Node) -> void: spawned_events.append(enemy)
	EventBus.enemy_spawned.connect(on_spawned)

	# 自动选点生成
	var husk: Enemy = world.spawn_enemy("husk")
	t.not_null(husk, "自动生成 husk 成功")
	t.eq(spawned_events.size(), 1, "enemy_spawned 触发一次")
	if husk == null:
		EventBus.enemy_spawned.disconnect(on_spawned)
		await _free_world(t, world)
		return
	t.check(world.interior_rect.has_point(husk.global_position), "自动生成点落在房间内部")
	t.gte(husk.global_position.distance_to(player.global_position), G.WAVE_MIN_DISTANCE_TO_PLAYER * 0.85,
			"生成点与玩家保持距离（不贴脸刷怪）")
	t.eq(husk.get_parent(), world.entity_root, "敌人挂在实体层（参与 Y 排序）")
	t.eq(husk.bullet_layer, world.bullet_root, "弹道层已注入")
	t.eq(husk.fx_layer, world.fx_root, "特效层已注入")
	t.eq(husk.data.id, "husk", "数值表已注入")
	t.eq(husk.health, 34.0, "初始生命等于数值表")
	t.eq(husk.health, husk.max_health, "生命为满值")
	t.check(husk.is_in_group(CombatUtil.GROUP_ENEMIES), "敌人进入 enemies 分组")
	t.eq(husk.collision_layer, G.LAYER_ENEMY, "碰撞层为 enemy")
	t.check(G.has_layer(husk.collision_mask, G.LAYER_WORLD), "碰撞掩码包含墙体")
	t.check(G.has_layer(husk.collision_mask, G.LAYER_PLAYER), "碰撞掩码包含玩家")
	t.eq(husk.target, player, "锁定玩家为目标")
	t.check(husk.activated, "生成后立即激活")
	t.check(husk.state != Enemy.State.DORMANT, "激活后不再是休眠状态")
	t.check(husk.state_log.has("dormant"), "状态日志记录了登场")
	t.check(husk._sprite != null and husk._sprite.texture != null, "敌人贴图已加载")
	t.eq(world.spawner.total_spawned, 1, "生成器统计 +1")
	t.eq(world.spawner.alive_count(), 1, "存活计数 1")
	t.check(world.alive_enemy_count() >= 4, "含试验靶在内的可攻击目标数增加")
	t.check(world.spawn_enemy("unknown_id") == null, "未知 id 不会生成敌人")

	# 休眠登场：不立即激活时先凝聚，计时结束后自动激活
	world.spawner.activate_on_spawn = false
	var sleeper: Enemy = world.spawn_enemy("hexeye", player.global_position + Vector2(200, 0))
	t.check(not sleeper.activated, "activate_on_spawn=false 时敌人处于休眠")
	t.eq(sleeper.state, Enemy.State.DORMANT, "休眠状态为 DORMANT")
	t.near(sleeper.activate_timer, G.ENEMY_ACTIVATE_DELAY, 0.05, "登场计时来自常量")
	await _frames(t, int(G.ENEMY_ACTIVATE_DELAY * 60.0) + 8)
	t.check(sleeper.activated, "登场计时结束后自动激活")
	t.check(sleeper.state != Enemy.State.DORMANT, "激活后开始行动")
	t.eq(world.spawner.alive_count(), 2, "存活计数 2")

	EventBus.enemy_spawned.disconnect(on_spawned)
	await _free_world(t, world)


# ==================== 3. 受击与死亡掉落 ====================

func _test_hit_and_death_drops(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	_tough_player(world)
	var enemy: Enemy = world.spawn_enemy("husk", world.player.global_position + Vector2(-200, 0))
	enemy.data.contact_damage = 0.0
	enemy.data.sight_range = 1.0        # 别让它跑过来，专心验证受击契约
	t.not_null(enemy, "生成受击测试敌人")
	if enemy == null:
		await _free_world(t, world)
		return

	var hurt_events: Array = []
	var died_events: Array = []
	var dropped_events: Array = []
	var on_hurt := func(_e: Node, amount: float, is_crit: bool) -> void: hurt_events.append([amount, is_crit])
	var on_died := func(e: Node, _pos: Vector2) -> void: died_events.append(e)
	var on_dropped := func(_e: Node, _pos: Vector2, drops: Array) -> void: dropped_events.append(drops)
	EventBus.enemy_hurt.connect(on_hurt)
	EventBus.enemy_died.connect(on_died)
	EventBus.enemy_dropped.connect(on_dropped)

	# 普通受击
	enemy.take_hit(10.0, false, Vector2.RIGHT * 60.0, 4242)
	t.near(enemy.health, 24.0, 0.01, "10 点伤害后 34 -> 24")
	t.eq(enemy.hit_count, 1, "受击计数 +1")
	t.eq(enemy.last_source_id, 4242, "记录伤害来源")
	t.near(enemy.last_knockback.length(), 60.0, 0.01, "记录击退向量")
	t.gt(enemy.external_velocity.length(), 0.0, "击退冲量已施加")
	t.gt(enemy.hit_flash_timer, 0.0, "受击进入闪白")
	t.eq(hurt_events.size(), 1, "enemy_hurt 触发一次")
	t.near(float((hurt_events[0] as Array)[0]), 10.0, 0.01, "事件携带实际伤害")
	t.check(not (hurt_events[0] as Array)[1], "非暴击标记正确")

	# 暴击标记与累计伤害
	enemy.take_hit(5.0, true, Vector2.ZERO, 4242)
	t.eq(enemy.crit_count, 1, "暴击计数 +1")
	t.near(enemy.health, 19.0, 0.01, "累计扣血 15")
	t.near(enemy.total_damage, 15.0, 0.01, "累计伤害统计正确")

	# 护甲减伤（精英 armor = 1）
	var elite: Enemy = world.spawn_enemy("husk_elite", world.player.global_position + Vector2(200, 0))
	elite.data.contact_damage = 0.0
	elite.data.sight_range = 1.0
	elite.take_hit(6.0, false, Vector2.ZERO, 1)
	t.near(elite.health, elite.max_health - 5.0, 0.01, "护甲 1 点固定减伤（最低 1）")
	t.check(elite.data.is_elite(), "精英标记生效")

	# 击退抗性：精英更"沉"
	enemy.external_velocity = Vector2.ZERO
	elite.external_velocity = Vector2.ZERO
	enemy.take_hit(1.0, false, Vector2.RIGHT * 200.0, 1)
	elite.take_hit(1.0, false, Vector2.RIGHT * 200.0, 1)
	t.gt(enemy.external_velocity.length(), elite.external_velocity.length(), "精英击退抗性更高")

	# 致死：掉落只结算一次（自爆怪递归的历史坑）
	var gold_before: int = GameState.gold
	var kills_before: int = GameState.kills
	enemy.take_hit(9999.0, false, Vector2.ZERO, 4242)
	t.check(enemy.dead, "血量归零后死亡")
	t.eq(enemy.health, 0.0, "死亡后生命为 0")
	t.eq(enemy.state, Enemy.State.DEAD, "状态切到 DEAD")
	t.check(enemy.last_state != Enemy.State.DEAD, "记录了死亡前的状态")
	t.eq(enemy.collision_layer, 0, "死亡后关闭碰撞层")
	t.eq(enemy.collision_mask, 0, "死亡后关闭碰撞掩码")
	t.eq(died_events.size(), 1, "enemy_died 只触发一次")
	t.eq(dropped_events.size(), 1, "enemy_dropped 只触发一次")
	t.check(not enemy.death_drops.is_empty(), "死亡结算了掉落表")
	t.eq(dropped_events[0], enemy.death_drops, "事件携带的掉落与结算一致")
	t.eq(int((enemy.death_drops[0] as Dictionary)["kind"]), G.PickupKind.COIN, "掉落首项为金币")
	t.eq(GameState.kills, kills_before + 1, "击杀计数 +1")
	t.gte(float(GameState.score), 10.0, "得分累计（husk = 10 分）")
	# M6 起金币不再直接入账：先掉成实体拾取物，玩家吸附/走过才结算
	t.eq(world.gold_from_drops, 0, "掉落瞬间金币还没入账（等拾取物结算）")
	t.eq(GameState.gold, gold_before, "拾取前金币不变")
	t.check(world.drop_stats.has(G.PickupKind.COIN), "掉落统计记录了金币")
	await _frames(t, 3)
	t.gte(float(world.queued_drops.size() + world.pickup_count()), 1.0, "掉落已生成实体拾取物")
	var coin: Pickup = null
	for entry: Variant in world.room_pickups:
		if entry is Pickup and (entry as Pickup).kind == G.PickupKind.COIN:
			coin = entry
			break
	if coin != null:
		coin.collect()
	t.gt(float(world.gold_from_drops), 0.0, "金币拾取物结算后进账")
	t.gt(float(GameState.gold - gold_before), 0.0, "玩家金币增加")

	# 死亡动画：缩放淡出后计时归零，auto_free=false 时保留节点
	t.gt(enemy.death_timer, 0.0, "进入死亡动画计时")
	await _frames(t, 30)
	t.near(enemy.death_timer, -1.0, 0.001, "动画结束后计时归零")
	t.check(is_instance_valid(enemy), "auto_free=false 时保留节点供断言")
	t.eq(world.spawner.alive_count(), 1, "存活计数只统计未死亡敌人")
	t.check(not enemy.is_dead_or_disabled() == false, "is_dead_or_disabled 返回 true")

	# auto_free=true 时动画结束后自动释放
	world.spawner.auto_free = true
	var temp: Enemy = world.spawn_enemy("husk", world.player.global_position + Vector2(0, -260))
	temp.data.contact_damage = 0.0
	temp.data.sight_range = 1.0
	temp.data.explode_on_death = false
	temp.take_hit(9999.0, false, Vector2.ZERO, 1)
	await _frames(t, 40)
	t.check(not is_instance_valid(temp), "auto_free=true 时死亡动画结束后释放节点")

	EventBus.enemy_hurt.disconnect(on_hurt)
	EventBus.enemy_died.disconnect(on_died)
	EventBus.enemy_dropped.disconnect(on_dropped)
	await _free_world(t, world)


# ==================== 4a. 近战冲锋 ====================

func _test_melee_charge(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = _tough_player(world)

	var hurt_events: Array = []
	var on_hurt := func(_amount: float, _from_shield: bool) -> void: hurt_events.append(_amount)
	EventBus.player_hurt.connect(on_hurt)

	# 追踪 -> 起手 -> 冲刺 -> 撞人
	var husk: EnemyHusk = world.spawn_enemy("husk", player.global_position + Vector2(-200, 0)) as EnemyHusk
	husk.data.contact_damage = 0.0
	t.check(husk is EnemyHusk, "近战原型实例化为 EnemyHusk")
	await _frames(t, 6)
	t.eq(husk.state_name(), "chase", "远距离时处于追踪状态")
	t.gt(husk.move_velocity.length(), 0.0, "追踪时有位移意图")
	var distance_before: float = husk.global_position.distance_to(player.global_position)
	await _frames(t, 24)
	t.check(husk.global_position.distance_to(player.global_position) < distance_before, "追踪拉近与玩家的距离")
	t.check(husk.global_position.distance_to(player.global_position) < husk.data.charge_trigger_range + 40.0,
			"持续追踪直到进入起手距离")

	await _wait_until(t, func() -> bool: return husk.state == Enemy.State.ATTACK and husk.windup_timer > 0.0, 200)
	t.check(husk.windup_timer > 0.0, "进入起手预警（给玩家反应时间）")
	t.near(husk.windup_timer, 0.34, 0.25, "起手时长约 0.34 秒")
	t.check(husk.state_log.has("attack"), "状态日志记录了 attack")
	t.near(husk.charge_direction.length(), 1.0, 0.01, "起手时锁定冲刺方向")

	await _wait_until(t, func() -> bool: return husk.charge_timer > 0.0, 120)
	t.check(husk.charge_timer > 0.0, "起手结束后进入冲刺")
	t.eq(husk.charges_done, 1, "冲刺计数 +1")
	t.gte(husk.attacks_made, 1.0, "攻击计数 +1")
	t.gte(husk.velocity.length(), 240.0, "冲刺速度接近数值表的 320")

	await _wait_until(t, func() -> bool: return husk.charge_hits >= 1 or husk.charge_timer <= 0.0, 120)
	t.gte(float(husk.charge_hits), 1.0, "冲刺撞到玩家")
	t.gt(husk.damage_dealt, 0.0, "撞击对玩家造成伤害")
	t.gte(float(hurt_events.size()), 1.0, "player_hurt 事件触发")
	t.gte(husk.attack_cooldown, 0.0, "冲刺结束后进入冷却")

	# 撞墙眩晕：把冲刺方向锁向左墙
	var wall_husk: EnemyHusk = world.spawn_enemy("husk",
			Vector2(world.interior_rect.position.x + 70.0, player.global_position.y)) as EnemyHusk
	wall_husk.data.contact_damage = 0.0
	wall_husk.facing = Vector2.LEFT
	wall_husk._begin_windup()
	t.near(wall_husk.charge_direction.x, -1.0, 0.01, "起手锁定为向左冲刺")
	wall_husk.windup_timer = 0.05
	await _frames(t, 26)
	t.gte(float(wall_husk.wall_stuns), 1.0, "冲刺撞墙后进入眩晕")
	t.eq(wall_husk.state_name(), "stunned", "撞墙后状态为 stunned")
	t.gt(wall_husk.stun_timer, 0.0, "眩晕计时生效")
	t.eq(wall_husk.charge_timer, 0.0, "撞墙后冲刺结束")

	# 强击退打断冲锋（玩家的反击窗口）
	var third: EnemyHusk = world.spawn_enemy("husk", player.global_position + Vector2(-100, 0)) as EnemyHusk
	third.data.contact_damage = 0.0
	third.attack_cooldown = 0.0
	await _wait_until(t, func() -> bool: return third.state == Enemy.State.ATTACK, 120)
	t.eq(third.state_name(), "attack", "第三个敌人进入起手")
	var knocked: int = third.interrupts
	third.take_hit(1.0, false, Vector2.RIGHT * 400.0, 1)
	t.gt(float(third.interrupts), float(knocked), "强击退触发打断")
	t.eq(third.windup_timer, 0.0, "起手被打断")
	t.eq(third.charge_timer, 0.0, "冲锋被打断")
	await _frames(t, 3)
	t.eq(third.state_name(), "stunned", "打断后短暂硬直")
	t.check(not third.dead, "1 点伤害不会打死它")

	# 小击退不打断（避免被手枪点一下就永远冲不了锋）
	var fourth: EnemyHusk = world.spawn_enemy("husk", player.global_position + Vector2(120, 40)) as EnemyHusk
	fourth.data.contact_damage = 0.0
	fourth.attack_cooldown = 0.0
	await _wait_until(t, func() -> bool: return fourth.state == Enemy.State.ATTACK, 120)
	fourth.take_hit(1.0, false, Vector2.LEFT * 40.0, 1)
	t.eq(fourth.interrupts, 0, "小击退不打断动作")
	t.eq(fourth.state_name(), "attack", "小击退后继续起手")

	EventBus.player_hurt.disconnect(on_hurt)
	await _free_world(t, world)


# ==================== 4b. 远程射击 ====================

func _test_ranged_shooter(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = _tough_player(world)

	var hexeye: EnemyHexeye = world.spawn_enemy("hexeye", player.global_position + Vector2(-150, 0)) as EnemyHexeye
	hexeye.data.contact_damage = 0.0
	t.check(hexeye is EnemyHexeye, "远程原型实例化为 EnemyHexeye")

	# 瞄准预警：先亮红光停顿，此时还没有弹丸
	await _wait_until(t, func() -> bool: return hexeye.state == Enemy.State.ATTACK and hexeye.aim_timer > 0.0, 120)
	t.check(hexeye.aim_timer > 0.0, "开火前进入瞄准预警")
	t.gt(hexeye.glow_boost, 0.0, "瞄准时脚下红光预警")
	t.eq(world.bullet_count(), 0, "预警阶段还没有弹丸")
	t.check(hexeye._has_line_of_sight(), "开阔地带视线通畅")

	# 开火：敌弹进入弹道层，归属与碰撞层正确
	await _wait_until(t, func() -> bool: return hexeye.bullets_fired >= 1, 120)
	t.eq(hexeye.bullets_fired, 1, "普通六目一轮一发")
	t.eq(hexeye.rounds_fired, 1, "轮次计数 +1")
	t.gte(float(world.bullet_count()), 1.0, "弹道层出现敌方弹丸")
	var bullet: Bullet = _first_enemy_bullet(world)
	t.not_null(bullet, "能找到敌方弹丸")
	if bullet != null:
		t.check(not bullet.from_player, "弹丸归属为敌方")
		t.eq(bullet.collision_layer, G.LAYER_ENEMY_BULLET, "敌弹使用敌方子弹层")
		t.check(G.has_layer(bullet._target_mask, G.LAYER_PLAYER), "敌弹可以打到玩家")
		t.near(bullet.damage, 9.0, 0.01, "敌弹伤害来自数值表")
		t.check(not bullet.custom_textures.is_empty(), "敌弹使用原创贴图")
		t.near(bullet.fly_velocity.length(), 265.0, 20.0, "敌弹弹速来自数值表")
		var to_player: Vector2 = (player.global_position - bullet.global_position).normalized()
		t.gt(bullet.fly_velocity.normalized().dot(to_player), 0.8, "敌弹朝玩家飞去")
		t.eq(bullet.source, hexeye, "弹丸记录了发射者")

	# 一轮打完进冷却，预警光解除
	await _wait_until(t, func() -> bool: return hexeye.attack_cooldown > 0.0 and hexeye.state == Enemy.State.CHASE, 180)
	t.gt(hexeye.attack_cooldown, 0.0, "开火后进入冷却")
	t.lte(hexeye.attack_cooldown, 1.7, "冷却不超过数值表的 1.7 秒")
	t.near(hexeye.glow_boost, -1.0, 0.001, "冷却时解除预警光")
	_clear_bullets(world)

	# 贴脸时先拉开距离（风筝手感），不会站着硬拼
	# 先把索敌距离压到 55：距离 60 时它够不着玩家，只能后退，借此单独验证"拉开距离"这一段行为
	var kiter: EnemyHexeye = world.spawn_enemy("hexeye", player.global_position + Vector2(-60, 0)) as EnemyHexeye
	kiter.data.contact_damage = 0.0
	kiter.data.sight_range = 55.0
	var close_distance: float = kiter.global_position.distance_to(player.global_position)
	await _frames(t, 40)
	t.gt(kiter.global_position.distance_to(player.global_position), close_distance, "距离过近时会后退拉开")
	t.gte(kiter.global_position.distance_to(player.global_position), kiter.data.keep_distance_min * 0.6,
			"保持最小交战距离")
	t.eq(kiter.bullets_fired, 0, "够不着玩家时不开火（先拉距离）")

	# 恢复索敌：拉开距离后就会开始射击
	kiter.data.sight_range = 380.0
	await _wait_until(t, func() -> bool: return kiter.bullets_fired >= 1, 180)
	t.gte(float(kiter.bullets_fired), 1.0, "拉开距离后恢复开火")
	t.gte(kiter.global_position.distance_to(player.global_position), kiter.data.keep_distance_min * 0.7,
			"开火时已站到安全距离之外")

	# 精英三连发
	var elite: EnemyHexeye = world.spawn_enemy("hexeye_elite", player.global_position + Vector2(150, 0)) as EnemyHexeye
	elite.data.contact_damage = 0.0
	t.eq(elite.data.burst_count, 3, "精英六目一轮三连发")
	_clear_bullets(world)
	await _wait_until(t, func() -> bool: return elite.bullets_fired >= 3, 240)
	t.eq(elite.bullets_fired, 3, "精英一轮打完 3 发")
	t.eq(elite.rounds_fired, 3, "每发都算一次射击")
	t.gte(float(world.bullet_count()), 3.0, "弹道层同时存在 3 发敌弹")

	# 强击退打断瞄准
	var interrupted: EnemyHexeye = world.spawn_enemy("hexeye", player.global_position + Vector2(120, -120)) as EnemyHexeye
	interrupted.data.contact_damage = 0.0
	await _wait_until(t, func() -> bool: return interrupted.state == Enemy.State.ATTACK and interrupted.aim_timer > 0.0, 180)
	t.check(interrupted.aim_timer > 0.0, "第四个敌人进入瞄准")
	var shots_before: int = interrupted.bullets_fired
	interrupted.take_hit(1.0, false, Vector2.UP * 400.0, 1)
	t.gte(float(interrupted.interrupts), 1.0, "瞄准被强击退打断")
	t.eq(interrupted.aim_timer, 0.0, "瞄准计时被清空")
	t.eq(interrupted.burst_left, 0, "本轮作废")
	t.eq(interrupted.state_name(), "stunned", "打断后短暂硬直")
	t.gt(interrupted.attack_cooldown, 0.0, "打断后进入短冷却")
	t.eq(interrupted.bullets_fired, shots_before, "打断后没有射出弹丸")

	_clear_bullets(world)
	await _free_world(t, world)


# ==================== 4c. 自爆 ====================

func _test_bomber_fuse(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = _tough_player(world)

	var explosions: Array = []
	var hurt_events: Array = []
	var dropped_events: Array = []
	var on_explode := func(pos: Vector2, radius: float) -> void: explosions.append([pos, radius])
	var on_hurt := func(_amount: float, _from_shield: bool) -> void: hurt_events.append(_amount)
	var on_dropped := func(_e: Node, _pos: Vector2, drops: Array) -> void: dropped_events.append(drops)
	EventBus.explosion_occurred.connect(on_explode)
	EventBus.player_hurt.connect(on_hurt)
	EventBus.enemy_dropped.connect(on_dropped)

	# 贴身触发引信
	var bloom: EnemyBloom = world.spawn_enemy("bloom", player.global_position + Vector2(-40, 0)) as EnemyBloom
	bloom.data.contact_damage = 0.0
	t.check(bloom is EnemyBloom, "自爆原型实例化为 EnemyBloom")
	await _wait_until(t, func() -> bool: return bloom.fusing, 60)
	t.check(bloom.fusing, "进入引信范围后开始蓄力")
	t.eq(bloom.state_name(), "attack", "蓄力时状态为 attack")
	t.gte(float(bloom.charge_level), 1.0, "蓄力档位从 1 开始")
	t.gt(bloom.fuse_timer, 0.0, "引信计时启动")
	t.near(bloom.fuse_timer, 0.78, 0.2, "引信时长约 0.78 秒")

	# 蓄力不可打断（只能用距离/掩体应对）
	bloom.take_hit(1.0, false, Vector2.RIGHT * 500.0, 1)
	t.gte(float(bloom.interrupts), 1.0, "记录了打断尝试")
	t.check(bloom.fusing, "蓄力不可被打断")
	t.gt(bloom.fuse_timer, 0.0, "引信仍在走")
	t.eq(bloom.state_name(), "attack", "打断尝试不改变状态")
	t.check(not bloom.dead, "1 点伤害不会打死它")

	# 档位递进 + 切换膨胀贴图
	await _wait_until(t, func() -> bool: return bloom.charge_level >= 2, 120)
	t.gte(float(bloom.charge_level), 2.0, "蓄力越久档位越高")
	t.check(bloom._sprite.texture != bloom.data.frames()[0], "蓄力时切换到膨胀贴图")
	t.gt(bloom._sprite.scale.x, 1.0, "蓄力时体积脉动变大")

	# 引信走完 -> 爆炸
	bloom.fuse_timer = 0.05
	player.clear_invulnerable()
	await _wait_until(t, func() -> bool: return bloom.exploded, 60)
	t.check(bloom.exploded, "引信走完后爆炸")
	t.eq(bloom.explosions, 1, "爆炸计数 1")
	t.check(bloom.dead, "自爆后自身死亡")
	t.eq(bloom.state, Enemy.State.DEAD, "状态切到 DEAD")
	t.gte(float(explosions.size()), 1.0, "explosion_occurred 事件触发")
	t.near(float((explosions[0] as Array)[1]), 64.0, 0.01, "爆炸半径来自数值表")
	t.gt(bloom.damage_dealt, 0.0, "爆炸对玩家造成伤害")
	t.gte(float(hurt_events.size()), 1.0, "player_hurt 事件触发")
	t.eq(dropped_events.size(), 1, "自爆只结算一次掉落")
	t.check(not bloom.death_drops.is_empty(), "自爆也有掉落")

	# 临终引爆 + 连锁：远处一对孢晶囊，杀掉一只会带走另一只
	explosions.clear()
	dropped_events.clear()
	var anchor: Vector2 = player.global_position + Vector2(-220, -120)
	var b1: EnemyBloom = world.spawn_enemy("bloom", anchor) as EnemyBloom
	var b2: EnemyBloom = world.spawn_enemy("bloom", anchor + Vector2(26, 0)) as EnemyBloom
	b1.data.contact_damage = 0.0
	b2.data.contact_damage = 0.0
	# 刚加入场景树的刚体要等一次物理步进才会登记进物理空间，
	# 否则爆炸的范围查询查不到它们（实战中敌人不会刚生成就被引爆）
	await _frames(t, 4)
	t.check(not b1.fusing, "距离玩家较远时不会自行蓄力")
	b1.take_hit(9999.0, false, Vector2.ZERO, 1)
	t.check(b1.exploded, "被击杀时临终引爆")
	t.check(b1.dead, "被击杀后死亡")
	await _frames(t, 8)
	t.check(b2.exploded, "同族被连锁引爆")
	t.check(b2.dead, "连锁引爆后同样死亡")
	t.gte(float(b1.chain_count), 1.0, "爆炸波及统计到同族")
	t.gte(float(explosions.size()), 2.0, "连锁产生两次爆炸事件")
	t.eq(dropped_events.size(), 2, "两只各自结算一次掉落")

	# 爆炸半径之外的玩家不会被波及
	var far: EnemyBloom = world.spawn_enemy("bloom", player.global_position + Vector2(260, -60)) as EnemyBloom
	far.data.contact_damage = 0.0
	hurt_events.clear()
	far.take_hit(9999.0, false, Vector2.ZERO, 1)
	t.check(far.exploded, "远处的孢晶囊被击杀也会炸")
	t.eq(far.damage_dealt, 0.0, "半径外不造成伤害")
	t.eq(hurt_events.size(), 0, "半径外玩家不受伤")

	EventBus.explosion_occurred.disconnect(on_explode)
	EventBus.player_hurt.disconnect(on_hurt)
	EventBus.enemy_dropped.disconnect(on_dropped)
	await _free_world(t, world)


# ==================== 5. 分离力：不互相重叠 ====================

func _test_separation(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	world.player.set_invulnerable(30.0)
	var center: Vector2 = world.player.global_position + Vector2(0, -64)
	var cluster: Array = []
	for i: int in range(6):
		var enemy: Enemy = world.spawn_enemy("husk", center + Vector2(float(i) * 2.0, 0.0))
		# 关闭索敌：让它们只受分离力与游荡影响，便于验证"不重叠"
		enemy.data.sight_range = 1.0
		enemy.data.contact_damage = 0.0
		cluster.append(enemy)
	t.eq(cluster.size(), 6, "生成 6 个挤在一起的敌人")

	await _frames(t, 70)
	var alive: int = 0
	var min_distance: float = 1e9
	for i: int in range(cluster.size()):
		var a: Enemy = cluster[i]
		if not is_instance_valid(a) or a.dead:
			continue
		alive += 1
		for j: int in range(i + 1, cluster.size()):
			var b: Enemy = cluster[j]
			if not is_instance_valid(b) or b.dead:
				continue
			min_distance = minf(min_distance, a.global_position.distance_to(b.global_position))
	t.eq(alive, 6, "6 个敌人都还活着")
	t.gt(min_distance, 8.0, "分离力把它们推开（不重叠成一坨）")
	t.lte(min_distance, 120.0, "分离力不会把它们炸飞到房间各处")
	t.gt(float(world.spawner.alive_count()), 5.0, "生成器存活计数与实际一致")

	await _free_world(t, world)


# ==================== 6. 波次调度 ====================

func _test_wave_scheduling(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	world.player.set_invulnerable(60.0)
	var cleared_events: Array = []
	var batch_events: Array = []
	var on_cleared := func() -> void: cleared_events.append(true)
	var on_batch := func(_index: int, ids: Array) -> void: batch_events.append(ids)
	world.spawner.wave_cleared.connect(on_cleared)
	world.spawner.batch_spawned.connect(on_batch)

	var ids: Array = world.spawn_wave(["husk", "hexeye", "bloom", "husk", "hexeye"])
	t.eq(ids.size(), 5, "波次返回全部敌人 id")
	t.eq(world.spawner.wave_ids.size(), 5, "波次 id 已记录")
	t.check(world.spawner.active, "波次进行中")
	t.check(not world.spawner.cleared, "尚未清空")
	t.eq(world.spawner.batches.size(), 2, "5 只敌人切成 2 批")
	t.eq(world.spawner.batches_spawned, 1, "先投放第一批")
	t.eq(world.spawner.pending_batches.size(), 1, "第二批待投放")
	t.eq(world.spawner.alive_count(), 3, "第一批 3 只已在场")
	t.eq(batch_events.size(), 1, "batch_spawned 触发一次")
	t.near(world.spawner.batch_timer, G.WAVE_BATCH_DELAY, 0.15, "批次间隔来自常量")

	var all_inside: bool = true
	var nearest: float = 1e9
	for entry: Variant in world.spawner.alive_enemies():
		var enemy: Enemy = entry
		all_inside = all_inside and world.interior_rect.has_point(enemy.global_position)
		nearest = minf(nearest, enemy.global_position.distance_to(world.player.global_position))
	t.check(all_inside, "所有生成点都在房间内部")
	t.gte(nearest, G.WAVE_MIN_DISTANCE_TO_PLAYER * 0.8, "生成点避开玩家")
	t.eq(world.spawner.enemies_of_archetype(EnemyData.Archetype.BOMBER).size(), 1, "能按原型筛选敌人")

	# 第二批投放
	world.spawner.batch_timer = 0.05
	await _frames(t, 8)
	t.eq(world.spawner.batches_spawned, 2, "第二批已投放")
	t.eq(world.spawner.alive_count(), 5, "5 只全部在场")
	t.eq(world.spawner.total_spawned, 5, "累计生成 5 只")
	t.check(world.spawner.pending_batches.is_empty(), "没有剩余批次")
	t.check(not world.spawner.cleared, "仍有存活敌人时不算清空")

	# 清场判定
	var killed: int = world.spawner.kill_all()
	t.eq(killed, 5, "kill_all 返回击杀数量")
	t.eq(world.spawner.alive_count(), 0, "存活数归零")
	await _frames(t, 6)
	t.check(world.spawner.cleared, "全部清完后标记清空")
	t.check(not world.spawner.active, "波次结束")
	t.eq(cleared_events.size(), 1, "wave_cleared 触发一次")

	# 起始房：空波次立即视为清空（M5 开门逻辑依赖这一点）
	world.spawner.despawn_all()
	world.spawner.room_kind = G.RoomKind.START
	cleared_events.clear()
	var empty: Array = world.spawn_wave([])
	t.eq(empty.size(), 0, "起始房波次为空")
	t.check(world.spawner.cleared, "空波次立即清空")
	t.eq(cleared_events.size(), 1, "空波次也发出 wave_cleared")
	t.eq(world.spawn_wave([]).size(), 0, "重复调用仍然安全")

	world.spawner.wave_cleared.disconnect(on_cleared)
	world.spawner.batch_spawned.disconnect(on_batch)
	await _free_world(t, world)
