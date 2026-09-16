extends TestSuite
## test_player —— M3 玩家与战斗核心验收（无头）。
##
## 覆盖四块：
##   1. 武器数据：手枪 / 霰弹枪 / 激光枪的伤害、射速、弹速、散射、耗能、击退、弹道类型；
##   2. 世界装配：GameWorld 能搭出房间 + 玩家 + 相机 + HUD + 靶子，弹道层已注入；
##   3. 属性系统：生命 / 护盾 / 能量 / 移速 / 暴击来自 GameState.stats，移动与冲刺生效；
##   4. 战斗链路：投射命中、霰弹多发、激光即时命中、技能范围伤害、受击 -> 死亡 -> 结算。
##
## run() 是协程：需要 await 物理帧让子弹真正飞到靶子上。

const G := preload("res://scripts/core/game_const.gd")

## 靶子在试验场里的索引（GameWorld._spawn_dummies 的第 2 个正好在玩家正上方）
const UP_DUMMY_INDEX: int = 1


func suite_name() -> String:
	return "玩家与战斗核心 (M3)"


func run(t: Node) -> void:
	_test_weapon_table(t)
	await _test_world_assembly(t)
	await _test_attributes_and_movement(t)
	await _test_projectile_hit(t)
	await _test_shotgun_pellets(t)
	await _test_laser_hitscan(t)
	await _test_dash(t)
	await _test_skill_area_damage(t)
	await _test_hurt_death_and_result(t)


# ==================== 1. 武器数据 ====================

func _test_weapon_table(t: Node) -> void:
	var pistol: WeaponData = WeaponDB.create("pistol")
	var shotgun: WeaponData = WeaponDB.create("shotgun")
	var laser: WeaponData = WeaponDB.create("laser")

	t.not_null(pistol, "WeaponDB 能创建 pistol")
	t.not_null(shotgun, "WeaponDB 能创建 shotgun")
	t.not_null(laser, "WeaponDB 能创建 laser")
	if pistol == null or shotgun == null or laser == null:
		return

	# --- 手枪：低耗能、中射速、单发投射 ---
	t.eq(pistol.kind, WeaponData.Kind.PROJECTILE, "手枪弹道类型为 PROJECTILE")
	t.eq(pistol.damage, 13.0, "手枪基础伤害 13")
	t.eq(pistol.pellets, 1, "手枪每次 1 发弹丸")
	t.eq(pistol.bullet_speed, 430.0, "手枪弹速 430")
	t.eq(pistol.energy_cost, 2.0, "手枪耗能 2")
	t.eq(pistol.knockback, 90.0, "手枪击退 90")
	t.near(pistol.fire_interval(), 1.0 / 4.4, 0.001, "手枪射击间隔 = 1/4.4 秒")
	t.check(pistol.auto_fire, "手枪支持按住连发")

	# --- 霰弹枪：多发、大散射、高击退、慢射速、非连发 ---
	t.eq(shotgun.pellets, 5, "霰弹枪每次 5 枚弹丸")
	t.eq(shotgun.spread_deg, 15.0, "霰弹枪散射 15 度")
	t.eq(shotgun.energy_cost, 8.0, "霰弹枪耗能 8")
	t.gt(shotgun.knockback, pistol.knockback, "霰弹枪击退强于手枪")
	t.gt(shotgun.fire_interval(), pistol.fire_interval(), "霰弹枪射速慢于手枪")
	t.check(not shotgun.auto_fire, "霰弹枪为半自动（需逐次点击）")

	# --- 激光枪：即时命中、贯穿、射程、耗能最高 ---
	t.eq(laser.kind, WeaponData.Kind.HITSCAN, "激光枪弹道类型为 HITSCAN")
	t.eq(laser.beam_range, 430.0, "激光射程 430")
	t.eq(laser.pierce, 99, "激光可贯穿多个目标")
	t.gt(laser.damage, pistol.damage, "激光单发伤害高于手枪")
	t.gt(laser.energy_cost, shotgun.energy_cost, "激光耗能高于霰弹枪")

	# --- 三把武器手感必须互不相同 ---
	t.neq(pistol.damage, shotgun.damage, "手枪与霰弹枪伤害不同")
	t.neq(pistol.fire_rate, laser.fire_rate, "手枪与激光射速不同")
	t.eq(WeaponDB.core_three().size(), 3, "core_three() 返回三把武器")
	var ids: Array = []
	for weapon: Variant in WeaponDB.core_three():
		ids.append((weapon as WeaponData).id)
	t.eq(ids, ["pistol", "shotgun", "laser"], "初始三把武器顺序为 手枪/霰弹枪/激光枪")


# ==================== 2. 世界装配 ====================

func _make_world(t: Node) -> GameWorld:
	GameState.new_run(20260914)
	var world := GameWorld.new()
	world.name = "TestGameWorld"
	# M4：演示波次由 test_enemy 专门验证；玩家断言不能被真实敌人干扰（敌弹会污染 bullet_count）
	world.auto_demo_wave = false
	t.add_child(world)
	return world


func _free_world(t: Node, world: GameWorld) -> void:
	if world == null:
		return
	world.clear_entities(false)
	world.queue_free()
	await t.get_tree().process_frame


func _test_world_assembly(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	t.not_null(world, "GameWorld 实例化成功")
	t.not_null(world.player, "世界内已生成玩家")
	t.not_null(world.camera, "世界内已生成相机")
	t.not_null(world.hud, "世界内已生成 HUD")
	t.eq(world.dummies.size(), 3, "试验场生成 3 个打靶水晶")

	if world.player != null:
		var player: Player = world.player
		t.eq(player.weapons.size(), 3, "玩家持有 3 个武器栏位")
		t.eq(player.current_weapon().id, "pistol", "当前武器为手枪")
		t.eq(player.bullet_layer, world.bullet_root, "弹道层已注入玩家")
		t.eq(player.fx_layer, world.fx_root, "特效层已注入玩家")
		t.check(player.invulnerable, "出生保护处于无敌状态")
		t.gt(player.invulnerable_timer, 0.0, "出生保护剩余时间 > 0")
		t.eq(player.collision_layer, G.LAYER_PLAYER, "玩家碰撞层为 player")
		t.check(G.has_layer(player.collision_mask, G.LAYER_WORLD), "玩家碰撞掩码包含墙体")

	if world.hud != null:
		t.eq(world.hud.player, world.player, "HUD 已绑定玩家")
		t.eq(world.hud.world, world, "HUD 已绑定世界")
		t.check(not world.hud.is_paused, "开局未处于暂停状态")
		# M8：暂停面板含内嵌设置子面板（F2 打开 / Esc 关闭）
		t.not_null(world.hud.get("_pause_settings"), "暂停面板已构建设置子面板")
		if world.hud.get("_pause_settings") != null:
			t.check(not bool(world.hud.get("_pause_settings").visible), "设置子面板初始隐藏")

	t.check(world.interior_rect.size.x > 0.0 and world.interior_rect.size.y > 0.0,
			"房间内部区域尺寸有效")
	t.check(world.camera.has_bounds, "相机已设置活动边界")
	t.gt(world.alive_enemy_count(), 0.0, "试验场内存在可攻击目标")

	await _free_world(t, world)


# ==================== 3. 属性与移动 ====================

func _test_attributes_and_movement(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = world.player
	t.not_null(player, "玩家存在（属性测试）")
	if player == null:
		await _free_world(t, world)
		return

	# 属性单一事实来源：玩家 stats 与 GameState.stats 是同一份字典
	t.eq(player.stats, GameState.stats, "玩家属性直接引用 GameState.stats")
	t.eq(player.max_health(), 100.0, "生命上限 100")
	t.eq(player.health(), 100.0, "初始生命满值")
	t.eq(player.max_shield(), 50.0, "护盾上限 50")
	t.eq(player.shield(), 50.0, "初始护盾满值")
	t.eq(player.max_energy(), 100.0, "能量上限 100")
	t.eq(player.energy(), 100.0, "初始能量满值")
	t.eq(player.stat("move_speed"), 205.0, "移速 205 像素/秒")
	t.eq(player.stat("crit_chance"), 0.1, "基础暴击率 10%")
	t.eq(player.stat("crit_multiplier"), 1.8, "暴击伤害 1.8 倍")
	t.eq(GameState.gold, G.START_GOLD, "开局金币为 0")

	# WASD：按下右键动作后玩家应真的向右位移
	var start_position: Vector2 = player.global_position
	Input.action_press("move_right")
	for i: int in range(18):
		await t.get_tree().physics_frame
	Input.action_release("move_right")
	t.gt(player.global_position.x - start_position.x, 4.0, "按下 D 键后玩家向右移动")
	t.near(player.global_position.y, start_position.y, 1.0, "横向移动不会带出纵向漂移")

	# 能量持续回复：清空后应自动回升
	player.stats["energy"] = 40.0
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	t.gt(player.energy(), 40.0, "能量随时间自动回复")

	# 护盾延迟回复：受击后先等待 shield_regen_delay，再逐步回盾
	player.stats["shield"] = 10.0
	player.shield_regen_timer = 0.0
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	t.gt(player.shield(), 10.0, "护盾在延迟结束后自动回复")

	await _free_world(t, world)


# ==================== 4. 战斗链路 ====================

## 把玩家摆到试验场中心偏下、朝正上方的靶子射击的标准姿势
func _aim_at_up_dummy(world: GameWorld) -> TrainingDummy:
	var player: Player = world.player
	player.clear_invulnerable()
	player.set_aim_direction(Vector2.UP)
	player.fire_cooldown = 0.0
	player.stats["energy"] = player.max_energy()
	var dummy: TrainingDummy = world.dummy_at(UP_DUMMY_INDEX)
	if dummy != null:
		dummy.reset(90.0)
	return dummy


func _clear_bullets(world: GameWorld) -> void:
	for child: Node in world.bullet_root.get_children():
		child.free()


func _test_projectile_hit(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = world.player
	var dummy: TrainingDummy = _aim_at_up_dummy(world)
	t.not_null(dummy, "正上方靶子存在")
	if dummy == null:
		await _free_world(t, world)
		return

	var before: int = player.shots_fired
	t.check(player.try_fire(), "手枪开火成功")
	t.eq(player.shots_fired, before + 1, "开火计数 +1")
	t.eq(player.last_shot_pellets, 1, "手枪本次发射 1 发")
	t.gte(player.last_shot_damage, 11.7, "手枪伤害不低于 13*(1-10%)")
	t.lte(player.last_shot_damage, 25.8, "手枪伤害不超过 13*(1+10%)*1.8（含暴击上限）")
	t.near(player.energy(), 98.0, 0.6, "手枪开火扣除 2 点能量")
	t.eq(player.last_fire_blocked_reason, "", "开火未被任何条件阻挡")
	t.eq(world.bullet_count(), 1, "弹道层中出现 1 发子弹")

	# 等子弹飞到靶子（距离约 160px，弹速 430px/s，约需 22 帧）
	var frames: int = 0
	while dummy.hit_count == 0 and frames < 80:
		await t.get_tree().physics_frame
		frames += 1
	t.gte(dummy.hit_count, 1.0, "手枪子弹命中靶子")
	t.gt(dummy.total_damage, 0.0, "靶子累计受到伤害")
	t.eq(dummy.last_source_id, player.get_instance_id(), "伤害来源标记为玩家")
	t.gt(dummy.last_knockback.length(), 0.0, "命中带击退向量")
	t.gt(world.fx_root.get_child_count(), 0.0, "命中后生成特效/飘字节点")

	# 冷却期内不能连开第二枪（手枪 1/4.4 秒）
	player.fire_cooldown = 0.2
	t.check(not player.try_fire(), "冷却未结束时无法开火")
	t.eq(player.last_fire_blocked_reason, "cooldown", "阻挡原因为 cooldown")

	# 能量不足时无法开火
	player.fire_cooldown = 0.0
	player.stats["energy"] = 0.0
	t.check(not player.try_fire(), "能量为 0 时无法开火")
	t.eq(player.last_fire_blocked_reason, "energy", "阻挡原因为 energy")

	_clear_bullets(world)
	await _free_world(t, world)


func _test_shotgun_pellets(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = world.player
	var dummy: TrainingDummy = _aim_at_up_dummy(world)
	t.check(player.set_weapon_slot(1), "可切换到 2 号武器栏（霰弹枪）")
	t.eq(player.current_weapon().id, "shotgun", "当前武器为霰弹枪")
	t.eq(GameState.weapon_index, 1, "武器栏位同步到 GameState")

	# 贴近靶子（60px）再开火：15 度散射下应有多枚弹丸落在靶身上
	# （远距离 160px 时只有中间弹丸能命中，这是散射的真实表现，不是缺陷）
	dummy.reset(900.0)
	player.global_position = dummy.global_position + Vector2(0, 60)
	player.set_aim_direction(Vector2.UP)
	player.fire_cooldown = 0.0
	player.stats["energy"] = 100.0
	t.check(player.try_fire(), "霰弹枪开火成功")
	t.eq(player.last_shot_pellets, 5, "霰弹枪一次喷出 5 枚弹丸")
	t.eq(world.bullet_count(), 5, "弹道层中出现 5 发弹丸")
	t.near(player.energy(), 92.0, 0.6, "霰弹枪扣除 8 点能量")
	t.gt(player.fire_cooldown, 0.5, "霰弹枪开火后进入较长冷却")

	# 5 枚弹丸的飞行方向必须互不相同（散射真实生效，而非重叠成一发）
	var angles: Array = []
	for bullet_node: Node in world.bullet_root.get_children():
		var bullet: Bullet = bullet_node as Bullet
		if bullet != null and not angles.has(bullet.fly_velocity.angle()):
			angles.append(bullet.fly_velocity.angle())
	t.eq(angles.size(), 5, "5 枚弹丸各自有不同的飞行方向")

	var frames: int = 0
	while dummy.hit_count < 2 and frames < 60:
		await t.get_tree().physics_frame
		frames += 1
	t.gte(dummy.hit_count, 2.0, "近距离霰弹枪至少 2 枚弹丸命中靶子")
	t.gte(dummy.total_damage, 18.0, "多枚弹丸累计伤害（单枚基础 10）")

	_clear_bullets(world)
	await _free_world(t, world)


func _test_laser_hitscan(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = world.player
	var dummy: TrainingDummy = _aim_at_up_dummy(world)
	t.check(player.set_weapon_slot(2), "可切换到 3 号武器栏（激光枪）")
	t.eq(player.current_weapon().id, "laser", "当前武器为激光枪")

	player.fire_cooldown = 0.0
	player.stats["energy"] = 100.0
	t.check(player.try_fire(), "激光枪开火成功")
	t.eq(world.bullet_count(), 0, "激光为即时命中，不产生飞行弹体")
	t.gte(dummy.hit_count, 1.0, "激光开火当帧即命中靶子")
	t.gte(dummy.total_damage, 24.3, "激光伤害不低于 27*(1-10%)")
	t.near(player.energy(), 87.0, 0.6, "激光枪扣除 13 点能量")

	await _free_world(t, world)


func _test_dash(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = world.player
	player.clear_invulnerable()
	player.dash_timer = 0.0
	player.dash_cooldown_timer = 0.0

	var start_position: Vector2 = player.global_position
	t.check(player.dash_ready(), "冷却结束时冲刺可用")
	t.check(player.try_dash(), "冲刺触发成功")
	t.eq(player.dashes_used, 1, "冲刺计数 +1")
	t.check(player.invulnerable, "冲刺期间处于无敌帧")
	t.near(player.dash_cooldown_timer, 0.85, 0.02, "冲刺冷却 0.85 秒")
	t.check(not player.dash_ready(), "冷却中冲刺不可用")
	t.check(not player.try_dash(), "冷却中无法再次冲刺")

	for i: int in range(6):
		await t.get_tree().physics_frame
	t.gt(player.global_position.distance_to(start_position), 8.0, "冲刺产生明显位移")

	player.dash_timer = 0.0
	player.dash_cooldown_timer = 0.0
	t.check(player.dash_ready(), "计时归零后冲刺恢复可用")

	await _free_world(t, world)


func _test_skill_area_damage(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = world.player
	var dummy: TrainingDummy = world.dummy_at(0)
	t.not_null(dummy, "技能测试靶子存在")
	if dummy == null:
		await _free_world(t, world)
		return

	# 把靶子挪到玩家身侧（技能半径 115），等一帧让物理空间同步新位置
	dummy.reset(200.0)
	dummy.global_position = player.global_position + Vector2(36, 0)
	await t.get_tree().physics_frame

	player.clear_invulnerable()
	player.skill_cooldown_timer = 0.0
	player.stats["energy"] = 100.0
	t.check(player.try_skill(), "技能释放成功")
	t.eq(player.skills_used, 1, "技能计数 +1")
	t.near(player.energy(), 80.0, 0.6, "技能扣除 20 点能量")
	t.near(player.skill_cooldown_timer, 4.8, 0.05, "技能冷却 4.8 秒")
	t.gte(dummy.hit_count, 1.0, "冲击波命中范围内的靶子")
	t.gte(dummy.total_damage, 22.0, "冲击波伤害不低于 44*50%（边缘衰减下限）")
	t.gt(dummy.last_knockback.length(), 0.0, "冲击波带击退")

	# 能量不足时技能被拒绝
	player.stats["energy"] = 5.0
	player.skill_cooldown_timer = 0.0
	t.check(not player.try_skill(), "能量不足时无法释放技能")
	t.check(not player.skill_ready(), "技能进入短冷却防止连点")

	await _free_world(t, world)


func _test_hurt_death_and_result(t: Node) -> void:
	var world: GameWorld = _make_world(t)
	var player: Player = world.player

	var died_calls: Array = []
	var on_died := func() -> void: died_calls.append(true)
	EventBus.player_died.connect(on_died)

	# 护盾优先吸收：20 点伤害全部落在 50 点护盾上
	player.clear_invulnerable()
	player.stats["shield"] = 50.0
	player.stats["health"] = 100.0
	player.take_hit(20.0, false, Vector2(60, 0), 0)
	t.near(player.shield(), 30.0, 0.01, "护盾吸收 20 点伤害后剩 30")
	t.eq(player.health(), 100.0, "护盾未破时生命不扣")
	t.check(player.invulnerable, "受击后获得短暂无敌帧")
	t.near(player.shield_regen_timer, 4.0, 0.05, "受击重置护盾回复延迟")

	# 无敌帧内不再受伤
	player.take_hit(50.0, false, Vector2.ZERO, 0)
	t.near(player.shield(), 30.0, 0.01, "无敌帧内免疫后续伤害")

	# 护盾打穿后扣生命，致死触发 player_died 与世界结算计时
	player.clear_invulnerable()
	player.take_hit(400.0, false, Vector2.ZERO, 0)
	t.eq(player.health(), 0.0, "超额伤害把生命压到 0")
	t.check(player.dead, "玩家进入死亡状态")
	t.eq(died_calls.size(), 1, "player_died 信号触发一次")
	t.gt(world._death_timer, 0.0, "世界开始死亡结算倒计时")
	t.check(player.collision_layer == 0, "死亡后关闭碰撞层")

	# 倒计时结束 -> end_run(false)
	world._death_timer = 0.05
	var frames: int = 0
	while GameState.run_active and frames < 60:
		await t.get_tree().process_frame
		frames += 1
	t.check(not GameState.run_active, "死亡结算后本局标记为结束")
	t.check(world.finished, "世界标记为已完成结算")

	if EventBus.player_died.is_connected(on_died):
		EventBus.player_died.disconnect(on_died)
	await _free_world(t, world)
