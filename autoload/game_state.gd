extends Node
## GameState —— 全局运行期状态（Autoload）。
##
## 负责三件事：
##   1. 一局游戏（run）的跨场景/跨楼层状态：层数、金币、武器列表、临时天赋、玩家属性快照；
##   2. 设置项（音量、全屏、屏幕抖动等）并落地到 SaveMgr；
##   3. 元进度（最佳层数、总局数）。
##
## 注意：战斗中的"实时"血量/能量由 Player 节点持有并广播事件；
## 这里保存的是跨楼层延续的属性快照，换层时通过 snapshot_stats / apply_stats 同步。

const G := preload("res://scripts/core/game_const.gd")

signal gold_changed(total: int)
signal weapons_changed(weapons: Array)
signal talents_changed(talents: Array)
signal bombs_changed(count: int)
signal floor_changed(floor_index: int)
signal key_changed(has_key: bool)
signal settings_changed
## 角色切换
signal character_changed(character_id: String)
## 天赋树：allocated 的 node_id 为空字符串表示洗点
signal talent_allocated(character_id: String, node_id: String)
signal talent_points_changed(points: int)

# ---------- 一局游戏状态 ----------
var run_active: bool = false
var floor_index: int = 1
var run_seed: int = 0
var rng := RandomNumberGenerator.new()

var gold: int = 0
## 武器数据（WeaponData 资源）列表，最多 3 把
var weapons: Array = []
var weapon_index: int = 0
## 临时天赋实例列表：{id, display_name, duration, remain, modifiers, instant, description}
var talents: Array = []
## 可投掷炸弹数量（F 键投掷，敌人掉落 / 商店 / 祭坛补充）
var bombs: int = 0
## 玩家属性快照（跨楼层保留）
var stats: Dictionary = {}
## 本局战绩：击杀数 / 精英击杀 / 得分（敌人 score 累加，结算界面展示）
var kills: int = 0
var elite_kills: int = 0
var score: int = 0
## 本层「地牢钥匙」是否在手（精英房掉落，开 Boss 房门的前置条件；换层清空）
var has_floor_key: bool = false

# ---------- 元进度 / 设置 ----------
var best_floor: int = 0
var unlocked_floor: int = 1
var total_runs: int = 0
## 累计通关次数（解锁角色 / 发放天赋点的依据）
var total_wins: int = 0
## 账户金币：跨局持久化，开局前可在武器图鉴中花费，替换初始武器。
## 完全通关（最后一层）时，当局金币的 1/3 转化为账户金币。
const ACCOUNT_GOLD_START: int = 300
var account_gold: int = ACCOUNT_GOLD_START
## 武器图鉴选定的开局初始 3 把武器 id（默认核心三把）
var starter_kit_ids: Array[String] = ["pistol", "shotgun", "laser"]

# ---------- 角色 / 永久天赋树 ----------
## 本局选择的角色 id（CharacterDB 的键）
var character_id: String = CharacterDB.STARTER_ID
## 天赋点总数（元进度，靠通关与到达层数获得）
var talent_points: int = 0
## 已获得的天赋点总数（展示用，不随加点减少）
var talent_points_total: int = 0
## 每棵树的已分配节点：{ character_id: Array[String] }
var talent_allocations: Dictionary = {}
## 上一局使用的角色（结算界面展示）
var last_character_id: String = ""
## 最近一次 end_run 时通关转化的账户金币数（结算界面展示用）
var last_account_added: int = 0
var settings: Dictionary = {
	"master_volume": 0.85,
	"sfx_volume": 0.9,
	"bgm_volume": 0.55,
	"fullscreen": false,
	"screen_shake": true,
	"show_fps": false,
}


func _ready() -> void:
	_load_meta_and_settings()


# ==================== 一局游戏 ====================

## 开新局。seed_value 传 0 表示随机，start_floor 为选择的起始关卡（默认 1）。
func new_run(seed_value: int = 0, start_floor: int = 1) -> void:
	run_seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system() * 1000.0) % 1000000007
	rng.seed = run_seed
	floor_index = clampi(start_floor, 1, G.TOTAL_FLOORS)
	gold = G.START_GOLD
	weapons.clear()
	weapon_index = 0
	talents.clear()
	bombs = G.START_BOMBS
	# 角色 + 永久天赋树共同决定本局属性（而不是裸的 DEFAULT_PLAYER_STATS）
	last_character_id = character_id
	apply_character_loadout()
	bombs += int(stats.get("start_bombs", 0.0))
	bombs = G.clampi(bombs, 0, G.MAX_BOMBS)
	gold += int(float(stats.get("gold_start", 0.0)))
	kills = 0
	elite_kills = 0
	score = 0
	has_floor_key = false
	run_active = true
	total_runs += 1
	_save_meta()
	gold_changed.emit(gold)
	weapons_changed.emit(weapons)
	talents_changed.emit(talents)
	bombs_changed.emit(bombs)
	floor_changed.emit(floor_index)
	key_changed.emit(has_floor_key)


## 本层的布局种子：同一局同一层永远生成同一张地图（读档 / 测试复现都靠它）
func floor_seed(floor_index_override: int = -1) -> int:
	var index: int = floor_index_override if floor_index_override > 0 else floor_index
	return run_seed + index * 1000003


## 拿到 / 用掉地牢钥匙
func set_floor_key(value: bool) -> void:
	if has_floor_key == value:
		return
	has_floor_key = value
	key_changed.emit(has_floor_key)


## 从存档恢复一局（主菜单"继续"）
func restore_run(data: Dictionary) -> bool:
	if data.is_empty() or not bool(data.get("run_active", false)):
		return false
	run_seed = int(data.get("run_seed", 0))
	rng.seed = run_seed
	floor_index = int(data.get("floor_index", 1))
	gold = int(data.get("gold", 0))
	weapons = _deserialize_weapons(data.get("weapons", []))
	weapon_index = int(data.get("weapon_index", 0))
	talents = _deserialize_talents(data.get("talents", []))
	bombs = G.clampi(int(data.get("bombs", G.START_BOMBS)), 0, G.MAX_BOMBS)
	# 读档：角色以存档为准；旧存档没有该字段时沿用当前选择的角色
	var saved_character: String = str(data.get("character_id", ""))
	if CharacterDB.has_character(saved_character):
		character_id = saved_character
	apply_character_loadout()
	for k: String in data.get("stats", {}).keys():
		if stats.has(k):
			stats[k] = data["stats"][k]
	stats["health"] = minf(float(stats.get("health", stats["max_health"])), float(stats["max_health"]))
	kills = int(data.get("kills", 0))
	elite_kills = int(data.get("elite_kills", 0))
	score = int(data.get("score", 0))
	has_floor_key = bool(data.get("has_floor_key", false))
	run_active = true
	_apply_talent_modifiers()
	gold_changed.emit(gold)
	weapons_changed.emit(weapons)
	talents_changed.emit(talents)
	bombs_changed.emit(bombs)
	floor_changed.emit(floor_index)
	key_changed.emit(has_floor_key)
	return true


## 结束一局（胜利或失败）
func end_run(victory: bool) -> void:
	run_active = false
	var reached_new_floor: bool = floor_index > best_floor
	best_floor = max(best_floor, floor_index)
	if victory and floor_index >= G.TOTAL_FLOORS:
		total_wins += 1
	# 元进度结算：首通新层 / 通关都会发天赋点
	grant_progress_rewards(victory, reached_new_floor)
	# 完全通关（打完最后一层）时，当局积攒金币的 1/3 转化为账户金币
	last_account_added = 0
	if victory and floor_index >= G.TOTAL_FLOORS:
		last_account_added = gold / 3
		account_gold += last_account_added
	_save_meta()
	SaveMgr.clear_run()
	EventBus.run_finished.emit(victory, floor_index, gold)


func abort_run() -> void:
	run_active = false
	SaveMgr.clear_run()


## 进入下一层：保留金币/武器/天赋，生命与护盾按比例部分恢复
func advance_floor() -> bool:
	if floor_index >= G.TOTAL_FLOORS:
		return false
	floor_index += 1
	best_floor = max(best_floor, floor_index)
	unlocked_floor = max(unlocked_floor, floor_index)
	# 每层的钥匙只开本层的 Boss 门，进新层重新找
	has_floor_key = false
	if not stats.is_empty():
		var heal: float = float(stats["max_health"]) * 0.25
		stats["health"] = clampf(float(stats["health"]) + heal, 0.0, float(stats["max_health"]))
		stats["shield"] = float(stats["max_shield"])
		stats["energy"] = float(stats["max_energy"])
	floor_changed.emit(floor_index)
	key_changed.emit(has_floor_key)
	_save_meta()
	return true


# ==================== 金币 ====================

func add_gold(amount: int) -> void:
	gold = max(0, gold + amount)
	gold_changed.emit(gold)


func try_spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


# ==================== 战绩 ====================

## 记录一次击杀（敌人死亡时由 Enemy.die() 调用）
func register_kill(score_value: int = 0, elite: bool = false) -> void:
	kills += 1
	if elite:
		elite_kills += 1
	score = max(0, score + maxi(score_value, 0))


# ==================== 武器 ====================

const MAX_WEAPONS: int = 3


func add_weapon(weapon_data: Resource) -> bool:
	if weapon_data == null:
		return false
	if weapons.size() < MAX_WEAPONS:
		weapons.append(weapon_data)
		weapons_changed.emit(weapons)
		if weapons.size() == 1:
			weapon_index = 0
			EventBus.weapon_switched.emit(0)
		return true
	# 已满：替换当前手持武器
	weapons[weapon_index] = weapon_data
	weapons_changed.emit(weapons)
	EventBus.weapon_switched.emit(weapon_index)
	return true


func set_weapon_index(index: int) -> void:
	if weapons.is_empty():
		return
	weapon_index = posmod(index, weapons.size())
	EventBus.weapon_switched.emit(weapon_index)


func current_weapon() -> Resource:
	if weapons.is_empty():
		return null
	return weapons[clamp(weapon_index, 0, weapons.size() - 1)]


# ==================== 临时天赋 ====================

## 添加临时天赋。talent: {id, display_name, duration, modifiers, instant, description}
func add_talent(talent: Dictionary) -> void:
	var tid: String = str(talent.get("id", ""))
	if tid.is_empty():
		return
	# 同 id 叠加时长而不是重复入列
	for t: Dictionary in talents:
		if str(t.get("id", "")) == tid:
			t["remain"] = maxf(float(t.get("duration", G.TALENT_DEFAULT_DURATION)), float(t.get("remain", 0.0)))
			talents_changed.emit(talents)
			_apply_talent_modifiers()
			EventBus.talent_gained.emit(tid, float(t["remain"]))
			return
	var entry: Dictionary = talent.duplicate(true)
	entry["remain"] = maxf(float(entry.get("duration", G.TALENT_DEFAULT_DURATION)), 0.1)
	talents.append(entry)
	_enforce_talent_slots()
	talents_changed.emit(talents)
	_apply_talent_modifiers()
	EventBus.talent_gained.emit(tid, float(entry["remain"]))


## 天赋槽位上限：超出时淘汰"剩余时间最短"的那个（最接近自然过期，损失最小）
func _enforce_talent_slots() -> void:
	while talents.size() > G.TALENT_MAX_SLOTS:
		var worst: int = 0
		for i: int in range(1, talents.size()):
			if float(talents[i].get("remain", 0.0)) < float(talents[worst].get("remain", 0.0)):
				worst = i
		var tid: String = str(talents[worst].get("id", ""))
		talents.remove_at(worst)
		EventBus.talent_expired.emit(tid)


## 当前是否有某天赋生效
func has_talent(talent_id: String) -> bool:
	for t: Dictionary in talents:
		if str(t.get("id", "")) == talent_id:
			return true
	return false


# ==================== 炸弹 ====================

## 增加炸弹（掉落 / 商店 / 祭坛），返回实际增加数量
func add_bombs(amount: int = 1) -> int:
	var before: int = bombs
	bombs = G.clampi(bombs + maxi(amount, 0), 0, G.MAX_BOMBS)
	if bombs != before:
		bombs_changed.emit(bombs)
	return bombs - before


## 消耗一枚炸弹。返回 false 表示没有炸弹可用。
func use_bomb() -> bool:
	if bombs <= 0:
		return false
	bombs -= 1
	bombs_changed.emit(bombs)
	return true


## 存档反序列化：只保留表里仍存在、且剩余时间大于 0 的天赋
func _deserialize_talents(list: Variant) -> Array:
	var out: Array = []
	if not (list is Array):
		return out
	for entry: Variant in list:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = (entry as Dictionary).duplicate(true)
		var tid: String = str(data.get("id", ""))
		if tid.is_empty():
			continue
		data["remain"] = float(data.get("remain", 0.0))
		if data["remain"] <= 0.0:
			continue
		if not data.has("duration"):
			data["duration"] = data["remain"]
		out.append(data)
	return out


## 存档序列化（talents 全是基础类型，可直接进 JSON）
func _serialize_talents() -> Array:
	var out: Array = []
	for t: Dictionary in talents:
		out.append(t.duplicate(true))
	return out


## 每帧由 Player 调用，扣减天赋时长
func tick_talents(delta: float) -> void:
	if talents.is_empty():
		return
	var changed: bool = false
	for i: int in range(talents.size() - 1, -1, -1):
		var t: Dictionary = talents[i]
		t["remain"] = float(t["remain"]) - delta
		if float(t["remain"]) <= 0.0:
			var tid: String = str(t.get("id", ""))
			talents.remove_at(i)
			changed = true
			EventBus.talent_expired.emit(tid)
	if changed:
		talents_changed.emit(talents)
		_apply_talent_modifiers()


func clear_talents() -> void:
	talents.clear()
	talents_changed.emit(talents)
	_apply_talent_modifiers()


## 天赋修正值 = 所有生效天赋 modifiers 的累加，写入 stats 的 *_bonus 字段。
## 每次都先清空旧的 bonus_ 键，避免天赋到期后加成残留。
func _apply_talent_modifiers() -> void:
	if stats.is_empty():
		return
	var stale: Array[String] = []
	for k: String in stats.keys():
		if k.begins_with("bonus_"):
			stale.append(k)
	for k: String in stale:
		stats.erase(k)

	var bonus: Dictionary = {}
	for t: Dictionary in talents:
		for k: String in t.get("modifiers", {}).keys():
			bonus[k] = float(bonus.get(k, 0.0)) + float(t["modifiers"][k])
	for k: String in bonus.keys():
		stats["bonus_" + k] = bonus[k]
	EventBus.player_stats_changed.emit(stats)


## 读取属性（含天赋加成），带默认值兜底
func stat_value(key: String) -> float:
	if stats.is_empty():
		stats = G.DEFAULT_PLAYER_STATS.duplicate(true)
	var base: float = float(stats.get(key, 0.0))
	return base + float(stats.get("bonus_" + key, 0.0))


func snapshot_stats(from_stats: Dictionary) -> void:
	for k: String in from_stats.keys():
		if not k.begins_with("bonus_"):
			stats[k] = from_stats[k]


# ==================== 角色 ====================

## 当前角色是否已解锁
func is_character_unlocked(character_id_override: String) -> bool:
	return CharacterDB.is_unlocked(character_id_override, best_floor, total_wins)


## 选择本局角色（未解锁的角色会被拒绝）
func select_character(character_id_override: String) -> bool:
	if not CharacterDB.has_character(character_id_override):
		return false
	if not is_character_unlocked(character_id_override):
		return false
	character_id = character_id_override
	_apply_character_stats()
	character_changed.emit(character_id)
	_save_meta()
	return true


## 当前角色的主动技能 id
func current_skill() -> String:
	return CharacterDB.skill_of(character_id)


## 把「角色基础覆盖 + 永久天赋修正」合成为本局 stats。
## 调用时机：new_run / restore_run / 切换角色 / 加点之后。
func apply_character_loadout() -> void:
	stats = G.DEFAULT_PLAYER_STATS.duplicate(true)
	_apply_character_stats()
	_apply_talent_modifiers()


func _apply_character_stats() -> void:
	if stats.is_empty():
		stats = G.DEFAULT_PLAYER_STATS.duplicate(true)
	# 1) 角色基础属性（生命 / 移速 / 技能冷却…）
	var overrides: Dictionary = CharacterDB.stat_overrides(character_id)
	for key: String in overrides.keys():
		stats[key] = float(overrides[key])
	# 2) 永久天赋树的修正（跨局累积）
	var bonus: Dictionary = character_bonus()
	for key: String in bonus.keys():
		stats[key] = float(stats.get(key, 0.0)) + float(bonus[key])


# ==================== 永久天赋树 ====================

## 某角色已分配的节点列表
func allocated_nodes(character_id_override: String = "") -> Array:
	var key: String = character_id_override if not character_id_override.is_empty() else character_id
	var list: Variant = talent_allocations.get(key, [])
	return list if list is Array else []


## 某角色天赋树带来的永久修正
func character_bonus(character_id_override: String = "") -> Dictionary:
	var key: String = character_id_override if not character_id_override.is_empty() else character_id
	return TalentTree.bonus_of(key, allocated_nodes(key))


## 该节点当前是否可加点
func can_allocate(node_id: String) -> bool:
	var node: Dictionary = TalentTree.get_node(character_id, node_id)
	if node.is_empty() or talent_points < TalentTree.cost_of(node):
		return false
	return TalentTree.can_unlock(character_id, node_id, allocated_nodes())


## 加点。返回是否成功（点数不足 / 前置未点 / 重复点都返回 false）。
func allocate_talent(node_id: String) -> bool:
	var node: Dictionary = TalentTree.get_node(character_id, node_id)
	if node.is_empty():
		return false
	var cost: int = TalentTree.cost_of(node)
	if talent_points < cost or not TalentTree.can_unlock(character_id, node_id, allocated_nodes()):
		return false
	talent_points -= cost
	var list: Array = allocated_nodes().duplicate()
	list.append(node_id)
	talent_allocations[character_id] = list
	# 加点立刻反映到属性上：重算而不是叠加，避免旧加成残留
	_apply_character_stats()
	talent_allocated.emit(character_id, node_id)
	_save_meta()
	return true


## 洗点：退回该角色所有点数。
## 刻意提供——第一次玩很难猜对加点顺序，锁死不能改会让人因为一次误点而弃坑。
func reset_talents(character_id_override: String = "") -> bool:
	var key: String = character_id_override if not character_id_override.is_empty() else character_id
	if not talent_allocations.has(key):
		return false
	talent_points += TalentTree.spent_points_of(key, allocated_nodes(key))
	talent_allocations.erase(key)
	_apply_character_stats()
	talent_allocated.emit(key, "")
	_save_meta()
	return true


## 获得天赋点（解锁新角色 / 通关时调用）
func grant_talent_points(amount: int) -> void:
	if amount <= 0:
		return
	talent_points += amount
	talent_points_total += amount
	talent_points_changed.emit(talent_points)
	_save_meta()


## 元进度推进：首通新层给 1 点，完全通关额外给 3 点
func grant_progress_rewards(victory: bool, reached_new_floor: bool) -> void:
	grant_talent_points((1 if reached_new_floor else 0) + (3 if victory else 0))


## 该角色是否已点满整棵树（结算界面提示「可换角色」用）
func is_talent_tree_complete(character_id_override: String = "") -> bool:
	var key: String = character_id_override if not character_id_override.is_empty() else character_id
	return TalentTree.is_tree_complete(key, allocated_nodes(key))


# ==================== 设置 ====================

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	settings_changed.emit()
	SaveMgr.save_settings(settings)
	_apply_display_settings()


func _apply_display_settings() -> void:
	var want_fullscreen: bool = bool(settings.get("fullscreen", false))
	var current_mode: int = DisplayServer.window_get_mode()
	if want_fullscreen and current_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not want_fullscreen and current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _load_meta_and_settings() -> void:
	var loaded_settings: Dictionary = SaveMgr.load_settings()
	for k: String in loaded_settings.keys():
		if settings.has(k):
			settings[k] = loaded_settings[k]
	var meta: Dictionary = SaveMgr.load_meta()
	best_floor = int(meta.get("best_floor", 0))
	unlocked_floor = maxi(int(meta.get("unlocked_floor", 1)), 1)
	total_runs = int(meta.get("total_runs", 0))
	total_wins = int(meta.get("total_wins", 0))
	talent_points = int(meta.get("talent_points", 0))
	talent_points_total = maxi(talent_points, int(meta.get("talent_points_total", 0)))
	# 天赋树分配：逐角色读入，丢弃已不存在的节点（版本迭代后不会崩）
	talent_allocations = {}
	var raw_allocations: Variant = meta.get("talent_allocations", {})
	if raw_allocations is Dictionary:
		for key: Variant in (raw_allocations as Dictionary).keys():
			var character_key: String = str(key)
			if not CharacterDB.has_character(character_key):
				continue
			var valid: Array = []
			for node_id: Variant in ((raw_allocations as Dictionary)[key] as Array):
				var node_key: String = str(node_id)
				if not TalentTree.get_node(character_key, node_key).is_empty():
					valid.append(node_key)
			if not valid.is_empty():
				talent_allocations[character_key] = valid
	var saved_character: String = str(meta.get("character_id", ""))
	if CharacterDB.has_character(saved_character):
		character_id = saved_character
	account_gold = maxi(int(meta.get("account_gold", ACCOUNT_GOLD_START)), 0)
	var loaded_kit: Array = meta.get("starter_kit_ids", [])
	if loaded_kit.is_empty():
		starter_kit_ids = ["pistol", "shotgun", "laser"]
	else:
		starter_kit_ids = []
		for weapon_id: Variant in loaded_kit:
			starter_kit_ids.append(str(weapon_id))
		# 如果存档数据不完整，补齐到 3 把
		while starter_kit_ids.size() < 3:
			starter_kit_ids.append(WeaponDB.STARTER_ID)
	last_account_added = 0
	_apply_display_settings()


func _save_meta() -> void:
	SaveMgr.save_meta({
		"best_floor": best_floor,
		"unlocked_floor": unlocked_floor,
		"total_runs": total_runs,
		"total_wins": total_wins,
		"talent_points": talent_points,
		"talent_points_total": talent_points_total,
		"talent_allocations": talent_allocations,
		"character_id": character_id,
		"account_gold": account_gold,
		"starter_kit_ids": starter_kit_ids,
	})


## 武器图鉴：用账户金币购买武器并替换指定槽位的初始武器（手枪免费）。
## 账户金币不足、武器 id 未知或槽位越界时返回 false。
func buy_kit_weapon(weapon_id: String, slot_index: int) -> bool:
	if not WeaponDB.has_weapon(weapon_id):
		return false
	if slot_index < 0 or slot_index >= starter_kit_ids.size():
		return false
	var price: int = int(WeaponDB.TABLE[weapon_id].get("price", 0))
	if account_gold < price:
		return false
	if price > 0:
		account_gold -= price
	starter_kit_ids[slot_index] = weapon_id
	_save_meta()
	return true


## 把当前局写入存档（换层/暂停时调用），供主菜单"继续"使用
func save_current_run() -> void:
	if not run_active:
		return
	SaveMgr.save_run({
		"run_active": true,
		"run_seed": run_seed,
		"floor_index": floor_index,
		"gold": gold,
		"character_id": character_id,
		"weapon_index": weapon_index,
		"weapons": _serialize_weapons(weapons),
		"talents": _serialize_talents(),
		"bombs": bombs,
		"stats": _serializable_stats(),
		"kills": kills,
		"elite_kills": elite_kills,
		"score": score,
		"has_floor_key": has_floor_key,
	})


func has_saved_run() -> bool:
	return SaveMgr.has_run()


func _serializable_stats() -> Dictionary:
	var out: Dictionary = {}
	for k: String in stats.keys():
		if not k.begins_with("bonus_"):
			out[k] = stats[k]
	return out


func _serialize_weapons(list: Array) -> Array:
	var out: Array = []
	for w: Resource in list:
		if w != null and w.has_method("to_dict"):
			out.append(w.to_dict())
	return out


func _deserialize_weapons(list: Variant) -> Array:
	var out: Array = []
	var db_path: String = "res://scripts/core/weapon_db.gd"
	if not ResourceLoader.exists(db_path):
		return out
	var db: GDScript = load(db_path)
	for entry: Variant in list:
		if entry is Dictionary:
			var w: Resource = db.from_dict(entry)
			if w != null:
				out.append(w)
	return out
