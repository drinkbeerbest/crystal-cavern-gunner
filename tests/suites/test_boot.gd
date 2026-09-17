extends TestSuite
## test_boot —— 工程骨架自检套件（M1 验收）。
##
## 覆盖：Autoload、输入映射、物理层常量、玩家默认属性、地牢常量、
## 权重随机、全局状态机（金币/天赋/存档）、设置落盘、主场景可实例化。

const G := preload("res://scripts/core/game_const.gd")


func suite_name() -> String:
	return "boot"


func run(t: Node) -> void:
	_test_project_settings(t)
	_test_autoloads(t)
	_test_input_map(t)
	_test_physics_layers(t)
	_test_player_defaults(t)
	_test_dungeon_constants(t)
	_test_weighted_pick(t)
	_test_gold(t)
	_test_talents(t)
	_test_floors(t)
	_test_account(t)
	_test_settings(t)
	_test_run_save(t)
	_test_main_scene(t)
	await _test_pause_blocks_damage(t)


# ---------- 工程配置 ----------

func _test_project_settings(t: Node) -> void:
	t.eq(str(ProjectSettings.get_setting("application/run/main_scene", "")), "res://scenes/main.tscn", "主场景配置正确")
	t.eq(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)), 1280, "视口宽 1280")
	t.eq(int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)), 720, "视口高 720")
	t.check(ResourceLoader.exists("res://assets/icon.png"), "图标存在")
	t.eq(str(ProjectSettings.get_setting("application/config/icon", "")), "res://assets/icon.png", "工程图标指向素材管线产出的 icon.png")
	t.eq(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", -1)), 0, "像素风最近邻过滤")


# ---------- Autoload ----------

func _test_autoloads(t: Node) -> void:
	for autoload_name: String in ["InputCfg", "EventBus", "SaveMgr", "GameState", "AudioMgr"]:
		t.not_null(t.get_node_or_null("/root/" + autoload_name), "Autoload 已加载: " + autoload_name)


# ---------- 输入映射 ----------

func _test_input_map(t: Node) -> void:
	var input_cfg: Node = t.get_node("/root/InputCfg")
	var missing: Array[String] = []
	for action: String in input_cfg.ALL_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(action)
	t.check(missing.is_empty(), "全部输入动作已注册" + ("" if missing.is_empty() else "（缺失: %s）" % ", ".join(missing)))

	# 关键动作必须有事件且按键正确
	t.check(InputMap.action_get_events("move_up").size() >= 2, "上移绑定 W + ↑")
	t.check(InputMap.action_get_events("shoot").size() == 1, "射击绑定 1 个鼠标键")
	var shoot_ev: InputEvent = InputMap.action_get_events("shoot")[0]
	t.check(shoot_ev is InputEventMouseButton and (shoot_ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT, "射击 = 鼠标左键")
	t.check(_has_keycode("dash", KEY_SHIFT), "冲刺 = Shift")
	t.check(_has_keycode("skill", KEY_SPACE), "技能 = 空格")
	t.check(_has_keycode("interact", KEY_E), "交互 = E")
	t.check(_has_keycode("pause", KEY_ESCAPE), "暂停 = Esc")
	t.check(_has_keycode("move_up", KEY_W) and _has_keycode("move_down", KEY_S)
		and _has_keycode("move_left", KEY_A) and _has_keycode("move_right", KEY_D), "WASD 移动绑定齐全")
	t.neq(str(input_cfg.action_label("move_up")), "?", "action_label 能给出可读键名")


func _has_keycode(action: String, keycode: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == keycode:
			return true
	return false


# ---------- 物理层 ----------

func _test_physics_layers(t: Node) -> void:
	var layers: Array[int] = [G.LAYER_WORLD, G.LAYER_PLAYER, G.LAYER_ENEMY,
		G.LAYER_PLAYER_BULLET, G.LAYER_ENEMY_BULLET, G.LAYER_PICKUP, G.LAYER_INTERACT]
	var seen: Dictionary = {}
	for layer: int in layers:
		t.check(layer > 0 and (layer & (layer - 1)) == 0, "层 %d 为 2 的幂" % layer)
		seen[layer] = true
	t.eq(seen.size(), layers.size(), "7 个物理层互不重复")

	t.eq(G.MASK_PLAYER, G.LAYER_WORLD | G.LAYER_ENEMY, "玩家掩码 = 墙 + 敌人")
	t.eq(G.MASK_PLAYER_BULLET, G.LAYER_WORLD | G.LAYER_ENEMY, "玩家子弹掩码 = 墙 + 敌人")
	t.eq(G.MASK_ENEMY_BULLET, G.LAYER_WORLD | G.LAYER_PLAYER, "敌人子弹掩码 = 墙 + 玩家")
	t.check(G.has_layer(G.MASK_PLAYER_BULLET, G.LAYER_ENEMY), "玩家子弹可命中敌人")
	t.check(not G.has_layer(G.MASK_PLAYER_BULLET, G.LAYER_PLAYER), "玩家子弹不会命中自己")
	t.check(not G.has_layer(G.MASK_ENEMY_BULLET, G.LAYER_ENEMY), "敌人子弹不会命中敌人")
	t.eq(G.MASK_PICKUP, G.LAYER_PLAYER, "拾取物只与玩家交互")
	t.check(G.LAYER_INTERACT <= 64, "交互层在 2D 物理 64 层上限内")


# ---------- 玩家默认属性 ----------

func _test_player_defaults(t: Node) -> void:
	var required: Array[String] = ["max_health", "health", "max_shield", "shield", "max_energy", "energy",
		"energy_regen", "move_speed", "crit_chance", "crit_multiplier", "dash_speed", "dash_cooldown",
		"pickup_radius", "damage_multiplier", "attack_speed_multiplier", "armor", "luck"]
	var missing: Array[String] = []
	for key: String in required:
		if not G.DEFAULT_PLAYER_STATS.has(key):
			missing.append(key)
	t.check(missing.is_empty(), "默认属性覆盖生命/护盾/能量/移速/暴击等" + ("" if missing.is_empty() else "（缺 %s）" % ", ".join(missing)))
	t.gte(float(G.DEFAULT_PLAYER_STATS["max_health"]), 1.0, "最大生命 > 0")
	t.lte(float(G.DEFAULT_PLAYER_STATS["health"]), float(G.DEFAULT_PLAYER_STATS["max_health"]), "初始生命不超过上限")
	t.lte(float(G.DEFAULT_PLAYER_STATS["shield"]), float(G.DEFAULT_PLAYER_STATS["max_shield"]), "初始护盾不超过上限")
	t.check(float(G.DEFAULT_PLAYER_STATS["crit_chance"]) >= 0.0 and float(G.DEFAULT_PLAYER_STATS["crit_chance"]) <= 1.0, "暴击率在 0~1")
	t.gt(float(G.DEFAULT_PLAYER_STATS["crit_multiplier"]), 1.0, "暴击倍率 > 1")
	t.gt(float(G.DEFAULT_PLAYER_STATS["dash_speed"]), float(G.DEFAULT_PLAYER_STATS["move_speed"]), "冲刺速度快于移动")


# ---------- 地牢常量 ----------

func _test_dungeon_constants(t: Node) -> void:
	t.eq(G.MIN_ROOMS_PER_FLOOR, 5, "每层最少 5 个房间")
	t.eq(G.MAX_ROOMS_PER_FLOOR, 10, "每层最多 10 个房间")
	t.gte(float(G.TOTAL_FLOORS), 1.0, "至少 1 层")
	t.check(G.ROOM_SIZES.size() >= 3, "至少 3 种房间尺寸")
	for room_size: Vector2i in G.ROOM_SIZES:
		t.check(room_size.x % 2 == 1 and room_size.y % 2 == 1, "房间尺寸为奇数便于居中开门 %s" % str(room_size))
		t.gte(float(room_size.x), 15.0, "房间宽度足够 %s" % str(room_size))
	var biggest: Vector2i = G.START_ROOM_SIZE
	for room_size: Vector2i in G.ROOM_SIZES:
		if room_size.x > biggest.x:
			biggest = room_size
	t.gt(float(G.BOSS_ROOM_SIZE.x), float(biggest.x), "Boss 房大于普通房")
	t.gt(float(G.TILE_SIZE), 0.0, "瓦片尺寸 > 0")


# ---------- 权重随机 ----------

func _test_weighted_pick(t: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var counts: Dictionary = {}
	for i: int in range(3000):
		var key: Variant = G.weighted_pick({"a": 1.0, "b": 3.0}, rng)
		counts[key] = int(counts.get(key, 0)) + 1
	t.check(counts.has("a") and counts.has("b"), "权重抽取覆盖全部候选")
	t.gt(float(int(counts.get("b", 0))), float(int(counts.get("a", 0))), "高权重项被抽中更多")
	t.eq(G.weighted_pick({}, rng), null, "空权重表返回 null")
	t.eq(G.weighted_pick({"only": 1.0}, rng), "only", "单项权重表返回该项")


# ---------- 全局状态：金币 ----------

func _test_gold(t: Node) -> void:
	GameState.new_run(20260914)
	t.eq(GameState.gold, G.START_GOLD, "新局金币从起始值开始")
	GameState.add_gold(120)
	t.eq(GameState.gold, 120, "加金币生效")
	GameState.add_gold(-200)
	t.eq(GameState.gold, 0, "金币不会为负")
	GameState.add_gold(50)
	t.check(not GameState.try_spend_gold(80), "余额不足时消费失败")
	t.eq(GameState.gold, 50, "消费失败不扣钱")
	t.check(GameState.try_spend_gold(30), "余额充足时消费成功")
	t.eq(GameState.gold, 20, "消费后余额正确")


# ---------- 全局状态：临时天赋 ----------

func _test_talents(t: Node) -> void:
	GameState.new_run(777)
	var base_speed: float = float(G.DEFAULT_PLAYER_STATS["move_speed"])
	t.near(GameState.stat_value("move_speed"), base_speed, 0.001, "无天赋时移速为默认值")

	GameState.add_talent({"id": "swift", "display_name": "疾风", "duration": 0.3, "modifiers": {"move_speed": 45.0}})
	t.eq(GameState.talents.size(), 1, "天赋入列")
	t.near(GameState.stat_value("move_speed"), base_speed + 45.0, 0.001, "天赋提升移速")

	GameState.add_talent({"id": "swift", "display_name": "疾风", "duration": 0.3, "modifiers": {"move_speed": 45.0}})
	t.eq(GameState.talents.size(), 1, "同 id 天赋不重复入列")

	GameState.add_talent({"id": "killer", "display_name": "杀意", "duration": 1.0, "modifiers": {"crit_chance": 0.2}})
	t.near(GameState.stat_value("crit_chance"), float(G.DEFAULT_PLAYER_STATS["crit_chance"]) + 0.2, 0.0001, "多个天赋同时生效")

	GameState.tick_talents(0.35)
	t.eq(GameState.talents.size(), 1, "到期天赋被移除")
	t.near(GameState.stat_value("move_speed"), base_speed, 0.001, "到期后加成还原")

	GameState.clear_talents()
	t.eq(GameState.talents.size(), 0, "clear_talents 清空")
	t.near(GameState.stat_value("crit_chance"), float(G.DEFAULT_PLAYER_STATS["crit_chance"]), 0.0001, "清空后属性还原")


# ---------- 全局状态：楼层 ----------

func _test_floors(t: Node) -> void:
	GameState.new_run(31337)
	t.eq(GameState.floor_index, 1, "新局从第 1 层开始")
	GameState.stats["health"] = 10.0
	t.check(GameState.advance_floor(), "可以进入下一层")
	t.eq(GameState.floor_index, 2, "层数 +1")
	t.gt(GameState.stat_value("health"), 10.0, "换层回血")
	for i: int in range(G.TOTAL_FLOORS + 2):
		GameState.advance_floor()
	t.eq(GameState.floor_index, G.TOTAL_FLOORS, "层数不超过总层数")


# ---------- 账户金币 / 武器图鉴 ----------

func _test_account(t: Node) -> void:
	# 强制重置，避免上一运行残留值干扰
	GameState.account_gold = GameState.ACCOUNT_GOLD_START
	GameState.starter_kit_ids = ["pistol", "shotgun", "laser"]
	GameState._save_meta()
	t.eq(GameState.account_gold, GameState.ACCOUNT_GOLD_START, "初始账户金币 300")

	# 免费换回手枪到槽位 0
	GameState.buy_kit_weapon("pistol", 0)
	t.eq(GameState.starter_kit_ids[0], "pistol", "可免费换回手枪到槽位 0")

	# 昂贵武器买不起（先把金币降到买不起狙击枪）
	GameState.account_gold = 200
	t.check(not GameState.buy_kit_weapon("sniper", 0), "账户金币不足时购买失败")

	# 用足够的账户金币买一把传说武器到槽位 0
	GameState.account_gold = 300
	t.check(GameState.buy_kit_weapon("sniper", 0), "账户金币足够时购买成功")
	t.eq(GameState.starter_kit_ids[0], "sniper", "购买后槽位 0 为狙击枪")
	t.eq(GameState.account_gold, 10, "购买后账户扣款 290")

	# 未知武器 id 拒绝
	t.check(not GameState.buy_kit_weapon("no_such_weapon", 0), "未知武器购买失败")
	t.check(not GameState.buy_kit_weapon("pistol", -1), "越界槽位购买失败")
	t.check(not GameState.buy_kit_weapon("pistol", 3), "越界槽位购买失败")

	# 完全通关：当局金币 1/3 转入账户
	GameState.new_run(31337)
	GameState.floor_index = G.TOTAL_FLOORS
	GameState.gold = 300
	GameState.end_run(true)
	t.eq(GameState.last_account_added, 100, "通关后 300 金币的 1/3 = 100 转入账户")
	t.eq(GameState.account_gold, 110, "账户金币 = 10 + 100")

	# 未通关不转化
	GameState.account_gold = 25
	GameState.new_run(111)
	GameState.floor_index = 1
	GameState.gold = 500
	GameState.end_run(false)
	t.eq(GameState.last_account_added, 0, "失败局不转化金币")
	t.eq(GameState.account_gold, 25, "失败局账户金币不变")

	# 归位初始状态，避免影响后续套件 / 玩家存档
	GameState.account_gold = GameState.ACCOUNT_GOLD_START
	GameState.starter_kit_ids = ["pistol", "shotgun", "laser"]
	GameState._save_meta()


# ---------- 设置 ----------

func _test_settings(t: Node) -> void:
	var original: float = float(GameState.settings.get("master_volume", 0.85))
	GameState.set_setting("master_volume", 0.42)
	var loaded: Dictionary = SaveMgr.load_settings()
	t.near(float(loaded.get("master_volume", -1.0)), 0.42, 0.0001, "设置写入磁盘")
	GameState.set_setting("master_volume", original)
	t.check(GameState.settings.has("sfx_volume") and GameState.settings.has("bgm_volume"), "含 SFX/BGM 音量项")
	t.check(GameState.settings.has("fullscreen"), "含全屏设置项")


# ---------- 存档 ----------

func _test_run_save(t: Node) -> void:
	SaveMgr.clear_run()
	t.check(not GameState.has_saved_run(), "无存档时 has_saved_run 为 false")

	GameState.new_run(9001)
	GameState.add_gold(88)
	GameState.stats["health"] = 42.0
	GameState.save_current_run()
	t.check(GameState.has_saved_run(), "存档写入成功")

	var data: Dictionary = SaveMgr.load_run()
	t.eq(int(data.get("gold", -1)), 88, "存档金币正确")
	t.eq(int(data.get("run_seed", -1)), 9001, "存档种子正确")
	t.check(data.get("saved_at", 0) != 0, "存档带时间戳")

	GameState.gold = 0
	GameState.stats["health"] = 1.0
	t.check(GameState.restore_run(data), "restore_run 成功")
	t.eq(GameState.gold, 88, "恢复后金币正确")
	t.near(float(GameState.stats["health"]), 42.0, 0.001, "恢复后生命正确")
	t.check(GameState.run_active, "恢复后 run_active 为真")

	t.check(not GameState.restore_run({}), "空存档恢复返回 false")

	SaveMgr.clear_run()
	t.check(not GameState.has_saved_run(), "清除存档生效")


# ---------- 主场景 ----------

func _test_main_scene(t: Node) -> void:
	t.check(ResourceLoader.exists("res://scenes/main.tscn"), "主场景文件存在")
	var packed: PackedScene = load("res://scenes/main.tscn")
	t.not_null(packed, "主场景可加载")
	if packed == null:
		return
	t.check(packed.can_instantiate(), "主场景可实例化")
	var instance: Node = packed.instantiate()
	t.not_null(instance, "主场景实例化成功")
	if instance == null:
		return
	t.get_tree().root.add_child(instance)
	t.not_null(instance.current_screen, "启动后自动进入菜单界面")
	t.check(not t.get_tree().paused, "启动后不处于暂停状态")
	t.eq(instance.get_child_count(), 1, "路由只挂载一个当前界面")
	# 暂停修复：Main 是 ALWAYS，子界面必须显式 PAUSABLE，否则暂停时世界仍在运行
	t.eq(int(instance.current_screen.process_mode), int(Node.PROCESS_MODE_PAUSABLE), "路由子界面为 PAUSABLE（暂停时才停得下来）")
	t.get_tree().root.remove_child(instance)
	instance.free()


## 暂停修复的行为级验证：get_tree().paused 时玩家受击必须被忽略，
## 解除暂停后恢复正常。防止 Area2D 物理回调在暂停状态仍触发伤害。
func _test_pause_blocks_damage(t: Node) -> void:
	GameState.new_run(20260914)
	var world := GameWorld.new()
	world.name = "PauseTestWorld"
	world.auto_demo_wave = false
	t.add_child(world)
	if world.player == null:
		t.check(false, "暂停测试需要世界内的玩家节点")
		world.queue_free()
		await t.get_tree().process_frame
		return
	var player: Player = world.player
	player.clear_invulnerable()

	var health_before: float = float(player.stats.get("health", 0.0))
	var shield_before: float = float(player.stats.get("shield", 0.0))
	var life_before: float = health_before + shield_before
	t.get_tree().paused = true
	player.take_hit(999.0, false, Vector2.ZERO, 0)
	t.get_tree().paused = false
	t.near(float(player.stats.get("health", 0.0)), health_before, 0.001, "暂停期间受击不扣血")
	t.near(float(player.stats.get("shield", 0.0)), shield_before, 0.001, "暂停期间受击不扣盾")

	player.take_hit(999.0, false, Vector2.ZERO, 0)
	var life_now: float = float(player.stats.get("health", 0.0)) + float(player.stats.get("shield", 0.0))
	t.lt(life_now, life_before, "解除暂停后受击正常扣血")

	world.clear_entities(false)
	world.queue_free()
	await t.get_tree().process_frame
