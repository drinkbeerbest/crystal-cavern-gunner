class_name GameWorld
extends Node2D
## GameWorld —— 游戏世界：随机地牢 + 房间流程（M5）。
##
## 两种模式：
##   - dungeon_mode（真机默认）：每层由 DungeonLayout 随机生成 5~10 个房间 + 1 个 Boss 房，
##     房间靠门连通。清怪开门 → 精英房掉地牢钥匙 → Boss 房门需要钥匙 → Boss 房清空开传送门 → 下一层。
##   - arena_mode（M3/M4 的战斗试验场，自动化测试继续用它）：单房间 + 演示波次 + 训练靶。
##
## 职责：
##   1. 分层组装世界（房间层 / 实体层 / 弹道层 / 特效层 / UI 层），保证绘制与清理顺序清晰；
##   2. 生成玩家、相机、HUD，并把弹道层/特效层注入玩家；
##   3. 按 DungeonLayout 逐房搭建房间（RoomBuilder 留门洞），并挂门 / 传送门 / 宝箱 / 商店垫 / 钥匙；
##   4. 通过 EnemySpawner 投放当前房间的波次，并统一处理全局事件：
##      伤害飘字、玩家死亡结算、敌人击杀奖励与掉落分流。

const G := preload("res://scripts/core/game_const.gd")

## 试验场房间尺寸（瓦片，含四周墙体一圈）
const ARENA_SIZE: Vector2i = Vector2i(29, 17)
## 玩家死亡后多久进入结算
const DEATH_TO_RESULT: float = 1.7
## 试验场演示波次：三类敌人各来一个，外加一个近战，方便一次看全行为差异
const DEMO_WAVE: Array = ["husk", "hexeye", "bloom", "husk"]
## 演示波次清空后多久刷下一波（0 表示不再刷）
const DEMO_RESPAWN_DELAY: float = 5.0

## 换房后玩家落脚点到门洞的距离（瓦片）
const DOOR_ENTRY_INSET: float = 1.6
## 换房后的门通行锁定时长（秒）：防止新房间的门立刻把玩家送回去
const DOOR_LOCKOUT: float = 0.3
## 换房时的短暂无敌，避免上一房残留实体造成接触伤害
const ROOM_ENTRY_PROTECTION: float = 0.6
## 障碍物候选（贴点名，RoomBuilder.add_obstacle 会自动补碰撞体）
const OBSTACLE_TEXTURES: Array[String] = ["crate", "barrel", "rock_0", "rock_1"]
const OBSTACLE_SIZES: Dictionary = {
	"crate": Vector2(22, 20),
	"barrel": Vector2(18, 18),
	"rock_0": Vector2(26, 22),
	"rock_1": Vector2(26, 22),
}
## 宝箱开出武器的概率
const CHEST_WEAPON_CHANCE: float = 0.22

var rng := RandomNumberGenerator.new()

# ---------- 图层 ----------
var world_root: Node2D      ## 房间容器（地牢模式下每房一间，换房时整棵释放）
var room_root: Node2D       ## 当前房间的地板 / 墙体 / 障碍 / 装饰
var entity_root: Node2D     ## 玩家 / 敌人 / 靶子 / 掉落（Y 排序）
var bullet_root: Node2D     ## 子弹 / 光束
var fx_root: Node2D         ## 特效 / 飘字

# ---------- 主要对象 ----------
var player: Player = null
var camera: CameraRig = null
var hud: HUD = null
var spawner: EnemySpawner = null

# ---------- 房间状态 ----------
var room: Dictionary = {}
var interior_rect: Rect2 = Rect2()
var dummies: Array = []

var arena_mode: bool = true
var finished: bool = false
## 试验场是否自动刷演示波次（测试里置 false，避免干扰玩家相关断言）
var auto_demo_wave: bool = true

# ---------- 地牢状态（M5） ----------
## true = 随机地牢模式（真机默认）；false = 旧试验场（自动化测试用）
var dungeon_mode: bool = false
## 当前层布局（rooms / neighbors / start_index / boss_index …）
var layout: DungeonLayout = null
## 当前房间下标；-1 表示还没进房
var current_room_index: int = -1
## 当前房间的门
var doors: Array = []
var portal: Portal = null
var floor_key: FloorKey = null
var chest: Chest = null
var shop_pad: ShopPad = null
var altar: Altar = null
## 本层已清空的房间数（起始房/商店房算已清空）
var rooms_cleared: int = 0
var boss_room_cleared: bool = false
## 玩家出生/进房落脚点
var _spawn_point: Vector2 = Vector2.ZERO
## 已激活波次的房间（防重复开波）
var _activated_room: int = -1
var _door_lockout: float = 0.0
var _key_toast_timer: float = 0.0

# ---------- 掉落分流（M6）：敌人死亡先入队，_process 在空闲时段再生成实体拾取物 ----------
## 队列元素：{"kind": int, "amount": float, "position": Vector2, "weapon": WeaponData, "talent": Dictionary}
var queued_drops: Array = []
## 当前房间在场的拾取物（换房时随房间一起清理）
var room_pickups: Array = []
var drop_stats: Dictionary = {}
var gold_from_drops: int = 0

var _death_timer: float = -1.0
var _demo_timer: float = -1.0
var _dev_weapon_cycle: int = 0


func _ready() -> void:
	_ensure_run()
	_build_layers()
	if dungeon_mode:
		arena_mode = false
		_start_floor(GameState.floor_index)
	elif arena_mode:
		_build_arena()
	_spawn_player()
	_setup_camera()
	_setup_hud()
	_connect_events()
	_setup_spawner()
	EventBus.run_started.emit(GameState.run_seed)
	EventBus.floor_started.emit(GameState.floor_index, GameState.run_seed)
	if dungeon_mode:
		_activate_current_room()
		_dungeon_intro_toast()
	else:
		_intro_toast()


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(delta: float) -> void:
	if _death_timer >= 0.0:
		_death_timer -= delta
		if _death_timer <= 0.0 and not finished:
			finished = true
			if player != null and is_instance_valid(player):
				player.snapshot_to_state()
			GameState.end_run(false)
	if _demo_timer >= 0.0:
		_demo_timer -= delta
		if _demo_timer <= 0.0:
			_demo_timer = -1.0
			if not finished and spawner != null:
				spawner.start_wave()
	if _door_lockout > 0.0:
		_door_lockout = maxf(0.0, _door_lockout - delta)
	if _key_toast_timer > 0.0:
		_key_toast_timer = maxf(0.0, _key_toast_timer - delta)
	if not queued_drops.is_empty():
		_process_drops()


## 调试快捷键：F5 补满资源，F6 轮换全部 8 把武器（便于手感验证）
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F5 or event.physical_keycode == KEY_F5:
		_dev_refill()
	elif event.keycode == KEY_F6 or event.physical_keycode == KEY_F6:
		_dev_cycle_weapon()


# ==================== 装配 ====================

func _ensure_run() -> void:
	if not GameState.run_active or GameState.stats.is_empty():
		GameState.new_run(0)
	rng.seed = GameState.run_seed


func _build_layers() -> void:
	world_root = Node2D.new()
	world_root.name = "WorldLayer"
	add_child(world_root)

	entity_root = Node2D.new()
	entity_root.name = "EntityLayer"
	entity_root.y_sort_enabled = true
	add_child(entity_root)

	bullet_root = Node2D.new()
	bullet_root.name = "BulletLayer"
	bullet_root.z_index = 8
	add_child(bullet_root)

	fx_root = Node2D.new()
	fx_root.name = "FxLayer"
	fx_root.z_index = 12
	add_child(fx_root)


func _spawn_player() -> void:
	# 武器在玩家创建前写入 GameState：Player._ready() 会直接接手这份列表，
	# 避免"起始手枪 + 试验三把"超出 3 个栏位而互相顶替。
	if dungeon_mode:
		# 地牢模式：读档继续时沿用存档里的武器；新开一局（new_run 已清空）
		# 发"武器图鉴初始武器 + 两把试验武器"，默认状况与原来的核心三把一致
		if GameState.weapons.is_empty():
			for weapon: Variant in WeaponDB.starter_kit(GameState.starter_kit_ids):
				GameState.add_weapon(weapon)
			GameState.weapon_index = 0
	else:
		GameState.weapons.clear()
		for weapon: Variant in WeaponDB.core_three():
			GameState.add_weapon(weapon)
		GameState.weapon_index = 0

	if _spawn_point == Vector2.ZERO:
		_spawn_point = _tile_position(ARENA_SIZE.x / 2, ARENA_SIZE.y - 3)

	player = Player.new()
	player.name = "Player"
	player.position = _spawn_point
	player.bullet_layer = bullet_root
	player.fx_layer = fx_root
	entity_root.add_child(player)
	# 出生保护：刚落地/刚进房时不会被贴脸伤害秒掉
	player.set_invulnerable(G.SPAWN_PROTECTION)
	# 炸弹的飞行范围跟着当前房间走（飞出这个矩形就落地起爆）
	player.throw_bounds = interior_rect


func _setup_camera() -> void:
	camera = CameraRig.new()
	camera.name = "CameraRig"
	add_child(camera)
	var room_size: Vector2i = room.get("size", ARENA_SIZE)
	var room_rect := Rect2(room.get("origin", Vector2.ZERO),
			Vector2(room_size) * float(G.TILE_SIZE))
	camera.set_bounds(room_rect)
	camera.set_target(player)
	camera.global_position = player.global_position


func _setup_hud() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(player, self)


func _setup_spawner() -> void:
	spawner = EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	var kind: int = G.RoomKind.COMBAT
	var seed_value: int = GameState.run_seed
	if dungeon_mode:
		kind = _current_room_kind()
		seed_value = _room_seed(current_room_index)
	spawner.setup(self, interior_rect, GameState.floor_index, kind, seed_value)
	spawner.wave_started.connect(_on_wave_started)
	spawner.wave_cleared.connect(_on_wave_cleared)
	if arena_mode and auto_demo_wave:
		# 延后一帧开波：等玩家节点进树，生成点才能正确避开玩家
		spawner.call_deferred("start_wave", DEMO_WAVE)


func _connect_events() -> void:
	if not EventBus.damage_number_requested.is_connected(_on_damage_number_requested):
		EventBus.damage_number_requested.connect(_on_damage_number_requested)
	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)
	if not EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.connect(_on_enemy_died)
	if not EventBus.enemy_dropped.is_connected(_on_enemy_dropped):
		EventBus.enemy_dropped.connect(_on_enemy_dropped)
	if not EventBus.weapon_dropped.is_connected(_on_weapon_dropped):
		EventBus.weapon_dropped.connect(_on_weapon_dropped)


func _on_weapon_dropped(weapon: WeaponData, at_position: Vector2) -> void:
	if weapon == null:
		return
	var drop: Pickup = spawn_pickup(G.PickupKind.WEAPON, 1.0, at_position)
	drop.weapon = weapon


func _intro_toast() -> void:
	if hud == null:
		return
	hud.show_toast("战斗试验场 · WASD 移动 / 鼠标瞄准射击 / Shift 冲刺 / Space 技能 / 1-3 切枪", 4.0)
	hud.call_deferred("show_toast", "F5 补满资源 · F6 轮换全部武器 · Esc 暂停", 4.0)


# ==================== 试验场 ====================

func _build_arena() -> void:
	var obstacles: Array = []
	for cell: Vector2i in [Vector2i(6, 4), Vector2i(22, 4), Vector2i(6, 12), Vector2i(22, 12)]:
		obstacles.append({
			"texture": "crate", "position": _tile_position(cell.x, cell.y), "size": Vector2(22, 20),
		})
	for cell: Vector2i in [Vector2i(10, 8), Vector2i(18, 8)]:
		obstacles.append({
			"texture": "barrel", "position": _tile_position(cell.x, cell.y), "size": Vector2(18, 18),
		})
	obstacles.append({
		"texture": "rock_0", "position": _tile_position(14, 6), "size": Vector2(26, 22),
	})

	room = RoomBuilder.build(world_root, {
		"size": ARENA_SIZE,
		"origin": Vector2.ZERO,
		"rng": rng,
		"walls": true,
		"carpet": true,
		"obstacles": obstacles,
	})
	interior_rect = room.get("interior_rect", Rect2())
	_spawn_point = _tile_position(ARENA_SIZE.x / 2, ARENA_SIZE.y - 3)

	# 墙上火把（画在墙体之上）
	for cell: Vector2i in [Vector2i(4, 0), Vector2i(24, 0), Vector2i(0, 5), Vector2i(28, 5),
			Vector2i(0, 11), Vector2i(28, 11), Vector2i(4, 16), Vector2i(24, 16)]:
		var torch: Node2D = RoomBuilder.add_decoration(world_root, "torch",
				_tile_position(cell.x, cell.y) + Vector2(0, 6), 4, 9.0)
		torch.z_index = 6
	# 火盆与晶簇（房间内部）
	for cell: Vector2i in [Vector2i(9, 3), Vector2i(19, 3)]:
		RoomBuilder.add_decoration(world_root, "brazier", _tile_position(cell.x, cell.y), 4, 10.0)
	for cell: Vector2i in [Vector2i(3, 8), Vector2i(25, 8)]:
		RoomBuilder.add_decoration(world_root, "crystal", _tile_position(cell.x, cell.y), 3, 5.0)

	_spawn_dummies()


func _spawn_dummies() -> void:
	dummies.clear()
	for cell: Vector2i in [Vector2i(9, 6), Vector2i(14, 9), Vector2i(19, 6)]:
		var dummy := TrainingDummy.new()
		dummy.position = _tile_position(cell.x, cell.y)
		dummy.auto_respawn = true
		entity_root.add_child(dummy)
		dummies.append(dummy)


## 瓦片坐标 -> 世界坐标（瓦片中心）
func _tile_position(tx: int, ty: int) -> Vector2:
	var origin: Vector2 = room.get("origin", Vector2.ZERO)
	return origin + Vector2((float(tx) + 0.5) * float(G.TILE_SIZE), (float(ty) + 0.5) * float(G.TILE_SIZE))


# ==================== 全局事件 ====================

func _on_damage_number_requested(world_position: Vector2, amount: float, is_crit: bool, is_player_damage: bool) -> void:
	if amount <= 0.0:
		return
	var number := DamageNumber.new()
	number.setup(amount, is_crit, is_player_damage)
	number.position = world_position
	fx_root.add_child(number)


func _on_player_died() -> void:
	if _death_timer >= 0.0:
		return
	_death_timer = DEATH_TO_RESULT
	if hud != null:
		hud.show_toast("你被晶窟吞没了……", 2.0)


func _on_enemy_died(enemy: Node, world_position: Vector2) -> void:
	Fx.play(fx_root, "spark", world_position + Vector2(0, -4), {"fps": 22.0, "scale": 1.0, "z_index": 13})
	if enemy is Enemy:
		# 正式敌人的奖励走掉落表（见 _on_enemy_dropped），这里不再给固定金币
		return
	# M3 的试验靶：给一点金币反馈
	GameState.add_gold(3)


## 掉落分流：敌人死亡回调处在物理帧里，直接建碰撞体不安全，所以只入队；
## 具体内容（武器实例 / 天赋条目）在入队时就用房间 RNG 摇好，保证同一种子可复现。
func _on_enemy_dropped(_enemy: Node, world_position: Vector2, drops: Array) -> void:
	for drop: Variant in drops:
		if not (drop is Dictionary):
			continue
		var payload: Dictionary = (drop as Dictionary).duplicate()
		var kind: int = int(payload.get("kind", G.PickupKind.COIN))
		var amount: float = float(payload.get("amount", 1.0))
		drop_stats[kind] = int(drop_stats.get(kind, 0)) + 1
		if kind == G.PickupKind.COIN:
			amount = float(maxi(1, int(amount)))
		elif kind == G.PickupKind.HEALTH and amount <= 0.0:
			amount = Pickup.default_amount(kind)
		elif kind == G.PickupKind.ENERGY and amount <= 0.0:
			amount = Pickup.default_amount(kind)
		payload["kind"] = kind
		payload["amount"] = amount
		payload["position"] = world_position
		if kind == G.PickupKind.WEAPON and payload.get("weapon", null) == null:
			payload["weapon"] = WeaponDB.random(_drop_rng(world_position, 1717), GameState.floor_index)
		elif kind == G.PickupKind.TALENT and payload.get("talent", null) == null:
			payload["talent"] = _roll_talent(_drop_rng(world_position, 4242))
		queued_drops.append(payload)


## 掉落摇奖用的独立 RNG：房间索引 + 掉落点抖动，同一种子同一点必然同样结果
func _drop_rng(world_position: Vector2, salt: int) -> RandomNumberGenerator:
	var jitter: int = absi(int(world_position.x * 0.37 + world_position.y * 0.91))
	return _room_rng(current_room_index + salt + jitter)


## 随机天赋：排除玩家当前已生效的，避免"捡了个重复的只是续时间"
func _roll_talent(r: RandomNumberGenerator) -> Dictionary:
	var exclude: Array = []
	for entry: Dictionary in GameState.talents:
		exclude.append(str(entry.get("id", "")))
	return TalentDB.random(r, exclude)


## 队列 -> 实体拾取物（在非物理回调的 _process 里执行，可以安全建碰撞体）
func _process_drops() -> void:
	if queued_drops.is_empty():
		return
	var pending: Array = queued_drops.duplicate()
	queued_drops.clear()
	for entry: Variant in pending:
		if not (entry is Dictionary):
			continue
		var payload: Dictionary = entry
		var options: Dictionary = {
			"weapon": payload.get("weapon", null),
			"talent": payload.get("talent", {}),
			"scatter_direction": Vector2.RIGHT.rotated(rng.randf() * TAU),
			"scatter_speed": rng.randf_range(0.6, 1.0) * G.PICKUP_SCATTER_SPEED,
		}
		spawn_pickup(int(payload.get("kind", G.PickupKind.COIN)),
				float(payload.get("amount", 1.0)),
				payload.get("position", _spawn_point), options)


## 生成一个实体拾取物（敌人掉落、宝箱、祭坛、测试都走这里）
func spawn_pickup(kind: int, amount: float, at_position: Vector2, options: Dictionary = {}) -> Pickup:
	var pickup := Pickup.new()
	var merged: Dictionary = options.duplicate()
	merged["bounds"] = interior_rect
	merged["fx_layer"] = fx_root
	merged["player"] = player
	merged["room"] = current_room_index
	if not merged.has("scatter_direction"):
		merged["scatter_direction"] = Vector2.RIGHT.rotated(rng.randf() * TAU)
	pickup.position = _clamped_drop_position(at_position)
	pickup.configure(kind, amount, merged)
	entity_root.add_child(pickup)
	pickup.collected.connect(_on_pickup_collected)
	pickup.expired.connect(_on_pickup_expired)
	room_pickups.append(pickup)
	return pickup


## 把掉落点收进房间可走范围（贴着墙掉的金币不会被撒到墙里捡不到）
func _clamped_drop_position(at_position: Vector2) -> Vector2:
	if interior_rect.size.x <= 0.0 or interior_rect.size.y <= 0.0:
		return at_position
	var margin := Vector2(7, 7)
	var inner := Rect2(interior_rect.position + margin, interior_rect.size - margin * 2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return at_position
	return Vector2(clampf(at_position.x, inner.position.x, inner.end.x),
			clampf(at_position.y, inner.position.y, inner.end.y))


## 拾取结算后的表现层：飘字、金币统计、关键道具提示
func _on_pickup_collected(pickup: Pickup, result: Dictionary) -> void:
	if pickup != null:
		room_pickups.erase(pickup)
	var gold: int = int(result.get("gold", 0))
	if gold > 0:
		gold_from_drops += gold
	var anchor: Vector2 = (pickup.global_position + Vector2(0, -14)) if pickup != null else _spawn_point
	var text: String = str(result.get("text", ""))
	if text != "":
		spawn_popup(text, result.get("color", Color.WHITE), anchor,
				int(result.get("kind", -1)) == G.PickupKind.TALENT
				or int(result.get("kind", -1)) == G.PickupKind.WEAPON)
	match int(result.get("kind", -1)):
		G.PickupKind.WEAPON:
			_toast("拾取 %s · 滚轮或 1/2/3 切换" % str(result.get("weapon_name", "")), 2.4)
		G.PickupKind.TALENT:
			_toast("天赋生效：%s · 限时增益" % str(result.get("talent_name", "")), 2.4)
		G.PickupKind.BOMB:
			_toast("炸弹补给 · 按 F 投掷", 1.8)


func _on_pickup_expired(pickup: Pickup) -> void:
	if pickup != null:
		room_pickups.erase(pickup)


## 世界坐标里的文字飘字（复用 DamageNumber 的上浮淡出，只是换成带颜色的短文字）
func spawn_popup(text: String, color: Color, world_position: Vector2, big: bool = false) -> DamageNumber:
	var popup := DamageNumber.new()
	popup.setup_text(text, color, big)
	popup.position = world_position
	fx_root.add_child(popup)
	return popup


## 当前房间在场的拾取物数量（测试 / 调试）
func pickup_count() -> int:
	var alive: int = 0
	for entry: Variant in room_pickups:
		if entry != null and is_instance_valid(entry):
			alive += 1
	return alive


func _on_wave_started(ids: Array) -> void:
	if hud != null:
		hud.show_toast("敌人出现 ×%d" % ids.size(), 1.6)


func _on_wave_cleared() -> void:
	if dungeon_mode:
		# 地牢：清怪 → 标记房间清空 → 开门（Boss 房还会开传送门）
		_mark_room_cleared()
		return
	if hud != null:
		hud.show_toast("区域已清空", 1.8)
	AudioMgr.play_sfx("pickup_talent", 0.0, -8.0)
	EventBus.room_cleared.emit(null)
	if arena_mode and auto_demo_wave and not finished and DEMO_RESPAWN_DELAY > 0.0:
		_demo_timer = DEMO_RESPAWN_DELAY


# ==================== 对外接口（测试 / 后续里程碑） ====================

func dummy_at(index: int) -> TrainingDummy:
	if index < 0 or index >= dummies.size():
		return null
	return dummies[index]


func alive_enemy_count() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(CombatUtil.GROUP_ENEMIES):
		if is_instance_valid(node) and not (node.has_method("is_dead_or_disabled") and bool(node.call("is_dead_or_disabled"))):
			count += 1
	return count


func bullet_count() -> int:
	return bullet_root.get_child_count()


## 投放一波敌人（ids 为空则按房型/层数自动规划）
func spawn_wave(ids: Array = []) -> Array:
	if spawner == null:
		return []
	return spawner.start_wave(ids)


## 生成单个敌人（测试与 Boss 房小怪共用）
func spawn_enemy(enemy_id: String, at_position: Variant = null) -> Enemy:
	if spawner == null:
		return null
	return spawner.spawn_enemy(enemy_id, at_position)


## 清空实体层（换房间 / 重开时用），保留玩家
func clear_entities(keep_player: bool = true) -> void:
	if spawner != null:
		spawner.despawn_all()
	for child: Node in entity_root.get_children():
		if keep_player and child == player:
			continue
		child.queue_free()
	for child: Node in bullet_root.get_children():
		child.queue_free()


# ==================== 开发辅助 ====================

func _dev_refill() -> void:
	if player == null:
		return
	player.stats["health"] = player.max_health()
	player.stats["shield"] = player.max_shield()
	player.stats["energy"] = player.max_energy()
	player.clear_invulnerable()
	player.dead = false
	player.heal(0.0)
	_death_timer = -1.0
	if hud != null:
		hud.show_toast("资源已补满", 1.4)
	AudioMgr.play_sfx("pickup_heart", 0.0, -6.0)


func _dev_cycle_weapon() -> void:
	if player == null:
		return
	var ids: Array = WeaponDB.ids()
	if ids.is_empty():
		return
	var weapon_id: String = str(ids[_dev_weapon_cycle % ids.size()])
	_dev_weapon_cycle += 1
	var weapon: WeaponData = WeaponDB.create(weapon_id)
	player.add_weapon(weapon)
	if hud != null:
		hud.show_toast("试验武器：%s（%s）" % [weapon.display_name, weapon_id], 1.8)


# ==================== 地牢：层与房间（M5） ====================

## 开始某一层：生成布局并进起始房
func _start_floor(floor_index: int) -> void:
	layout = DungeonLayout.generate(_floor_rng(floor_index), floor_index)
	current_room_index = -1
	rooms_cleared = 0
	boss_room_cleared = false
	_activated_room = -1
	_enter_room(layout.start_index, -1)


## 每层一个确定性随机流：同一层永远生成同一张地图（读档/测试可复现）
func _floor_rng(floor_index: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = GameState.floor_seed(floor_index)
	return r


## 房间内容（障碍布局、宝箱奖励）用的独立随机流
func _room_rng(index: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = GameState.floor_seed() + index * 7919 + 13
	return r


func _room_seed(index: int) -> int:
	return GameState.floor_seed() + index * 104729 + 7


func _current_room_kind() -> int:
	if layout == null:
		return G.RoomKind.COMBAT
	var data: Dictionary = layout.room(current_room_index)
	if data.is_empty():
		return G.RoomKind.COMBAT
	return int(data.get("kind", G.RoomKind.COMBAT))


## 进入某个房间：拆旧房 -> 建新房 -> 放门与道具 -> 摆放玩家 -> 同步相机 -> 开波
## from_dir：玩家是从新房的哪个方向进来的（-1 = 直接落在房间中央）
func _enter_room(index: int, from_dir: int = -1) -> void:
	if layout == null:
		return
	var data: Dictionary = layout.room(index)
	if data.is_empty():
		return
	current_room_index = index
	data["visited"] = true
	_activated_room = -1
	_teardown_room()

	var kind: int = int(data["kind"])
	room = RoomBuilder.build(_new_room_root(), {
		"size": data["size"],
		"origin": Vector2.ZERO,
		"rng": _room_rng(index),
		"walls": true,
		"carpet": kind == G.RoomKind.START or kind == G.RoomKind.BOSS,
		"obstacles": _room_obstacles(data),
		"doors": layout.door_dirs(index),
	})
	interior_rect = room.get("interior_rect", Rect2())

	_decorate_room(data)
	_build_doors(data)
	_build_room_props(data)
	_place_player(from_dir)
	_sync_camera(true)
	_door_lockout = DOOR_LOCKOUT

	if spawner != null:
		spawner.setup(self, interior_rect, GameState.floor_index, kind, _room_seed(index))
		_activate_current_room()

	EventBus.room_entered.emit(self)
	_toast(_room_title(kind), 1.8)


## 拆掉上一间房：先静默碰撞与监听，再 queue_free，避免同帧新旧房间互相干扰
func _teardown_room() -> void:
	if room_root != null and is_instance_valid(room_root):
		_silence(room_root)
		room_root.queue_free()
	room_root = null
	if spawner != null:
		spawner.despawn_all()
	for child: Node in entity_root.get_children():
		if child == player:
			continue
		_silence(child)
		child.queue_free()
	for child: Node in bullet_root.get_children():
		child.queue_free()
	for child: Node in fx_root.get_children():
		child.queue_free()
	doors.clear()
	room_pickups.clear()
	portal = null
	floor_key = null
	chest = null
	shop_pad = null
	altar = null


## 递归关掉碰撞层与 Area 监听（节点仍会在帧末真正释放）
static func _silence(node: Node) -> void:
	if node is CollisionObject2D:
		var body: CollisionObject2D = node
		body.collision_layer = 0
		if body is Area2D:
			var area: Area2D = body
			# 拆房间常常发生在物理回调链里（撞门/踩传送门），必须延迟改监听状态
			area.set_deferred("monitoring", false)
			area.set_deferred("monitorable", false)
	for child: Node in node.get_children():
		_silence(child)


func _new_room_root() -> Node2D:
	room_root = Node2D.new()
	room_root.name = "Room"
	world_root.add_child(room_root)
	return room_root


## 战斗房放几个可破坏感的障碍；起始房/商店房/Boss 房保持空旷
func _room_obstacles(data: Dictionary) -> Array:
	var out: Array = []
	var kind: int = int(data["kind"])
	if kind == G.RoomKind.START or kind == G.RoomKind.SHOP or kind == G.RoomKind.BOSS:
		return out
	var size: Vector2i = data["size"]
	var r := _room_rng(int(data["index"]) + 991)
	var cx: int = size.x / 2
	var cy: int = size.y / 2
	var count: int = r.randi_range(2, 4)
	var tries: int = 0
	while out.size() < count and tries < 48:
		tries += 1
		var cell := Vector2i(r.randi_range(3, size.x - 4), r.randi_range(3, size.y - 4))
		# 中央落脚点与门口通道留空，避免玩家进房被堵死
		if absi(cell.x - cx) <= 2 and absi(cell.y - cy) <= 2:
			continue
		if _blocks_doorway(cell, size):
			continue
		var tex: String = OBSTACLE_TEXTURES[r.randi_range(0, OBSTACLE_TEXTURES.size() - 1)]
		out.append({
			"texture": tex,
			"position": _tile_position(cell.x, cell.y),
			"size": OBSTACLE_SIZES[tex],
		})
	return out


func _blocks_doorway(cell: Vector2i, size: Vector2i) -> bool:
	var cx: int = size.x / 2
	var cy: int = size.y / 2
	if (cell.x == cx or cell.x == cx - 1) and (cell.y <= 2 or cell.y >= size.y - 3):
		return true
	if (cell.y == cy or cell.y == cy - 1) and (cell.x <= 2 or cell.x >= size.x - 3):
		return true
	return false


## 墙上火把 + 房型专属装饰
func _decorate_room(data: Dictionary) -> void:
	var host: Node2D = room_root
	var size: Vector2i = data["size"]
	var kind: int = int(data["kind"])
	var torch_cells: Array = [
		Vector2i(2, 0), Vector2i(size.x - 3, 0),
		Vector2i(0, 2), Vector2i(size.x - 1, 2),
		Vector2i(0, size.y - 3), Vector2i(size.x - 1, size.y - 3),
		Vector2i(2, size.y - 1), Vector2i(size.x - 3, size.y - 1),
	]
	for cell_value: Variant in torch_cells:
		var cell: Vector2i = cell_value
		var torch: Node2D = RoomBuilder.add_decoration(host, "torch",
				_tile_position(cell.x, cell.y) + Vector2(0, 6), 4, 9.0)
		torch.z_index = 6
	if kind == G.RoomKind.START or kind == G.RoomKind.BOSS:
		for cell_value: Variant in [Vector2i(size.x / 2 - 4, size.y / 2), Vector2i(size.x / 2 + 4, size.y / 2)]:
			var cell: Vector2i = cell_value
			RoomBuilder.add_decoration(host, "brazier", _tile_position(cell.x, cell.y), 4, 10.0)
	if kind == G.RoomKind.TREASURE or kind == G.RoomKind.ELITE or kind == G.RoomKind.SHOP:
		RoomBuilder.add_decoration(host, "crystal", _tile_position(size.x / 2, 2), 3, 5.0)


## 按布局给当前房间挂门；Boss 门在没有精英房的层不锁（否则会死锁）
func _build_doors(data: Dictionary) -> void:
	doors.clear()
	var index: int = int(data["index"])
	var size: Vector2i = data["size"]
	var cleared: bool = bool(data.get("cleared", false))
	var key_room_exists: bool = layout != null and layout.elite_index >= 0
	for dir_value: int in layout.door_dirs(index):
		var target: int = layout.neighbor_in_direction(index, dir_value)
		if target < 0:
			continue
		var boss_door: bool = key_room_exists and layout.is_boss_door(index, dir_value)
		var door := Door.new()
		door.configure(dir_value, index, target, size, boss_door, cleared and not boss_door)
		room_root.add_child(door)
		door.door_used.connect(_on_door_used)
		door.door_blocked.connect(_on_door_blocked)
		doors.append(door)


## 房型专属物件：宝箱 / 商店垫 / 精英房钥匙 / Boss 房传送门
func _build_room_props(data: Dictionary) -> void:
	var kind: int = int(data["kind"])
	var size: Vector2i = data["size"]
	var center: Vector2 = _tile_position(size.x / 2, size.y / 2)
	match kind:
		G.RoomKind.START:
			# 起始房的许愿祭坛：花金币换天赋或炸弹，每层只开两次
			altar = Altar.new()
			altar.name = "Altar"
			altar.position = center + Vector2(0, -30)
			altar.rng = _room_rng(int(data["index"]) + 911)
			if data.has("altar_uses"):
				altar.uses_left = clampi(int(data["altar_uses"]), 0, G.ALTAR_USE_LIMIT)
			entity_root.add_child(altar)
			altar.purchased.connect(_on_altar_purchased.bind(data))
			altar.denied.connect(_on_altar_denied)
			altar.exhausted.connect(_on_altar_exhausted.bind(data))
		G.RoomKind.TREASURE:
			if bool(data.get("chest_taken", false)):
				return
			chest = Chest.new()
			chest.name = "Chest"
			entity_root.add_child(chest)
			chest.position = center + Vector2(0, -6)
			chest.reward = _roll_chest_reward(_room_rng(int(data["index"]) + 5501))
			chest.opened.connect(_on_chest_opened)
		G.RoomKind.SHOP:
			shop_pad = ShopPad.new()
			shop_pad.name = "ShopPad"
			shop_pad.position = center
			# 库存要在 add_child 之前塞好：ShopPad._ready 只在空库存时铺默认商品
			if data.has("shop_stock"):
				shop_pad.stock = data["shop_stock"]
				shop_pad.cursor = clampi(int(data.get("shop_cursor", 0)), 0, maxi(0, shop_pad.stock.size() - 1))
			entity_root.add_child(shop_pad)
			# 武器货架在 _ready 之后补充；只在首次进入这家店时上架，
			# 并立即写回房间数据，防止反复进出导致武器越摆越多
			if not data.has("shop_stock"):
				shop_pad.restock_weapons(_room_rng(current_room_index + 9999), GameState.floor_index)
				data["shop_stock"] = shop_pad.stock.duplicate(true)
				data["shop_cursor"] = 0
			shop_pad.purchased.connect(_on_shop_purchased)
			shop_pad.denied.connect(_on_shop_denied)
			shop_pad.stock_changed.connect(_on_shop_stock_changed.bind(data))
			# 柜台：商店垫后面摆一座祭坛，读作摊位
			RoomBuilder.add_decoration(room_root, "altar", center + Vector2(0, -34), 4, 8.0)
		G.RoomKind.ELITE:
			# 清空后掉钥匙；如果玩家没捡就走出房间，回来时钥匙还在
			if bool(data.get("cleared", false)) and not bool(data.get("key_taken", false)):
				_spawn_floor_key(center)
		G.RoomKind.BOSS:
			if bool(data.get("cleared", false)):
				_spawn_portal(center, false)


func _roll_chest_reward(r: RandomNumberGenerator) -> Dictionary:
	if r.randf() < CHEST_WEAPON_CHANCE:
		return {"kind": "weapon", "amount": 0.0, "label": "武器"}
	var roll: float = r.randf()
	if roll < 0.45:
		var gold: int = r.randi_range(18, 34) + (GameState.floor_index - 1) * 8
		return {"kind": "gold", "amount": float(gold), "label": "金币"}
	if roll < 0.75:
		return {"kind": "heal", "amount": 40.0, "label": "治疗"}
	return {"kind": "energy", "amount": 60.0, "label": "能量"}


## 开波 / 开门的核心：进房后决定这间房要不要打
func _activate_current_room() -> void:
	if not dungeon_mode or spawner == null or layout == null:
		return
	var data: Dictionary = layout.room(current_room_index)
	if data.is_empty() or _activated_room == current_room_index:
		return
	_activated_room = current_room_index
	if bool(data.get("cleared", false)):
		_set_doors_open(true)
		return
	var kind: int = int(data["kind"])
	match kind:
		G.RoomKind.START, G.RoomKind.SHOP:
			# 安全房：不出怪，直接算清空并开门
			_mark_room_cleared(true)
		G.RoomKind.BOSS:
			var boss_ids: Array = _boss_wave_ids()
			if boss_ids.is_empty():
				# M8 接入点：Boss 实体还没做时，Boss 房直接判清空并放出传送门
				_mark_room_cleared(true)
			else:
				_set_doors_open(false)
				spawner.start_wave(boss_ids)
		_:
			_set_doors_open(false)
			spawner.start_wave()


## M7：本层 Boss 房投放的敌人 id（按层数轮换 Boss，终极层出收割者）
func _boss_wave_ids() -> Array:
	match GameState.floor_index:
		2:
			return ["weaver"]
		3:
			return ["warden", "weaver"]
		4:
			return ["reaper"]
		_:
			return ["warden"]


## 标记当前房间清空：开门 + 按房型给奖励（精英掉钥匙，Boss 开传送门）
func _mark_room_cleared(quiet: bool = false) -> void:
	if layout == null:
		return
	var data: Dictionary = layout.room(current_room_index)
	if data.is_empty() or bool(data.get("cleared", false)):
		return
	data["cleared"] = true
	rooms_cleared += 1
	_set_doors_open(true)
	EventBus.room_cleared.emit(self)
	match int(data["kind"]):
		G.RoomKind.ELITE:
			_spawn_floor_key(room.get("center", _spawn_point))
			_toast("精英已倒下 · 掉出了地牢钥匙")
			AudioMgr.play_sfx("level_clear", 0.0, -8.0)
		G.RoomKind.BOSS:
			boss_room_cleared = true
			EventBus.floor_cleared.emit(GameState.floor_index)
			_spawn_portal(room.get("center", _spawn_point), true)
			AudioMgr.play_sfx("level_clear", 0.0, -6.0)
		_:
			if not quiet:
				_toast("房间已清空 · 门开了")
				AudioMgr.play_sfx("door_open", 0.0, -12.0)


func _set_doors_open(value: bool) -> void:
	for entry: Variant in doors:
		if not is_instance_valid(entry):
			continue
		var door: Door = entry
		if value and door.is_locked():
			continue  # Boss 门要钥匙，不随清怪自动开
		door.set_open(value)
	if not value and not doors.is_empty():
		AudioMgr.play_sfx("door_locked", 0.22, -15.0)
	EventBus.doors_state_changed.emit(self, value)


func _spawn_floor_key(at_position: Vector2) -> void:
	if floor_key != null and is_instance_valid(floor_key):
		return
	floor_key = FloorKey.new()
	floor_key.name = "FloorKey"
	# 必须在 add_child 之前定位：FloorKey._ready 会把当前位置记成浮动基准点
	floor_key.position = at_position
	entity_root.add_child(floor_key)
	floor_key.collected.connect(_on_key_collected)


func _spawn_portal(at_position: Vector2, announce: bool = true) -> void:
	if portal != null and is_instance_valid(portal):
		return
	portal = Portal.new()
	portal.name = "Portal"
	portal.position = at_position
	entity_root.add_child(portal)
	portal.activate(GameState.floor_index + 1)
	portal.used.connect(_on_portal_used)
	EventBus.portal_activated.emit(portal)
	if announce:
		_toast("传送门开启 · 踩上去进入下一层", 2.6)


## 玩家落脚点：从哪个门进来就站在哪个门内侧
func _place_player(from_dir: int) -> void:
	var size: Vector2i = room.get("size", ARENA_SIZE)
	_spawn_point = room.get("center", _spawn_point)
	if from_dir >= 0:
		_spawn_point = RoomBuilder.door_entry_point(size, from_dir, Vector2.ZERO, DOOR_ENTRY_INSET)
	if player == null or not is_instance_valid(player):
		return
	player.position = _spawn_point
	player.velocity = Vector2.ZERO
	player.set_invulnerable(maxf(G.SPAWN_PROTECTION, ROOM_ENTRY_PROTECTION))
	# 炸弹的飞行范围跟着房间走
	player.throw_bounds = interior_rect


func _sync_camera(snap: bool = false) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var size: Vector2i = room.get("size", ARENA_SIZE)
	camera.set_bounds(Rect2(room.get("origin", Vector2.ZERO), Vector2(size) * float(G.TILE_SIZE)))
	if snap and player != null and is_instance_valid(player):
		camera.global_position = player.global_position


## 换层：写回快照 -> 推进层数（含 25% 回血与满盾满能）-> 生成新层 -> 同步玩家
func _advance_floor() -> void:
	if finished:
		return
	if player != null and is_instance_valid(player):
		player.snapshot_to_state()
	if not GameState.advance_floor():
		# 最后一层的 Boss 房也清空了 = 通关
		finished = true
		GameState.save_current_run()
		GameState.end_run(true)
		return
	GameState.save_current_run()
	_start_floor(GameState.floor_index)
	if player != null and is_instance_valid(player):
		player.restore_from_state()
	AudioMgr.play_bgm("dungeon_%d" % clampi(GameState.floor_index, 1, G.TOTAL_FLOORS))
	AudioMgr.play_sfx("level_start", 0.0, -6.0)
	EventBus.floor_started.emit(GameState.floor_index, GameState.floor_seed())
	_toast("进入第 %d 层 · 敌人更强了" % GameState.floor_index, 2.6)


func _room_title(kind: int) -> String:
	match kind:
		G.RoomKind.START:
			return "起始房 · 安全"
		G.RoomKind.COMBAT:
			return "战斗房"
		G.RoomKind.ELITE:
			return "精英房 · 清空可拿到地牢钥匙"
		G.RoomKind.TREASURE:
			return "宝箱房 · 按 E 开箱"
		G.RoomKind.SHOP:
			return "商店房 · 按 E 购买"
		G.RoomKind.BOSS:
			return "Boss 房"
	return "房间"


func _dungeon_intro_toast() -> void:
	if hud == null:
		return
	hud.show_toast("第 %d 层 · 清怪开门，精英房掉钥匙，钥匙开 Boss 门" % GameState.floor_index, 4.0)
	hud.call_deferred("show_toast", "WASD 移动 / 鼠标射击 / Shift 冲刺 / Space 技能 / F 炸弹 / E 交互 / Esc 暂停", 4.0)


func _toast(text: String, duration: float = 2.2) -> void:
	if hud != null:
		hud.show_toast(text, duration)


# ---------- 地牢交互回调 ----------

func _on_door_used(door: Door) -> void:
	if finished or _door_lockout > 0.0:
		return
	if door == null or not is_instance_valid(door):
		return
	# 换房要拆旧房、建新房的碰撞体，不能停在物理回调里做
	# （引擎会拦下 shape.disabled 与 monitoring 的改动），推到本帧空闲时段执行。
	_door_lockout = DOOR_LOCKOUT
	call_deferred("_enter_room", door.target_index, DungeonLayout.opposite_dir(door.dir))


func _on_door_blocked(door: Door) -> void:
	if finished:
		return
	if door == null or not is_instance_valid(door):
		return
	# 有钥匙时不受提示冷却限制，否则刚听完"门锁着"捡到钥匙却要再等一秒
	if GameState.has_floor_key:
		_key_toast_timer = 1.6
		GameState.set_floor_key(false)
		AudioMgr.play_sfx("door_open", -0.1, -6.0)
		_toast("用掉地牢钥匙 · Boss 房门打开了")
		# 开门 + 换房都要动碰撞体，同样推到空闲时段
		_door_lockout = DOOR_LOCKOUT
		call_deferred("_unlock_boss_door", door)
		return
	if _key_toast_timer > 0.0:
		return
	_key_toast_timer = 1.6
	AudioMgr.play_sfx("door_locked", 0.0, -6.0)
	_toast("Boss 门被锁住了 · 钥匙在本层的精英房里", 2.6)


func _on_key_collected(key: FloorKey) -> void:
	GameState.set_floor_key(true)
	AudioMgr.play_sfx("pickup_talent", 0.0, -6.0)
	_toast("拿到地牢钥匙 · 去开 Boss 房门", 3.0)
	if key != null and is_instance_valid(key):
		Fx.play(fx_root, "level_ring", key.global_position + Vector2(0, -6),
				{"fps": 14.0, "scale": 0.75, "z_index": 13})
	var data: Dictionary = layout.room(current_room_index) if layout != null else {}
	if not data.is_empty():
		data["key_taken"] = true
	floor_key = null


func _on_portal_used(_portal: Portal) -> void:
	# 换层同样要重建整层碰撞体，不能在物理回调里直接做
	call_deferred("_advance_floor")


## 用钥匙开 Boss 门并走进去（由 _on_door_blocked 延迟调用）
func _unlock_boss_door(door: Door) -> void:
	if finished or door == null or not is_instance_valid(door):
		return
	door.open_with_key()
	_door_lockout = 0.0
	_enter_room(door.target_index, DungeonLayout.opposite_dir(door.dir))


func _on_chest_opened(source: Chest) -> void:
	var data: Dictionary = layout.room(current_room_index) if layout != null else {}
	if not data.is_empty():
		data["chest_taken"] = true
	var reward: Dictionary = source.reward if source != null else {}
	var amount: float = float(reward.get("amount", 0.0))
	match str(reward.get("kind", "gold")):
		"gold":
			var gold: int = maxi(1, int(amount))
			GameState.add_gold(gold)
			AudioMgr.play_sfx("pickup_coin", 0.0, -8.0)
			_toast("宝箱：金币 ×%d" % gold)
		"heal":
			if player != null and is_instance_valid(player):
				player.heal(amount)
			AudioMgr.play_sfx("pickup_heart", 0.0, -8.0)
			_toast("宝箱：治疗 +%d" % int(amount))
		"energy":
			if player != null and is_instance_valid(player):
				player.add_energy(amount)
			AudioMgr.play_sfx("pickup_energy", 0.0, -8.0)
			_toast("宝箱：能量 +%d" % int(amount))
		"weapon":
			var weapon: WeaponData = WeaponDB.random(_room_rng(current_room_index + 313), GameState.floor_index)
			if player != null and is_instance_valid(player) and weapon != null:
				player.add_weapon(weapon)
				_toast("宝箱：获得 %s" % weapon.display_name)
	if source != null and is_instance_valid(source):
		Fx.play(fx_root, "level_ring", source.global_position + Vector2(0, -8),
				{"fps": 14.0, "scale": 0.8, "z_index": 13})


func _on_shop_purchased(_pad: ShopPad, offer: Dictionary) -> void:
	var label: String = str(offer.get("label", "商品"))
	match str(offer.get("id", "")):
		"heal":
			if player != null:
				player.heal(45.0)
		"shield":
			if player != null:
				player.add_shield(player.max_shield())
		"energy":
			if player != null:
				player.add_energy(player.max_energy())
		"weapon", "weapon_specific":
			var weapon: WeaponData = offer.get("weapon_data") as WeaponData
			if weapon == null:
				weapon = WeaponDB.random(_room_rng(current_room_index + 7717), GameState.floor_index)
			if player != null and weapon != null:
				player.add_weapon(weapon)
				label = weapon.display_name
		"talent":
			# 商店天赋走"买定离手"：当场生效，不生成拾取物
			var entry: Dictionary = _roll_talent(_room_rng(current_room_index + 5150))
			if entry.is_empty():
				_toast("天赋已售罄", 1.6)
				return
			_grant_talent(entry, _shop_center())
			label = str(entry.get("display_name", "天赋"))
		"bomb":
			var added: int = GameState.add_bombs(int(offer.get("amount", 2)))
			_toast("购入：炸弹 x%d · 按 F 投掷" % added)
			if player != null:
				spawn_popup("+%d 炸弹" % added, Color(1.0, 0.62, 0.44), _shop_center(), true)
			return
	_toast("购入：%s" % label)


func _on_shop_denied(_pad: ShopPad, _offer: Dictionary) -> void:
	_toast("金币不够 · 先清几间房攒钱", 1.6)


## 商店库存写回房间数据：玩家走出再回来，买过的一次性商品不会复活
func _on_shop_stock_changed(_pad: ShopPad, stock: Array, data: Dictionary) -> void:
	data["shop_stock"] = stock
	data["shop_cursor"] = _pad.cursor if _pad != null else 0


# ==================== 祭坛（起始房许愿台） ====================

## 祭坛成交：世界层负责结算效果，祭坛自己只管扣钱与限次
func _on_altar_purchased(_altar: Altar, offer: Dictionary, data: Dictionary) -> void:
	data["altar_uses"] = _altar.remaining_uses() if _altar != null else 0
	var at: Vector2 = _altar.global_position if (_altar != null and is_instance_valid(_altar)) else _spawn_point
	match str(offer.get("id", "")):
		"talent":
			var entry: Dictionary = _roll_talent(_room_rng(current_room_index + 991))
			if entry.is_empty():
				GameState.add_gold(int(offer.get("price", G.ALTAR_TALENT_PRICE)))
				_toast("祭坛沉默了 · 金币已退回", 1.8)
				return
			_grant_talent(entry, at)
			_toast("祭坛赐予：%s" % str(entry.get("display_name", "天赋")), 2.2)
		"bomb":
			var added: int = GameState.add_bombs(int(offer.get("amount", 2)))
			AudioMgr.play_sfx("pickup_weapon", 0.0, -7.0)
			spawn_popup("+%d 炸弹" % added, Color(1.0, 0.62, 0.44), at, true)
			_toast("祭坛赐予：炸弹 x%d · 按 F 投掷" % added, 2.0)


func _on_altar_denied(_altar: Altar, _offer: Dictionary) -> void:
	_toast("金币不够 · 祭坛只收现钱", 1.6)


## 许愿次数用完：写回房间数据，走出再回来祭坛仍是熄灭状态
func _on_altar_exhausted(_altar: Altar, data: Dictionary) -> void:
	data["altar_uses"] = 0
	_toast("祭坛的火焰熄灭了", 1.8)


## 天赋生效的统一入口：拾取物之外的来源（商店 / 祭坛）也走这里，表现一致
func _grant_talent(entry: Dictionary, at: Vector2) -> void:
	GameState.add_talent(entry)
	AudioMgr.play_sfx("pickup_talent", 0.0, -6.0)
	Fx.play(fx_root, "level_ring", at + Vector2(0, -10), {"fps": 15.0, "scale": 0.9, "z_index": 13})
	spawn_popup("天赋 · %s" % str(entry.get("display_name", "")), Color(0.86, 0.68, 1.0),
			at + Vector2(0, -22), true)


func _shop_center() -> Vector2:
	if shop_pad != null and is_instance_valid(shop_pad):
		return shop_pad.global_position + Vector2(0, -14)
	return _spawn_point


# ==================== 地牢对外接口（测试 / 后续里程碑） ====================

## 当前房型
func current_room_kind() -> int:
	return _current_room_kind()


## 当前（或指定）房间的布局数据
func room_data(index: int = -1) -> Dictionary:
	if layout == null:
		return {}
	return layout.room(index if index >= 0 else current_room_index)


## 当前房间开着的门数量
func open_door_count() -> int:
	var count: int = 0
	for entry: Variant in doors:
		if is_instance_valid(entry) and (entry as Door).is_open:
			count += 1
	return count


## 测试/调试用：直接切到某个房间
func goto_room(index: int) -> void:
	_enter_room(index, -1)


## 测试/调试用：立刻清空当前房间（等价于把怪全杀光）
func clear_current_room() -> void:
	if spawner != null:
		spawner.kill_all()
	_mark_room_cleared()


## 测试/调试用：立刻换层
func advance_floor_now() -> void:
	_advance_floor()
