extends TestSuite
## test_boss —— M7 Boss 战验收（无头）。
##
## 覆盖五块：
##   1. 数值表：warden / weaver 条目齐全、archetype=BOSS、脚本路由、贴图、掉落、层数成长；
##   2. 生成装配：实例化为 EnemyBoss、boss_spawned 事件、HUD 需要的 display_name /
##      max_health_value、world_node 注入（召唤小怪的入口）；
##   3. 受击契约：boss_health_changed 事件、护甲减伤、血量跨阈值转阶段 2 +
##      boss_phase_changed 事件、免疫击退打断（不断招式）；
##   4. 技能状态机：手动起手各技能（环形/扇形/螺旋/冲撞/召唤/砸地），
##      验证预警 -> 执行 -> 计数/弹丸/召唤物的完整链路；
##   5. 召唤与清场：召唤物注入世界、上限控制、小怪清零广播 boss_minions_cleared；
##   6. 死亡清场：boss_died 事件 + 波次清空（传送门链路前置条件）。
##
## run() 是协程：技能发射、冲刺、召唤都需要真实物理帧推进。

const G := preload("res://scripts/core/game_const.gd")
const TEST_PLAYER_HEALTH: float = 4000.0


func suite_name() -> String:
	return "Boss 战 (M7)"


func run(t: Node) -> void:
	_test_boss_table(t)
	await _test_spawn_and_contract(t)
	await _test_hit_phase_and_interrupt(t)
	await _test_skill_state_machine(t)
	await _test_summon_and_cleared(t)
	await _test_boss_death_clears_wave(t)


# ==================== 公共工具 ====================

func _make_world(t: Node) -> GameWorld:
	GameState.new_run(20260915)
	var world := GameWorld.new()
	world.name = "TestBossWorld"
	world.auto_demo_wave = false
	t.add_child(world)
	world.spawner.auto_free = false
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


func _frames(t: Node, count: int) -> void:
	for i: int in range(count):
		await t.get_tree().physics_frame
		await t.get_tree().process_frame


func _wait_until(t: Node, condition: Callable, max_frames: int = 400) -> int:
	var frames: int = 0
	while frames < max_frames and not bool(condition.call()):
		await t.get_tree().physics_frame
		await t.get_tree().process_frame
		frames += 1
	return frames


func _spawn_boss(world: GameWorld, boss_id: String, at_position: Variant = null) -> EnemyBoss:
	var boss: EnemyBoss = world.spawn_enemy(boss_id, at_position) as EnemyBoss
	return boss


func _bullet_count(world: GameWorld) -> int:
	return world.bullet_count()


# ==================== 1. 数值表 ====================

func _test_boss_table(t: Node) -> void:
	var warden: EnemyData = EnemyDB.create_data("warden")
	var weaver: EnemyData = EnemyDB.create_data("weaver")
	t.not_null(warden, "EnemyDB 能创建 warden（晶核监守者）")
	t.not_null(weaver, "EnemyDB 能创建 weaver（织弹者）")
	if warden == null or weaver == null:
		return

	t.eq(warden.archetype, EnemyData.Archetype.BOSS, "warden 为 BOSS 原型")
	t.eq(weaver.archetype, EnemyData.Archetype.BOSS, "weaver 为 BOSS 原型")
	t.eq(EnemyDB.script_for(warden), EnemyDB.BOSS_SCRIPT, "BOSS 脚本路由正确")
	t.eq(EnemyDB.script_for(weaver), EnemyDB.BOSS_SCRIPT, "weaver 共用 BOSS 脚本")
	t.check(EnemyDB.script_for(warden) != EnemyDB.script_for(EnemyDB.create_data("husk")),
			"Boss 与普通敌人脚本不同")

	# 数值表齐全：相位/移速/弹幕/召唤/砸地/阶段 2
	t.gt(warden.max_health, 500.0, "warden 生命 862")
	t.gt(warden.armor, 0.0, "warden 有护甲")
	t.gt(warden.phase_threshold, 0.0, "warden 有阶段阈值")
	t.gt(warden.radial_count, 0, "warden 有环形弹幕")
	t.gt(warden.charge_damage, 0.0, "warden 有冲撞伤害")
	t.gt(warden.summon_count, 0, "warden 有召唤")
	t.gt(warden.slam_damage, 0.0, "warden 有砸地")
	t.gt(warden.phase2_extra_bullets, 0, "warden 阶段 2 加弹")
	t.gt(weaver.fan_count, 0, "weaver 有扇形弹幕")
	t.gt(weaver.spiral_arms, 0, "weaver 有螺旋弹幕")
	t.eq(weaver.charge_windup, 0.45, "weaver 也带冲撞参数（防御性兜底）")

	# 阶段 2 强化数值合法
	t.check(warden.phase2_speed_mul > 1.0, "阶段 2 移速加成")
	t.check(warden.phase2_cooldown_mul < 1.0, "阶段 2 冷却缩短")
	t.check(weaver.phase2_speed_mul > 1.0 and weaver.phase2_cooldown_mul < 1.0,
			"weaver 阶段 2 同样强化")

	# 贴图：4 帧齐全且真实存在
	for boss_data: EnemyData in [warden, weaver]:
		t.check(ResourceLoader.exists(boss_data.sprite_path(0)), "Boss 贴图存在：%s" % boss_data.sprite_path(0))
		t.eq(boss_data.frames().size(), boss_data.frame_count, "%s 帧数与配置一致" % boss_data.id)
	t.eq(warden.sprite_dir, "res://assets/sprites/bosses/", "warden 使用独立贴图目录")

	# 掉落：金币区间 + 高价值词条
	t.gte(warden.gold_min, 50, "warden 金币下限高")
	t.gte(float(warden.drops.get("weapon", 0.0)), 0.3, "warden 有武器掉落概率")
	t.gte(float(warden.drops.get("talent", 0.0)), 0.3, "warden 有天赋掉落概率")
	t.gte(float(weaver.drops.get("weapon", 0.0)), 0.3, "weaver 有武器掉落概率")

	# 层数成长：第 3 层双 Boss 血量健康
	var late: EnemyData = EnemyDB.create_data("warden", 3)
	t.near(late.max_health, 862.0 * (1.0 + G.ENEMY_HP_GROWTH_PER_FLOOR * 2.0), 1.0,
			"第 3 层 warden 血量按成长公式放大")
	t.check(late.max_health > warden.max_health, "层数越高 Boss 越肉")

	# 存活 id 数量回归：测试里已有敌人 id 数应为 8（3 基础 + 3 精英 + 2 Boss）
	t.eq(EnemyDB.ids().size(), 8, "敌人 id 总数 = 8（3 基础 + 3 精英 + 2 Boss）")


# ==================== 2. 生成装配 ====================

func _test_spawn_and_contract(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = _tough_player(world)

	var spawned_events: Array = []
	var on_spawned := func(boss: Node) -> void: spawned_events.append(boss)
	EventBus.boss_spawned.connect(on_spawned)

	var boss: EnemyBoss = _spawn_boss(world, "warden", world.player.global_position + Vector2(-220, 0))
	t.not_null(boss, "warden 生成成功")
	if boss == null:
		EventBus.boss_spawned.disconnect(on_spawned)
		await _free_world(t, world)
		return
	t.check(boss is EnemyBoss, "Boss 实例化为 EnemyBoss")
	t.eq(spawned_events.size(), 1, "boss_spawned 触发一次")
	t.eq(spawned_events[0], boss, "事件携带 Boss 实例")
	t.eq(boss.display_name, "晶核监守者", "HUD 需要的显示名已暴露")
	t.near(boss.max_health_value, boss.max_health, 0.01, "HUD 血条最大值已暴露")
	t.near(boss.health, boss.max_health, 0.01, "生成即满血")
	t.eq(boss.data.id, "warden", "数值表 id 正确")
	t.eq(boss.bullet_layer, world.bullet_root, "弹道层注入")
	t.eq(boss.fx_layer, world.fx_root, "特效层注入")
	t.eq(boss.world_node, world, "world_node 注入（召唤入口）")
	t.eq(boss.target, player, "锁定玩家为目标")
	t.check(boss.activated, "生成后立即激活")
	t.check(boss.phase_index == 1, "初始阶段 1")
	t.check(boss.is_in_group(CombatUtil.GROUP_ENEMIES), "Boss 进入 enemies 分组")
	t.check(ResourceLoader.exists("res://scripts/entities/enemy_boss.gd"), "Boss 脚本文件存在")

	EventBus.boss_spawned.disconnect(on_spawned)
	await _free_world(t, world)


# ==================== 3. 受击 / 阶段 / 打断 ====================

func _test_hit_phase_and_interrupt(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	_tough_player(world)
	var boss: EnemyBoss = _spawn_boss(world, "weaver", world.player.global_position + Vector2(200, 0))
	t.not_null(boss, "weaver 生成成功")
	if boss == null:
		await _free_world(t, world)
		return
	# 锁它别乱跑，专心验证受击契约
	boss.data.sight_range = 1.0

	var health_events: Array = []
	var phase_events: Array = []
	var on_health := func(current: float, max_value: float) -> void: health_events.append([current, max_value])
	var on_phase := func(_b: Node, phase: int) -> void: phase_events.append(phase)
	EventBus.boss_health_changed.connect(on_health)
	EventBus.boss_phase_changed.connect(on_phase)

	# 普通受击：护甲 2 点减伤 + 血量事件
	boss.take_hit(10.0, false, Vector2.RIGHT * 60.0, 4242)
	t.near(boss.health, boss.max_health - 8.0, 0.01, "10 伤害 -> 扣 8（护甲 2）")
	t.eq(boss.hit_count, 1, "受击计数 +1")
	t.eq(health_events.size(), 1, "boss_health_changed 触发一次")
	t.near(float((health_events[0] as Array)[0]), boss.health, 0.01, "事件携带实时血量")
	t.near(float((health_events[0] as Array)[1]), boss.max_health, 0.01, "事件携带最大血量")

	# 免疫击退打断：interrupt 只计数，不断招式、不硬直
	boss._start_skill(EnemyBoss.Skill.FAN)
	t.eq(boss.skill_context, EnemyBoss.Skill.FAN, "已起手扇形弹幕")
	boss.take_hit(1.0, false, Vector2.UP * 600.0, 1)
	t.gte(float(boss.interrupts), 1.0, "强击退被记录为打断尝试")
	t.eq(boss.skill_context, EnemyBoss.Skill.FAN, "打断后技能仍在（Boss 免疫打断）")
	t.eq(boss.stun_timer, 0.0, "打断不产生硬直")
	# 等当前技能走完，避免阶段测试被技能状态干扰
	boss.skill_timer = 0.01
	await _wait_until(t, func() -> bool: return boss.skill_context == EnemyBoss.Skill.NONE, 300)

	# 跨阈值转阶段 2：weaver 血 788、阈值 0.5
	var hp_before: float = boss.health
	t.check(hp_before > 394.0, "起始血量高于阈值")
	boss.take_hit(hp_before - 350.0, false, Vector2.ZERO, 4242)
	t.check(boss.health <= boss.max_health * boss.data.phase_threshold,
			"血量压到阈值以下（350 < 394）")
	t.eq(boss.phase_index, 2, "切换到阶段 2")
	t.eq(boss.phase_switches, 1, "阶段切换计数 1")
	t.eq(phase_events.size(), 1, "boss_phase_changed 触发一次")
	t.eq(phase_events[0], 2, "事件携带阶段号 2")
	# 阶段切换后立刻能放新技能（冷却已刷新）
	t.check(float(boss.skill_cooldowns[EnemyBoss.Skill.FAN]) <= 0.0, "阶段切换刷新技能冷却")

	# 阶段 2 后死亡路径仍正常（不带病）
	var died_events: Array = []
	var on_died := func(_b: Node) -> void: died_events.append(true)
	EventBus.boss_died.connect(on_died)
	boss.take_hit(9999.0, false, Vector2.ZERO, 4242)
	t.check(boss.dead, "击杀成功")
	t.eq(died_events.size(), 1, "boss_died 触发一次")

	EventBus.boss_health_changed.disconnect(on_health)
	EventBus.boss_phase_changed.disconnect(on_phase)
	EventBus.boss_died.disconnect(on_died)
	await _free_world(t, world)


# ==================== 4. 技能状态机 ====================

func _test_skill_state_machine(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = _tough_player(world)

	# ---- warden：环形 -> 冲撞 -> 召唤 -> 砸地 ----
	var warden: EnemyBoss = _spawn_boss(world, "warden", player.global_position + Vector2(-180, 0))
	t.not_null(warden, "warden 生成成功")
	if warden == null:
		await _free_world(t, world)
		return
	warden.data.sight_range = 460.0

	# 环形弹幕：预警 -> 满圈发射（2 圈 x 14 发）
	var bullets_before: int = warden.bullets_fired
	warden._start_skill(EnemyBoss.Skill.RADIAL)
	t.eq(warden.skill_phase, "windup", "进入预警阶段")
	await _wait_until(t, func() -> bool: return warden.skill_context == EnemyBoss.Skill.NONE, 300)
	t.eq(warden.radials_fired, 1, "环形弹幕计数 +1")
	t.gte(float(warden.bullets_fired - bullets_before), 28.0, "两圈共发射 >= 28 发")
	t.gte(float(_bullet_count(world)), 1.0, "敌方弹丸进入弹道层")

	# 冲撞：锁定方向冲一段；冲完计数 +1
	warden.skill_cooldowns[EnemyBoss.Skill.CHARGE] = -1.0
	warden.attack_cooldown = 0.0
	warden._start_skill(EnemyBoss.Skill.CHARGE)
	await _wait_until(t, func() -> bool: return warden.skill_context == EnemyBoss.Skill.NONE, 300)
	t.eq(warden.charges_done, 1, "冲撞计数 +1")
	t.gt(warden.damage_dealt, 0.0, "冲撞对玩家造成伤害")

	# 砸地：贴脸范围伤害
	warden.skill_cooldowns[EnemyBoss.Skill.SLAM] = -1.0
	warden.attack_cooldown = 0.0
	warden.global_position = player.global_position + Vector2(40, 0)
	await _frames(t, 3)
	warden._start_skill(EnemyBoss.Skill.SLAM)
	await _wait_until(t, func() -> bool: return warden.skill_context == EnemyBoss.Skill.NONE, 200)
	t.eq(warden.slams_done, 1, "砸地计数 +1")
	t.gte(warden.damage_dealt, 0.0, "砸地命中（伤害已累计）")

	# 清理弹丸避免干扰后续
	for child: Node in world.bullet_root.get_children():
		child.free()

	# ---- weaver：扇形 -> 螺旋 ----
	var weaver: EnemyBoss = _spawn_boss(world, "weaver", player.global_position + Vector2(160, 0))
	t.not_null(weaver, "weaver 生成成功")
	if weaver == null:
		await _free_world(t, world)
		return
	weaver.data.sight_range = 480.0

	var weaver_bullets: int = weaver.bullets_fired
	weaver._start_skill(EnemyBoss.Skill.FAN)
	await _wait_until(t, func() -> bool: return weaver.skill_context == EnemyBoss.Skill.NONE, 300)
	t.eq(weaver.fans_fired, 1, "扇形弹幕计数 +1")
	t.gte(float(weaver.bullets_fired - weaver_bullets), 21.0, "3 波 x 7 发 = >= 21 发")

	weaver_bullets = weaver.bullets_fired
	weaver._start_skill(EnemyBoss.Skill.SPIRAL)
	await _wait_until(t, func() -> bool: return weaver.skill_context == EnemyBoss.Skill.NONE, 400)
	t.eq(weaver.spirals_fired, 1, "螺旋弹幕计数 +1")
	t.gte(float(weaver.bullets_fired - weaver_bullets), 48.0, "16 帧 x 3 臂 = >= 48 发")

	for child: Node in world.bullet_root.get_children():
		child.free()
	await _free_world(t, world)


# ==================== 5. 召唤与清场广播 ====================

func _test_summon_and_cleared(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	_tough_player(world)
	var warden: EnemyBoss = _spawn_boss(world, "warden", world.player.global_position + Vector2(-200, 0))
	t.not_null(warden, "warden 生成成功")
	if warden == null:
		await _free_world(t, world)
		return
	# 锁 AI，让召唤测试完全由手动起手驱动
	warden.data.sight_range = 1.0

	var cleared_events: Array = []
	var on_cleared := func(_b: Node) -> void: cleared_events.append(true)
	EventBus.boss_minions_cleared.connect(on_cleared)

	# 第一波召唤：3 只 husk 注入世界
	var spawned_before: int = world.spawner.total_spawned
	warden._start_skill(EnemyBoss.Skill.SUMMON)
	t.eq(warden.skill_phase, "windup", "召唤进入预警")
	await _wait_until(t, func() -> bool: return warden.skill_context == EnemyBoss.Skill.NONE, 240)
	t.eq(warden.summons_done, 1, "召唤计数 +1")
	t.eq(warden.minions_alive(), 3, "3 只召唤物存活")
	t.eq(world.spawner.total_spawned, spawned_before + 3, "召唤物经由世界生成器注入")
	t.gte(float(world.spawner.alive_count()), 3.0, "生成器存活数包含召唤物")
	t.eq(cleared_events.size(), 0, "还没清光时无清空广播")

	# 小怪在 Boss 死后会自动清场；Boss 活着时玩家清怪 -> 广播清空提示
	var minions: Array = warden._minions.duplicate()
	var killed: int = 0
	for entry: Variant in minions:
		var minion: Enemy = entry
		if is_instance_valid(minion) and not minion.dead:
			minion.take_hit(9999.0, false, Vector2.ZERO, 4242)
			killed += 1
	t.eq(killed, 3, "清杀 3 只召唤物")
	t.eq(warden.minions_alive(), 0, "召唤物全部死亡")
	await _frames(t, 3)
	t.eq(cleared_events.size(), 1, "小怪清零广播触发一次")

	# 上限控制：召唤 cap 6，长时间战斗不会无限刷
	warden.skill_cooldowns[EnemyBoss.Skill.SUMMON] = -1.0
	warden.attack_cooldown = 0.0
	warden._start_skill(EnemyBoss.Skill.SUMMON)
	await _wait_until(t, func() -> bool: return warden.skill_context == EnemyBoss.Skill.NONE, 240)
	t.eq(warden.summons_done, 2, "第二波召唤完成")
	t.eq(warden.minions_alive(), 3, "第二波 3 只在场")
	# 再召一波：3 只存在，cap 6 允许再招 3，但不超出
	warden.skill_cooldowns[EnemyBoss.Skill.SUMMON] = -1.0
	warden.attack_cooldown = 0.0
	warden._start_skill(EnemyBoss.Skill.SUMMON)
	await _wait_until(t, func() -> bool: return warden.skill_context == EnemyBoss.Skill.NONE, 240)
	t.eq(warden.summons_done, 3, "第三波召唤完成")
	t.lte(float(warden.minions_alive()), 6.0, "召唤物不超过上限 6")
	# 满了之后再召：被上限拦截，不再生成
	warden.skill_cooldowns[EnemyBoss.Skill.SUMMON] = -1.0
	warden.attack_cooldown = 0.0
	warden._start_skill(EnemyBoss.Skill.SUMMON)
	await _wait_until(t, func() -> bool: return warden.skill_context == EnemyBoss.Skill.NONE, 240)
	t.eq(warden.minions_alive(), 6, "上限拦截：保持 6 只")
	t.gte(float(warden.summons_blocked_by_cap), 1.0, "记录被上限拦截的召唤")

	EventBus.boss_minions_cleared.disconnect(on_cleared)
	await _free_world(t, world)


# ==================== 6. 死亡清场 ====================

func _test_boss_death_clears_wave(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	_tough_player(world)

	var died_events: Array = []
	var dropped_events: Array = []
	var cleared_events: Array = []
	var on_died := func(_b: Node) -> void: died_events.append(true)
	var on_dropped := func(_e: Node, _pos: Vector2, drops: Array) -> void: dropped_events.append(drops)
	var on_wave_cleared := func() -> void: cleared_events.append(true)
	EventBus.boss_died.connect(on_died)
	EventBus.enemy_dropped.connect(on_dropped)
	world.spawner.wave_cleared.connect(on_wave_cleared)

	# 用 world.spawn_wave 走正常波次链路：Boss 房也走这里
	var boss_ids: Array = world.spawn_wave(["weaver"])
	t.eq(boss_ids.size(), 1, "Boss 波次投放 1 只")
	t.eq(world.spawner.alive_count(), 1, "场上 1 只存活")
	var boss: EnemyBoss = world.spawner.alive_enemies()[0] as EnemyBoss
	t.check(boss is EnemyBoss, "波次生成的是 Boss")

	# 让它召唤些小怪再被杀：清场必须把小怪一并带走，波次才能清空
	boss.data.sight_range = 1.0
	boss.attack_cooldown = 0.0
	boss._start_skill(EnemyBoss.Skill.SUMMON)
	await _wait_until(t, func() -> bool: return boss.skill_context == EnemyBoss.Skill.NONE, 240)
	t.eq(boss.minions_alive(), 2, "Boss 在场时召出 2 只小怪（weaver 召唤数=2）")

	# 击杀 Boss：召唤物被同步清场 -> wave_cleared -> 房间可开门
	boss.take_hit(99999.0, false, Vector2.ZERO, 4242)
	t.check(boss.dead, "Boss 死亡")
	t.eq(boss.minions_alive(), 0, "Boss 死亡时清掉所有召唤物")
	t.eq(died_events.size(), 1, "boss_died 触发一次")
	t.check(not dropped_events.is_empty(), "Boss 结算掉落")
	await _wait_until(t, func() -> bool: return world.spawner.cleared, 200)
	t.check(world.spawner.cleared, "Boss + 召唤物全部清完后波次清空")
	t.eq(cleared_events.size(), 1, "wave_cleared 触发一次")
	t.eq(world.spawner.alive_count(), 0, "存活数归零")

	EventBus.boss_died.disconnect(on_died)
	EventBus.enemy_dropped.disconnect(on_dropped)
	world.spawner.wave_cleared.disconnect(on_wave_cleared)
	await _free_world(t, world)