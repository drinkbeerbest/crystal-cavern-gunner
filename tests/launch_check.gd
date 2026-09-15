extends Node
## 真窗口启动自检（M3 验收用，必须带窗口运行，不能 --headless，否则无法渲染截图）。
##
## 它走的是玩家真实路径：加载 main.tscn -> 主菜单 -> 点击「开始游戏」按钮 ->
## 进入 GameWorld -> 用 Input.action_press 模拟 WASD / 左键 / Shift / 空格 / 数字键 /
## Esc -> 断言移动、射击、冲刺、技能、换枪、受击、暂停恢复都真实生效 ->
## 抓一张视口截图存到 tools/_preview/launch_check.png 供人工核对画面与 HUD。
##
## 运行：
##   "D:/godot/Godot_v4.7.2-stable_win64.exe" --path "D:/game1" res://tests/launch_check.tscn

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const SHOT_PATH: String = "res://tools/_preview/launch_check.png"
const START_KEYWORDS: Array = ["开始", "新游戏", "START", "Start"]
## 地牢段要用房型枚举与房间尺寸常量
const G := preload("res://scripts/core/game_const.gd")

var _passed: int = 0
var _failed: int = 0
var _main: Node = null
var _world: Node = null
var _player: Node = null


func _ready() -> void:
	await _run()


func _run() -> void:
	print("")
	print("====================================================")
	print(" 晶窟枪魂 · 真窗口启动自检")
	print("====================================================")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame

	await _check_boot_into_menu()
	if _world == null or _player == null:
		_summary()
		get_tree().quit(1)
		return

	await _check_movement()
	await _check_shooting()
	await _check_dash_and_skill()
	await _check_weapon_switching()
	await _check_damage_feedback()
	await _check_pause_resume()
	await _check_enemy_archetypes()
	await _check_screenshot()
	await _check_dungeon_flow()
	await _check_boss_battle()
	await _check_drop_talent_bomb()

	await _teardown()
	_summary()
	get_tree().quit(0 if _failed == 0 else 1)


# ==================== 1. 启动 -> 主菜单 -> 战斗世界 ====================

func _check_boot_into_menu() -> void:
	print("")
	print("--- [启动与界面切换] ---")
	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(_main != null, "主场景 main.tscn 实例化成功")
	var menu: Node = _main.get("current_screen")
	_check(menu != null, "启动后已显示初始界面")
	if menu != null:
		print("        初始界面节点: %s" % str(menu.name))

	var start_button: Button = _find_button(menu, START_KEYWORDS)
	_check(start_button != null, "主菜单存在「开始游戏」按钮")
	if start_button == null:
		return
	print("        按钮文案: %s" % start_button.text)
	start_button.pressed.emit()
	for i: int in range(12):
		await get_tree().physics_frame

	_world = _main.get("current_screen")
	_check(_world != null, "点击开始后已切换到新界面")
	if _world == null:
		return
	print("        当前界面节点: %s" % str(_world.name))
	_check(_world.has_method("alive_enemy_count"), "新界面是战斗世界 GameWorld")
	_check(_world.get("player") != null, "战斗世界内已生成玩家")
	_check(_world.get("camera") != null, "战斗世界内已生成相机")
	_check(_world.get("hud") != null, "战斗世界内已生成 HUD")
	_check(not get_tree().paused, "开局场景树未处于暂停")
	_player = _world.get("player")
	await _quiet_arena()


# ==================== 2. WASD 移动 ====================

func _check_movement() -> void:
	print("")
	print("--- [移动] ---")
	await _settle(6)
	var origin: Vector2 = _player.global_position
	Input.action_press("move_right")
	for i: int in range(18):
		await get_tree().physics_frame
	Input.action_release("move_right")
	# 速度是 move_toward 平滑衰减的，需要给它十来帧停下
	await _settle(15)
	var moved: Vector2 = _player.global_position - origin
	_check(moved.length() > 8.0, "按住 D 键玩家真实位移 %.1f px" % moved.length())
	_check(moved.x > 0.0, "位移方向与按键一致（向右）")
	_check(absf(_player.velocity.x) < 1.0, "松开按键后速度归零（实际 %.2f）" % _player.velocity.x)

	origin = _player.global_position
	Input.action_press("move_up")
	Input.action_press("move_left")
	for i: int in range(14):
		await get_tree().physics_frame
	Input.action_release("move_up")
	Input.action_release("move_left")
	await get_tree().physics_frame
	moved = _player.global_position - origin
	_check(moved.length() > 6.0, "斜向组合键可八向移动（位移 %.1f px）" % moved.length())
	_check(moved.x < 0.0 and moved.y < 0.0, "斜向方向为左上")


# ==================== 3. 鼠标瞄准 + 左键射击 ====================

func _check_shooting() -> void:
	print("")
	print("--- [射击] ---")
	_player.manual_aim = true
	_player.aim_direction = Vector2.RIGHT
	GameState.stats["energy"] = _player.max_energy() * 0.5
	await _settle(2)

	var shots_before: int = _player.shots_fired
	var bullets_before: int = _world.bullet_count()
	Input.action_press("shoot")
	for i: int in range(10):
		await get_tree().physics_frame
	Input.action_release("shoot")
	await get_tree().physics_frame
	_check(_player.shots_fired > shots_before, "左键开火：射击计数 %d -> %d" % [shots_before, _player.shots_fired])
	_check(_world.bullet_count() > bullets_before or _world.bullet_count() > 0,
			"开火后弹道层存在子弹（%d 发）" % _world.bullet_count())

	# 耗能单独精确测：直接调 try_fire()，避免能量回复掩盖单次消耗
	await _settle(30)
	GameState.stats["energy"] = 50.0
	await _settle(1)
	var energy_before: float = _player.energy()
	var cost: float = _player.current_weapon().energy_cost
	_player.try_fire()
	await get_tree().physics_frame
	_check(_player.energy() < energy_before - cost * 0.5,
			"开火按武器耗能扣能量 %.1f -> %.1f（手枪耗能 %.0f）" % [energy_before, _player.energy(), cost])

	# 手枪为全自动，按住应连续开火
	var auto_shots: int = _player.shots_fired
	Input.action_press("shoot")
	for i: int in range(30):
		await get_tree().physics_frame
	Input.action_release("shoot")
	_check(_player.shots_fired > auto_shots + 1, "手枪按住连发（%d -> %d）" % [auto_shots, _player.shots_fired])
	await _settle(30)


# ==================== 4. 冲刺与技能 ====================

func _check_dash_and_skill() -> void:
	print("")
	print("--- [冲刺与技能] ---")
	GameState.stats["energy"] = _player.max_energy()
	await _settle(2)

	var dashes_before: int = _player.dashes_used
	var dash_origin: Vector2 = _player.global_position
	Input.action_press("dash")
	await get_tree().physics_frame
	Input.action_release("dash")
	# physics_frame 信号在物理处理之前发出，必须再等两帧才能读到本帧结果
	await _settle(2)
	_check(_player.dashes_used == dashes_before + 1, "Shift 冲刺触发（计数 %d -> %d）" % [dashes_before, _player.dashes_used])
	_check(_player.dash_cooldown_timer > 0.0 or _player.dash_timer > 0.0,
			"冲刺进入冷却（剩余 %.2f s）" % _player.dash_cooldown_timer)
	for i: int in range(10):
		await get_tree().physics_frame
	_check(_player.global_position.distance_to(dash_origin) > 12.0,
			"冲刺产生明显位移（%.1f px）" % _player.global_position.distance_to(dash_origin))

	var skills_before: int = _player.skills_used
	Input.action_press("skill")
	await get_tree().physics_frame
	Input.action_release("skill")
	await _settle(2)
	_check(_player.skills_used == skills_before + 1, "空格技能触发（计数 %d -> %d）" % [skills_before, _player.skills_used])
	_check(_player.skill_cooldown_timer > 0.0, "技能进入冷却（剩余 %.2f s）" % _player.skill_cooldown_timer)
	await _settle(20)


# ==================== 5. 数字键换枪 ====================

func _check_weapon_switching() -> void:
	print("")
	print("--- [武器切换] ---")
	_check(_player.current_weapon().id == "pistol", "初始武器为手枪")

	Input.action_press("weapon_2")
	await get_tree().physics_frame
	Input.action_release("weapon_2")
	await get_tree().physics_frame
	_check(_player.current_weapon().id == "shotgun", "按 2 切到霰弹枪（实际 %s）" % _player.current_weapon().id)

	Input.action_press("weapon_3")
	await get_tree().physics_frame
	Input.action_release("weapon_3")
	await get_tree().physics_frame
	_check(_player.current_weapon().id == "laser", "按 3 切到激光枪（实际 %s）" % _player.current_weapon().id)

	# 激光为穿透射线：先等场上残留子弹自然消失，再确认开火不产生飞行弹
	await _settle(45)
	var laser_shots_before: int = _player.shots_fired
	GameState.stats["energy"] = _player.max_energy()
	# 射击判定走 is_action_pressed，而 physics_frame 信号先于物理处理发出，
	# 必须按住跨过若干物理帧，否则松开会在玩家读取输入之前生效
	Input.action_press("shoot")
	for i: int in range(3):
		await get_tree().physics_frame
	Input.action_release("shoot")
	await _settle(3)
	_check(_player.shots_fired > laser_shots_before, "激光枪可以开火（%d -> %d）" % [laser_shots_before, _player.shots_fired])
	_check(_world.bullet_count() == 0, "激光为 hitscan，不生成飞行子弹（场上 %d 发）" % _world.bullet_count())

	Input.action_press("weapon_1")
	await get_tree().physics_frame
	Input.action_release("weapon_1")
	await get_tree().physics_frame
	_check(_player.current_weapon().id == "pistol", "按 1 切回手枪")


# ==================== 6. 受击反馈 ====================

func _check_damage_feedback() -> void:
	print("")
	print("--- [受击与反馈] ---")
	GameState.stats["shield"] = 0.0
	_player.invulnerable = false
	_player.invulnerable_timer = 0.0
	await _settle(2)

	var hp_before: float = _player.health()
	var taken_before: float = _player.damage_taken_total
	var fx_before: int = _world.fx_root.get_child_count()
	_player.take_hit(15.0, false, Vector2.ZERO, _player.get_instance_id())
	await _settle(3)
	_check(_player.health() < hp_before, "受击扣血 %.1f -> %.1f" % [hp_before, _player.health()])
	_check(_player.damage_taken_total > taken_before, "累计承伤已记录")
	_check(_world.fx_root.get_child_count() > fx_before, "受击生成飘字/特效节点")
	_check(not _player.dead, "15 点伤害不致死")
	_player.heal(_player.max_health())
	await _settle(2)


# ==================== 7. Esc 暂停与恢复 ====================

func _check_pause_resume() -> void:
	print("")
	print("--- [暂停与恢复] ---")
	_push_action("pause")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_world.hud.is_paused, "Esc 暂停：HUD 进入暂停态")
	_check(get_tree().paused, "Esc 暂停：场景树 paused = true")

	_push_action("pause")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not _world.hud.is_paused, "再次 Esc：恢复游戏")
	_check(not get_tree().paused, "恢复后场景树 paused = false")

	# --- M8：暂停面板内嵌设置（F2 打开，Esc 关闭，不退出暂停） ---
	_push_action("pause")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_world.hud.is_paused, "M8 设置：先进入暂停态")
	var hud: Node = _world.hud
	_check(hud.get("_pause_settings") != null, "M8 设置：暂停面板含设置子面板节点")
	if hud.get("_pause_settings") != null:
		_check(not bool(hud.get("_pause_settings").visible), "M8 设置：初始隐藏")
		_push_key(KEY_F2)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(bool(hud.get("_pause_settings").visible), "M8 设置：F2 打开设置面板")
		_check(_world.hud.is_paused and get_tree().paused, "M8 设置：打开设置不退出暂停")
		_push_action("pause")
		await get_tree().process_frame
		await get_tree().process_frame
		_check(not bool(hud.get("_pause_settings").visible), "M8 设置：Esc 关闭设置面板")
		_check(_world.hud.is_paused and get_tree().paused, "M8 设置：关闭后仍在暂停")
	_push_action("pause")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not _world.hud.is_paused, "M8 设置：最后恢复游戏")


# ==================== 8. 三类敌人在真实窗口里可区分（M4） ====================

## 关掉试验场的自动演示波次并清场。
## 玩家相关断言（位移 / 冲刺 / hitscan 计数）必须在安静场地里做：
## 敌人的身体会挡住冲刺，远程敌弹会被算进"场上子弹数"。
## 敌人本身的断言放在第 8 节，验证完再让截图带上它们。
func _quiet_arena() -> void:
	if _world == null:
		return
	_world.auto_demo_wave = false
	_world._demo_timer = -1.0
	var spawner: Variant = _world.get("spawner")
	if spawner != null:
		spawner.despawn_all()
	await _settle(4)
	var spawner_ref: Variant = _world.get("spawner")
	var owned: int = spawner_ref.alive_count() if spawner_ref != null else _world.alive_enemy_count()
	_check(owned == 0, "玩家断言前本波敌人已清空（存活 %d）" % owned)


## 只补血盾能量、不弹提示（_dev_refill 会 show_toast，会污染后面的截图核对）
func _top_up_player() -> void:
	if _player == null:
		return
	_player.stats["health"] = _player.max_health()
	_player.stats["shield"] = _player.max_shield()
	_player.stats["energy"] = _player.max_energy()
	EventBus.player_health_changed.emit(_player.health(), _player.max_health())


func _check_enemy_archetypes() -> void:
	print("")
	print("--- [敌人三类行为] ---")
	var spawner: Variant = _world.get("spawner")
	_check(spawner != null, "战斗世界挂载了敌人生成器")
	if spawner == null:
		return
	# 试验场的训练靶也在敌人组里，但不归 spawner 管；本波计数一律用 alive_count()
	var dummies: int = _world.alive_enemy_count() - spawner.alive_count()

	var ids: Array = _world.spawn_wave(["husk", "hexeye", "bloom"])
	_check(ids.size() == 3, "投放了三类敌人各一只（%s）" % str(ids))

	# 波次会分批投放（G.WAVE_BATCH_DELAY = 3.2 秒），等待窗口必须盖过全部批次间隔；
	# 真窗口帧率低于 60 时按帧数换算会偏短，所以这里给足冗余（200 轮 x 3 帧）。
	# 自爆型可能刚上场就贴近玩家引爆并被回收，所以判定看累计投放数 total_spawned
	# 加"是否见过自爆型"，不依赖某一帧的存活快照。
	var roster: int = spawner.alive_count()
	var seen_bomber: bool = false
	var bomber_gone: bool = false
	for i: int in range(200):
		await _settle(3)
		roster = spawner.alive_count()
		if spawner.enemies_of_archetype(EnemyData.Archetype.BOMBER).is_empty():
			bomber_gone = bomber_gone or seen_bomber
		else:
			seen_bomber = true
		if spawner.total_spawned >= 3 and (seen_bomber or bomber_gone):
			break
	_check(spawner.total_spawned >= 3, "三只敌人都已投放（累计 %d，本波存活 %d，试验靶 %d）"
			% [spawner.total_spawned, roster, dummies])
	_check(seen_bomber or bomber_gone, "自爆型确曾到场（见过 %s / 已引爆离场 %s）"
			% [str(seen_bomber), str(bomber_gone)])

	var melee: Array = spawner.enemies_of_archetype(EnemyData.Archetype.MELEE)
	var ranged: Array = spawner.enemies_of_archetype(EnemyData.Archetype.RANGED)
	var bomber: Array = spawner.enemies_of_archetype(EnemyData.Archetype.BOMBER)
	_check(not melee.is_empty() and melee[0] is EnemyHusk, "近战原型在场且为 EnemyHusk（%d 只）" % melee.size())
	_check(not ranged.is_empty() and ranged[0] is EnemyHexeye, "远程原型在场且为 EnemyHexeye（%d 只）" % ranged.size())
	_check(bomber.is_empty() or bomber[0] is EnemyBloom,
			"自爆原型为 EnemyBloom（当前存活 %d 只）" % bomber.size())

	var husk: EnemyHusk = melee[0] if not melee.is_empty() else null
	var hexeye: EnemyHexeye = ranged[0] if not ranged.is_empty() else null
	var bloom: EnemyBloom = bomber[0] if not bomber.is_empty() else null

	# 让三类敌人真实打一会儿：逐轮打标记，敌人中途阵亡或被释放也不会漏记。
	# 每轮补一次血盾能量（不走 _dev_refill，避免弹提示污染后面的截图核对），
	# 否则玩家可能在观察窗口里被打死、界面切到结算，后续断言就无从下手了。
	var husk_acted: bool = false
	var hexeye_acted: bool = false
	var bloom_acted: bool = false
	for i: int in range(40):
		_top_up_player()
		await _settle(5)
		if husk != null and is_instance_valid(husk) \
				and (husk.charges_done > 0 or husk.state == Enemy.State.ATTACK):
			husk_acted = true
		if hexeye != null and is_instance_valid(hexeye) \
				and (hexeye.bullets_fired > 0 or hexeye.state == Enemy.State.ATTACK):
			hexeye_acted = true
		if bloom != null and is_instance_valid(bloom) \
				and (bloom.fusing or bloom.exploded or bloom.state == Enemy.State.ATTACK):
			bloom_acted = true
	# 自爆型引爆后会被回收：见过又消失，就等于它跑完了自己的攻击行为
	if not bloom_acted and (bomber_gone or (bloom != null and not is_instance_valid(bloom))):
		bloom_acted = true
	var acted: int = int(husk_acted) + int(hexeye_acted) + int(bloom_acted)
	_check(acted == 3, "三类敌人各自进入了自己的攻击行为（近战 %s / 远程 %s / 自爆 %s）"
			% [str(husk_acted), str(hexeye_acted), str(bloom_acted)])
	_check(_player.damage_taken_total > 0.0, "敌人对玩家形成了真实压力（累计承伤 %.1f）"
			% _player.damage_taken_total)


# ==================== 9. 视口截图 ====================

func _check_screenshot() -> void:
	print("")
	print("--- [画面渲染] ---")
	_player.manual_aim = true
	_player.aim_direction = Vector2(0.7, -0.7).normalized()
	GameState.stats["energy"] = _player.max_energy()
	Input.action_press("shoot")
	for i: int in range(3):
		await get_tree().physics_frame
	Input.action_release("shoot")
	await get_tree().process_frame
	await get_tree().process_frame

	var image: Image = get_viewport().get_texture().get_image()
	_check(image != null, "视口截图获取成功")
	if image == null:
		return
	print("        截图尺寸: %s" % str(image.get_size()))
	image.save_png(SHOT_PATH)

	var file: FileAccess = FileAccess.open(SHOT_PATH, FileAccess.READ)
	_check(file != null, "截图已写入 %s" % SHOT_PATH)
	if file != null:
		var bytes: int = file.get_length()
		file.close()
		_check(bytes > 4096, "截图文件大小合理（%d 字节）" % bytes)

	var sampled: Dictionary = {}
	for y: int in range(0, image.get_height(), 16):
		for x: int in range(0, image.get_width(), 16):
			sampled[image.get_pixel(x, y)] = true
	_check(sampled.size() >= 8, "采样到 %d 种颜色，画面已真实渲染（非黑屏）" % sampled.size())


# ==================== 10. 地牢房间流程（M5） ====================

## 真窗口跑一遍完整地牢闭环：起始房 -> 战斗房清怪开门 -> 门传送 ->
## 精英房取钥匙 -> Boss 门放行 -> 传送门换层，最后截一张地牢画面。
## 单独建一个 GameWorld(dungeon_mode) 与试验场并存，验完自己释放。
const DUNGEON_SHOT_PATH: String = "res://tools/_preview/launch_check_dungeon.png"

## 真窗口下敌人会真的打人，把沙包玩家的血线抬满，免得检查途中世界被判负结束。
## 注意：health 会被玩家自身 clamp 回 max_health，所以"6000 血"其实只是补满，
## 真正保命靠长无敌；同时必须取消死亡倒计时并复位 finished/run_active，
## 否则世界一旦走完 end_run(false)，门/传送门/掉落都会被 finished 门控挡掉。
func _dungeon_top_up(dw: GameWorld) -> void:
	if dw == null or dw.player == null:
		return
	dw._death_timer = -1.0
	if dw.finished:
		dw.finished = false
	if not GameState.run_active:
		GameState.run_active = true
	dw.player.stats["shield"] = 0.0
	dw.player.stats["health"] = 6000.0
	dw.player.clear_invulnerable()
	# 炸弹/小怪留下的击退速度会在下一物理帧把玩家甩走，定位类断言前先清干净
	dw.player.velocity = Vector2.ZERO
	dw.player._external_velocity = Vector2.ZERO
	# 自检里玩家可能被自己的炸弹或小怪打死，而死亡态会让 Pickup.collect() 直接拒绝结算，
	# 后续掉落断言就会全红——这里把 die() 改掉的标志与碰撞层一并复位。
	if dw.player.dead:
		dw.player.dead = false
		dw.player.collision_layer = G.LAYER_PLAYER
		dw.player.collision_mask = G.MASK_PLAYER
		if dw.player._body_sprite != null:
			dw.player._body_sprite.modulate = Color(1, 1, 1, 1)
		if dw.player._weapon_sprite != null:
			dw.player._weapon_sprite.visible = true
	dw.player.set_invulnerable(120.0)


## 门口 -> 房间内侧的偏移（把玩家"站"进门洞里）
func _inward(dir: int) -> Vector2:
	match dir:
		0: return Vector2(0, 12)    # 北门：往 +Y 进屋
		1: return Vector2(0, -12)   # 南门
		2: return Vector2(12, 0)    # 西门
		3: return Vector2(-12, 0)   # 东门
	return Vector2.ZERO


## rooms_of_kind 返回房间数据字典，取里面的 index
func _first_kind(layout: DungeonLayout, kind: int) -> int:
	var list: Array = layout.rooms_of_kind(kind)
	return int(list[0]["index"]) if not list.is_empty() else -1


func _dungeon_door_to(dw: GameWorld, target_index: int) -> Door:
	for entry: Variant in dw.doors:
		if is_instance_valid(entry) and (entry as Door).target_index == target_index:
			return entry
	return null


## 轮询等待条件成立（门的 ARM_DELAY、钥匙浮动、传送门蓄力都要真等物理帧）
func _dungeon_wait(cond: Callable, max_tries: int = 60) -> bool:
	for i: int in range(max_tries):
		if bool(cond.call()):
			return true
		await _settle(2)
	return bool(cond.call())


func _check_dungeon_flow() -> void:
	print("")
	print("--- [地牢房间流程] ---")
	GameState.new_run(20260915)
	GameState.add_gold(120)
	# 主菜单进来的世界现在也是地牢模式，会和检查世界叠加渲染（截图里会混进它的敌人），
	# 画面核对前先把它藏起来；相机由检查世界接管，不影响后续断言。
	if _world != null and is_instance_valid(_world):
		_world.visible = false
	var dw: GameWorld = GameWorld.new()
	dw.name = "DungeonCheckWorld"
	# 必须在 add_child 之前打开：_ready 按这个开关决定走地牢还是试验场
	dw.dungeon_mode = true
	add_child(dw)
	await _settle(10)
	_dungeon_top_up(dw)

	# --- 布局不变量（真窗口下再核一遍）
	var layout: DungeonLayout = dw.layout
	_check(layout != null, "地牢世界生成了布局")
	if layout == null:
		dw.queue_free()
		return
	var normals: int = layout.normal_room_count()
	_check(normals >= 5 and normals <= 10, "本层普通房间数在 5-10 之间（%d 间）" % normals)
	_check(layout.room_kind(layout.boss_index) == G.RoomKind.BOSS,
			"Boss 房唯一（index=%d）" % layout.boss_index)
	_check(layout.all_reachable(), "所有房间都能从起始房走到")

	# --- 起始房
	_check(dw.current_room_kind() == G.RoomKind.START, "开局落在起始房")
	_check(dw.doors.size() > 0 and dw.open_door_count() == dw.doors.size(),
			"起始房门全开（%d 扇）" % dw.doors.size())
	_check(dw.spawner.alive_count() == 0, "起始房不出怪")
	_check(dw.interior_rect.grow(8.0).has_point(dw.player.position), "玩家站在起始房可行走区内")
	_check(dw.camera.has_bounds, "相机已绑定房间边界")

	# --- 战斗房：关门开波 -> 清怪开门
	var combat: int = _first_kind(layout, G.RoomKind.COMBAT)
	_check(combat >= 0, "布局里有纯战斗房")
	dw.goto_room(combat)
	await _settle(12)
	_dungeon_top_up(dw)
	_check(dw.current_room_index == combat, "已切入战斗房")
	_check(dw.spawner.alive_count() > 0, "战斗房刷出敌人（%d 只）" % dw.spawner.alive_count())
	_check(dw.open_door_count() == 0, "开波后门全部关闭")
	dw.clear_current_room()
	await _settle(10)
	_check(dw.spawner.alive_count() == 0, "清怪后场上没有敌人")
	_check(dw.open_door_count() == dw.doors.size(), "清怪后门重新开启")

	# --- 门传送（靠 Area2D 真重叠，不是直接调函数）
	var travel_door: Door = dw.doors[0]
	var travel_target: int = travel_door.target_index
	var travel_from: int = dw.current_room_index
	_check(travel_door.is_open, "清怪后的门是开着的（可通行）")
	dw.player.position = travel_door.global_position + _inward(travel_door.dir)
	var travelled: bool = await _dungeon_wait(
			func() -> bool: return dw.current_room_index == travel_target, 60)
	_check(travelled, "走进开着的门 -> 切换到邻房（%d -> %d）" % [travel_from, travel_target])
	_check(_dungeon_door_to(dw, travel_from) != null, "新房里有一扇能走回原房的门（双向连通）")

	# --- 精英房：清怪掉钥匙 -> 踩上拾取
	GameState.set_floor_key(false)
	var elite: int = layout.elite_index
	_check(elite >= 0, "布局里有精英房（钥匙房）")
	dw.goto_room(elite)
	await _settle(12)
	_dungeon_top_up(dw)
	_check(dw.floor_key == null, "没清怪前钥匙不出现")
	dw.clear_current_room()
	await _settle(10)
	_check(dw.floor_key != null, "精英房清怪后掉出地牢钥匙")
	if dw.floor_key != null:
		_check(dw.floor_key.position.distance_to(dw.room.get("center", Vector2.ZERO)) < 40.0,
				"钥匙掉在房间中央附近（没被浮动基准点甩走）")
		dw.player.position = dw.floor_key.position
		var got_key: bool = await _dungeon_wait(func() -> bool: return GameState.has_floor_key, 90)
		_check(got_key, "踩上钥匙 -> GameState.has_floor_key 置真")
		_check(dw.floor_key == null, "钥匙拾取后从世界里移除")

	# --- Boss 门：没钥匙不放行，有钥匙开门并消耗
	var boss: int = layout.boss_index
	var neighbors: Array = layout.neighbor_indexes(boss)
	_check(not neighbors.is_empty(), "Boss 房有邻居房间")
	var gate_room: int = int(neighbors[0])
	GameState.set_floor_key(false)
	dw.goto_room(gate_room)
	await _settle(12)
	_dungeon_top_up(dw)
	dw.clear_current_room()
	await _settle(10)
	var boss_door: Door = _dungeon_door_to(dw, boss)
	_check(boss_door != null and boss_door.is_boss_door, "通往 Boss 房的门被标记为 Boss 门")
	if boss_door != null:
		_check(boss_door.is_locked(), "没钥匙时 Boss 门上锁")
		dw._key_toast_timer = 0.0
		dw.player.position = boss_door.global_position + _inward(boss_door.dir)
		await _settle(30)
		_dungeon_top_up(dw)
		_check(dw.current_room_index == gate_room, "没钥匙撞 Boss 门不放行")
		GameState.set_floor_key(true)
		var entered: bool = await _dungeon_wait(
				func() -> bool: return dw.current_room_index == boss, 90)
		_check(entered, "有钥匙撞 Boss 门 -> 进入 Boss 房")
		_check(not GameState.has_floor_key, "开门消耗掉地牢钥匙")
		_check(dw.current_room_kind() == G.RoomKind.BOSS, "当前房型 = Boss 房")

	# --- Boss 房（M7 起有真 Boss）：击杀 -> 清场 -> 传送门 -> 换层
	await _settle(12)
	_dungeon_top_up(dw)
	var boss_arrived: bool = await _dungeon_wait(
			func() -> bool: return not dw.spawner.enemies_of_archetype(EnemyData.Archetype.BOSS).is_empty(), 90)
	_check(boss_arrived, "Boss 房投放了 Boss 实体（%d 只）"
			% dw.spawner.enemies_of_archetype(EnemyData.Archetype.BOSS).size())
	if boss_arrived:
		var boss_node: Variant = dw.spawner.enemies_of_archetype(EnemyData.Archetype.BOSS)[0]
		_check(boss_node is EnemyBoss, "投放的是 EnemyBoss 实例")
		if dw.hud != null:
			_check(dw.hud.get("_boss_panel") != null and dw.hud._boss_panel.visible, "HUD Boss 血条已显示")
		_dungeon_top_up(dw)
		boss_node.take_hit(999999.0, false, Vector2.ZERO, 0)
	var boss_cleared: bool = await _dungeon_wait(
			func() -> bool: return dw.boss_room_cleared, 150)
	_check(boss_cleared, "Boss 击杀后房间清空判定通过")
	_check(dw.portal != null and dw.portal.is_active, "Boss 房清空后传送门激活")
	if dw.portal != null:
		_check(dw.portal.target_floor == GameState.floor_index + 1, "传送门指向下一层")
		var floor_before: int = GameState.floor_index
		# 踩门前的金币数：换层不该动它（路上捡到的掉落已经算在里面）
		var gold_at_portal: int = GameState.gold
		dw.player.position = dw.portal.position
		var advanced: bool = await _dungeon_wait(
				func() -> bool: return GameState.floor_index == floor_before + 1, 160)
		if not advanced:
			print("    [diag-portal] finished=%s run_active=%s death_timer=%.2f player_dead=%s portal_active=%s room=%d/%d" % [
					dw.finished, GameState.run_active, dw._death_timer, dw.player.dead,
					dw.portal != null and dw.portal.is_active,
					dw.current_room_index, dw.layout.start_index])
		_check(advanced, "踩上传送门进入下一层（%d -> %d）" % [floor_before, floor_before + 1])
		_check(GameState.gold == gold_at_portal, "跨层保留金币（进门前 %d 枚 -> 换层后 %d 枚）"
				% [gold_at_portal, GameState.gold])
		_check(dw.current_room_index == dw.layout.start_index, "新层从起始房开始")
		_check(not GameState.has_floor_key, "换层后钥匙清空（每层重新找）")
		_check(dw.interior_rect.grow(12.0).has_point(dw.player.position), "换层后玩家已落到新起始房内")

	# --- 地牢画面：门洞 / 墙体 / 装饰都要真渲染出来
	await _settle(12)
	var dungeon_image: Image = get_viewport().get_texture().get_image()
	_check(dungeon_image != null, "地牢画面截图获取成功")
	if dungeon_image != null:
		dungeon_image.save_png(DUNGEON_SHOT_PATH)
		var dfile: FileAccess = FileAccess.open(DUNGEON_SHOT_PATH, FileAccess.READ)
		_check(dfile != null, "地牢截图已写入 %s" % DUNGEON_SHOT_PATH)
		if dfile != null:
			dfile.close()
		var sampled: Dictionary = {}
		for y: int in range(0, dungeon_image.get_height(), 16):
			for x: int in range(0, dungeon_image.get_width(), 16):
				sampled[dungeon_image.get_pixel(x, y)] = true
		_check(sampled.size() >= 8, "地牢画面采样到 %d 种颜色（非黑屏）" % sampled.size())

	dw.clear_entities(false)
	dw.queue_free()
	await _settle(6)


# ==================== 11. 掉落 · 天赋 · 炸弹（M6） ====================

const DROPS_SHOT_PATH: String = "res://tools/_preview/launch_check_drops.png"


func _check_drop_talent_bomb() -> void:
	print("")
	print("--- [掉落 · 天赋 · 炸弹] ---")
	GameState.new_run(20260916)
	GameState.add_gold(200)
	GameState.add_bombs(3)
	if _world != null and is_instance_valid(_world):
		_world.visible = false
		# 冻结主世界玩家，避免它和 dw.player 同时响应 Input.action_press
		if _world.player != null:
			_world.player.set_physics_process(false)
			_world.player.set_process(false)
	var dw: GameWorld = GameWorld.new()
	dw.name = "DropCheckWorld"
	dw.dungeon_mode = true
	add_child(dw)
	await _settle(10)
	_dungeon_top_up(dw)
	var hud: HUD = dw.hud

	# --- 祈愿祭坛：起始房里有，走过去按 E 能换到天赋
	var altar: Altar = dw.altar
	_check(altar != null, "起始房生成了祈愿祭坛")
	if altar != null:
		_check(altar.can_interact(dw.player), "祭坛可交互（剩余 %d 次）" % altar.remaining_uses())
		_check(altar.interact_prompt().find("祈愿") >= 0, "祭坛提示文案带「祈愿」：%s" % altar.interact_prompt())
		dw.player.position = altar.global_position + Vector2(0, 10)
		await _settle(4)
		var talents_before: int = GameState.talents.size()
		var gold_before: int = GameState.gold
		Input.action_press("interact")
		await _settle(2)
		Input.action_release("interact")
		await _settle(8)
		_check(GameState.talents.size() > talents_before,
				"E 键祈愿拿到天赋（%d -> %d）" % [talents_before, GameState.talents.size()])
		_check(GameState.gold < gold_before, "祈愿扣了金币（%d -> %d）" % [gold_before, GameState.gold])
		_check(altar.remaining_uses() == G.ALTAR_USE_LIMIT - 1, "祭坛可用次数 -1")

	# --- HUD：天赋栏亮起来、炸弹计数跟着 GameState 走
	_check(hud != null and hud._talent_dock != null and hud._talent_dock.visible, "有天赋时 HUD 天赋栏显示")
	if hud != null and not hud._talent_slots.is_empty():
		var icon: TextureRect = hud._talent_slots[0]
		_check(icon != null and icon.texture != null, "天赋槽里有图标贴图")
	_check(hud != null and hud._bomb_label != null and hud._bomb_label.text == str(GameState.bombs),
			"HUD 炸弹计数正确（显示 %s）"
					% (hud._bomb_label.text if hud != null and hud._bomb_label != null else "?"))

	# --- F 键投掷炸弹：扣枚数、生成实体、引信走完自动爆炸
	dw.player.manual_aim = true
	dw.player.aim_direction = Vector2(0, -1)
	dw.player.bomb_cooldown_timer = 0.0
	var bombs_before: int = GameState.bombs
	var thrown_before: int = dw.player.bombs_thrown
	Input.action_press("throw_bomb")
	await _settle(2)
	Input.action_release("throw_bomb")
	await _settle(4)
	_check(GameState.bombs == bombs_before - 1,
			"F 键投掷消耗 1 枚炸弹（%d -> %d）" % [bombs_before, GameState.bombs])
	_check(dw.player.bombs_thrown > thrown_before, "投掷计数 +1")
	var bomb: ThrownBomb = _find_bomb_node(dw)
	_check(bomb != null, "世界里生成了炸弹实体")
	if bomb != null:
		_check(bomb.bounds == dw.interior_rect, "炸弹飞行范围绑定当前房间")
		# 轮询世界里还有没有炸弹节点——爆炸后 ThrownBomb 会 queue_free 自己，
		# 用 _find_bomb_node(dw)==null 代替捕获 bomb 引用，避免 lambda 捕获已释放对象报 ERROR。
		var boom: bool = await _dungeon_wait(func() -> bool: return _find_bomb_node(dw) == null, 200)
		_check(boom, "引信走完后炸弹自动爆炸")
	await _settle(6)
	_dungeon_top_up(dw)

	# --- 掉落实体化：敌人死掉地上真有东西，走过去被磁吸吃掉
	var victim: Enemy = dw.spawn_enemy("husk", dw.player.global_position + Vector2(64, 0))
	_check(victim != null, "生成一只敌人用于掉落验证")
	if victim != null:
		# 敌人刚 add_child 的当帧还没进物理空间，出生保护也可能吃掉伤害——先等几帧再秒杀。
		# 注意：Enemy.damage_target() 是"敌人打它的目标（玩家）"，打敌人要用 take_hit()。
		await _settle(4)
		victim.take_hit(99999.0, false, Vector2.ZERO, 0)
		var dropped: bool = await _dungeon_wait(func() -> bool: return dw.pickup_count() > 0, 90)
		if not dropped:
			print("    [diag-drop] victim_valid=%s victim_dead=%s queued=%d pickups=%d finished=%s run_active=%s death_timer=%.2f player_dead=%s player_hp=%.0f" % [
					is_instance_valid(victim), (victim.dead if is_instance_valid(victim) else false),
					dw.queued_drops.size(), dw.pickup_count(), dw.finished, GameState.run_active,
					dw._death_timer, dw.player.dead, dw.player.health()])
		_check(dropped, "敌人死亡掉出实体拾取物（%d 枚）" % dw.pickup_count())
		var coin: Pickup = _find_pickup_of_kind(dw, G.PickupKind.COIN)
		_check(coin != null, "掉落里有金币拾取物")
		if coin != null:
			var gold_before_coin: int = GameState.gold
			# 玩家与金币互相贴齐：清掉击退残余速度（否则下一帧 move_and_slide 会把玩家甩出磁吸半径），
			# 再把金币挪到玩家脚下并跳过撒开/拾取保护，确保 _check_collect 当帧就能命中。
			dw.player.velocity = Vector2.ZERO
			dw.player._external_velocity = Vector2.ZERO
			coin._scatter_time = 0.0
			coin._scatter_velocity = Vector2.ZERO
			coin._arm_timer = 0.0
			coin.global_position = dw.player.global_position
			# 轮询世界里金币是否消失，避免 lambda 捕获已 queue_free 的 coin 报 ERROR
			var eaten: bool = await _dungeon_wait(
					func() -> bool: return _find_pickup_of_kind(dw, G.PickupKind.COIN) == null, 150)
			if not eaten:
				var left: Pickup = _find_pickup_of_kind(dw, G.PickupKind.COIN)
				print("    [diag] dead=%s health=%.0f can_collect=%s target_ok=%s dist=%.1f" % [
						dw.player.dead, dw.player.health(),
						(left != null and left.can_collect()),
						(left != null and left.target_player == dw.player),
						(left.global_position.distance_to(dw.player.global_position) if left != null else -1.0)])
			_check(eaten, "走到金币上被磁吸吃掉")
			_check(GameState.gold > gold_before_coin,
					"金币入账（%d -> %d）" % [gold_before_coin, GameState.gold])
			_check(dw.gold_from_drops > 0, "世界统计到掉落金币（%d）" % dw.gold_from_drops)

	# --- 天赋到期：加成清空，HUD 天赋栏收起来
	GameState.tick_talents(999.0)
	await _settle(6)
	_check(GameState.talents.is_empty(), "天赋到期后列表清空")
	_check(hud != null and hud._talent_dock != null and not hud._talent_dock.visible, "天赋到期后 HUD 天赋栏隐藏")

	# --- 掉落画面：拾取物 / 天赋栏 / 祭坛都要真渲染出来
	await _settle(10)
	var drop_image: Image = get_viewport().get_texture().get_image()
	_check(drop_image != null, "掉落画面截图获取成功")
	if drop_image != null:
		drop_image.save_png(DROPS_SHOT_PATH)
		var dfile: FileAccess = FileAccess.open(DROPS_SHOT_PATH, FileAccess.READ)
		_check(dfile != null, "掉落截图已写入 %s" % DROPS_SHOT_PATH)
		if dfile != null:
			dfile.close()
		var sampled: Dictionary = {}
		for y: int in range(0, drop_image.get_height(), 16):
			for x: int in range(0, drop_image.get_width(), 16):
				sampled[drop_image.get_pixel(x, y)] = true
		_check(sampled.size() >= 8, "掉落画面采样到 %d 种颜色（非黑屏）" % sampled.size())

	dw.clear_entities(false)
	dw.queue_free()
	await _settle(6)


func _find_bomb_node(dw: GameWorld) -> ThrownBomb:
	for child: Node in dw.entity_root.get_children():
		if child is ThrownBomb:
			return child
	return null


func _find_pickup_of_kind(dw: GameWorld, kind: int) -> Pickup:
	for entry: Variant in dw.room_pickups:
		if is_instance_valid(entry) and entry is Pickup and (entry as Pickup).kind == kind:
			return entry
	return null


# ==================== 12. Boss 战 · 技能 · 阶段（M7） ====================

## 真窗口打一轮完整 Boss 战：Boss 房投放 warden -> HUD 血条出现 ->
## 观察 Boss 打出技能 -> 压血到 50% 触发阶段 2 + HUD 阶段横幅 ->
## 击杀后小怪清空、房间判定清空、传送门出现 -> 截一张 Boss 战画面。
## 复用 _dungeon_top_up / _dungeon_wait 的地牢世界脚手架。
const BOSS_SHOT_PATH: String = "res://tools/_preview/launch_check_boss.png"


func _check_boss_battle() -> void:
	print("")
	print("--- [Boss 战 · 技能 · 阶段] ---")
	GameState.new_run(20260917)
	GameState.add_gold(200)
	if _world != null and is_instance_valid(_world):
		_world.visible = false
		# 冻结主世界玩家，避免它和 dw.player 同时响应 Input.action_press
		if _world.player != null:
			_world.player.set_physics_process(false)
			_world.player.set_process(false)
	var dw: GameWorld = GameWorld.new()
	dw.name = "BossCheckWorld"
	dw.dungeon_mode = true
	add_child(dw)
	await _settle(10)
	_dungeon_top_up(dw)
	var hud: HUD = dw.hud

	# --- 直接进 Boss 房（钥匙已就绪）
	var boss_idx: int = dw.layout.boss_index
	dw.goto_room(boss_idx)
	var boss_arrived: bool = await _dungeon_wait(
			func() -> bool: return not dw.spawner.enemies_of_archetype(EnemyData.Archetype.BOSS).is_empty(), 90)
	_check(boss_arrived, "Boss 房投放出 Boss（%d 只）"
			% dw.spawner.enemies_of_archetype(EnemyData.Archetype.BOSS).size())
	if not boss_arrived:
		dw.clear_entities(false)
		dw.queue_free()
		await _settle(6)
		return
	var boss_node: EnemyBoss = dw.spawner.enemies_of_archetype(EnemyData.Archetype.BOSS)[0] as EnemyBoss
	_check(boss_node is EnemyBoss, "投放的是 EnemyBoss 实例")
	if boss_node == null:
		dw.clear_entities(false)
		dw.queue_free()
		await _settle(6)
		return
	_check(boss_node.display_name != "", "Boss 有显示名：%s" % boss_node.display_name)
	_check(dw.hud != null and dw.hud.get("_boss_panel") != null and dw.hud._boss_panel.visible,
			"HUD Boss 血条已显示")
	_check(dw.open_door_count() == 0, "Boss 战期间房门紧锁")

	# --- 观察 Boss 打出一轮技能（皮糙肉厚，给足物理帧覆盖预警 + 执行 + 冷却轮转）
	var saw_skill: bool = false
	for i: int in range(300):
		_dungeon_top_up(dw)
		await _settle(3)
		if (boss_node.radials_fired > 0 or boss_node.fans_fired > 0
				or boss_node.summons_done > 0 or boss_node.charges_done > 0
				or boss_node.slams_done > 0):
			saw_skill = true
			break
	_check(saw_skill, "Boss 打出过实质性技能（radial/fan/summon/charge/slam）")
	_check(dw.spawner.alive_count() >= 1, "Boss 战进行中 Boss 存活")

	# --- 压血到 50% 以下：进入阶段 2 + HUD 阶段横幅
	_dungeon_top_up(dw)
	var hp_now: float = boss_node.health
	boss_node.take_hit(hp_now * 0.6, false, Vector2.ZERO, 0)
	await _settle(10)
	_dungeon_top_up(dw)
	_check(boss_node.phase_index == 2, "血量跨过 50%% 进入阶段 2（当前 %d）" % boss_node.phase_index)
	_check(hud != null and hud.get("_phase_banner") != null and hud._phase_banner.text == "阶段 2",
			"HUD 弹出阶段横幅（%s）"
			% (hud._phase_banner.text if hud != null and hud.get("_phase_banner") != null else "?"))

	# --- 击杀 -> 小怪清场 -> 房间判定清空 -> 传送门
	_dungeon_top_up(dw)
	boss_node.take_hit(999999.0, false, Vector2.ZERO, 0)
	var boss_dead: bool = await _dungeon_wait(
			func() -> bool: return dw.spawner.alive_count() == 0, 150)
	_check(boss_dead, "Boss 及其召唤物全部清场（存活 %d）" % dw.spawner.alive_count())
	var cleared: bool = await _dungeon_wait(
			func() -> bool: return dw.boss_room_cleared, 120)
	_check(cleared, "Boss 击杀后房间清空判定通过")
	_check(dw.portal != null and dw.portal.is_active, "Boss 房清空后传送门激活")

	# --- Boss 战画面：血条 / 阶段横幅 / Boss 本体真人渲染
	await _settle(10)
	var image: Image = get_viewport().get_texture().get_image()
	_check(image != null, "Boss 战截图获取成功")
	if image != null:
		image.save_png(BOSS_SHOT_PATH)
		var sampled: Dictionary = {}
		for y: int in range(0, image.get_height(), 16):
			for x: int in range(0, image.get_width(), 16):
				sampled[image.get_pixel(x, y)] = true
		_check(sampled.size() >= 8, "Boss 战画面采样到 %d 种颜色（非黑屏）" % sampled.size())

	dw.clear_entities(false)
	dw.queue_free()
	await _settle(6)


# ==================== 工具函数 ====================

func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		_world.clear_entities(false)
		_world.queue_free()
		await get_tree().process_frame
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	# 与真实退出路径一致：清掉静态纹理缓存，避免退出时报 resources still in use
	Fx.clear_cache()
	RoomBuilder.clear_cache()
	AudioMgr.shutdown()


func _settle(frames: int) -> void:
	for i: int in range(frames):
		await get_tree().physics_frame


## 暂停由 HUD 的 _unhandled_input 监听 InputEvent 触发，
## Input.action_press 不产生事件，因此这里推送一个 InputEventAction 走真实输入管线。
func _push_action(action_name: String) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	get_viewport().push_input(event, true)


## 推送一个物理按键事件（M8 暂停设置面板的 F2 走 InputEventKey 分支）。
func _push_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	get_viewport().push_input(event, true)


func _find_button(root: Node, keywords: Array) -> Button:
	if root == null:
		return null
	for child: Node in root.get_children():
		var button: Button = child as Button
		if button != null:
			for keyword: Variant in keywords:
				if String(keyword) in button.text:
					return button
		var found: Button = _find_button(child, keywords)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  PASS | %s" % message)
	else:
		_failed += 1
		print("  FAIL | %s" % message)


func _summary() -> void:
	print("")
	print("====================================================")
	print(" 真窗口自检结果: %d 通过 / %d 失败 / 共 %d 项" % [_passed, _failed, _passed + _failed])
	print(" 截图: %s" % SHOT_PATH)
	print("====================================================")
