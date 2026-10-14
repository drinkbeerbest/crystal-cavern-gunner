class_name CharacterDB
extends RefCounted
## CharacterDB —— 角色（职业）表。
##
## 元气骑士那一类作品的地基是「角色」：每个角色有独立的生命上限、初始武器、
## **专属主动技能**和**专属天赋树**，于是「这局我玩什么」本身就成了第一决策。
## 之前本游戏只有一个无名角色，开局三把枪自选——有武器选择，但没有身份。
##
## 三个角色按「想要的乐趣」分开，而不是按数值强弱：
##   晶刃武士 —— 贴脸换命：血厚、技能是突进斩、初始近战
##   游晶游侠 —— 远程风筝：血脆、技能是箭雨、初始精准
##   哨戒工程机 —— 阵地输出：技能是丢炮台、初始双持
##
## 每个角色还有一棵**独立天赋树**（见 talent_tree.gd），所以换角色不是换个数值，
## 而是换一整套构筑路线。
##
## 扩展方式：TABLE 加一条（记得同步 talent_tree.gd 里的 TREES）。

## 天赋树的分支（与 talent_tree.gd 的 Branch 对应）
enum Branch { OFFENSE, DEFENSE, UTILITY }

## 角色表：id -> 定义
## stats        覆盖到 DEFAULT_PLAYER_STATS 的键（只写要改的）
## skill        SkillDB 的 id
## starter_kit  WeaponDB 的 id 列表（不足 3 把会自动补全）
## unlock       解锁条件：{"floor": n} = 到达过第 n 层；{"wins": n} = 通关 n 次；缺省 = 初始解锁
const TABLE: Dictionary = {
	"vanguard": {
		"display_name": "晶刃武士", "tag": "刃",
		"order": 0, "unlock": {},
		"color": Color(1.00, 0.42, 0.36),
		"skill": "dash_slash", "branch": "offense",
		"starter_kit": ["blade", "shotgun", "pistol"],
		"stats": {
			"max_health": 130.0, "health": 130.0,
			"max_shield": 60.0, "shield": 60.0,
			"move_speed": 218.0, "dash_cooldown": 0.72,
		},
		"description": "以身体为武器的高压近战。突进斩让你能钻进敌群再穿出来。",
	},
	"ranger": {
		"display_name": "游晶游侠", "tag": "游",
		"order": 1, "unlock": {"floor": 2},
		"color": Color(0.48, 0.82, 1.00),
		"skill": "barrage", "branch": "utility",
		"starter_kit": ["rifle", "pistol", "wand"],
		"stats": {
			"max_health": 92.0, "health": 92.0,
			"max_shield": 45.0, "shield": 45.0,
			"move_speed": 212.0, "energy_regen": 8.5,
			"crit_chance": 0.16, "crit_multiplier": 1.95,
		},
		"description": "脆皮高暴击的远程风筝位。箭雨是你被围住时的救命稻草。",
	},
	"sentinel": {
		"display_name": "哨戒工程机", "tag": "哨",
		"order": 2, "unlock": {"floor": 4},
		"color": Color(0.62, 1.00, 0.52),
		"skill": "turret", "branch": "defense",
		"starter_kit": ["gatling", "shotgun", "laser"],
		"stats": {
			"max_health": 112.0, "health": 112.0,
			"max_shield": 80.0, "shield": 80.0,
			"max_energy": 130.0, "energy": 130.0, "energy_regen": 9.5,
			"move_speed": 196.0, "pickup_radius": 92.0,
		},
		"description": "丢炮台打输出的阵地流。战场控制是你的强项，贴脸是短板。",
	},
}

## 初始解锁的角色（unlock 为空的那个）
const STARTER_ID: String = "vanguard"


static func ids() -> Array:
	var out: Array = []
	for key: Variant in TABLE.keys():
		out.append(str(key))
	out.sort_custom(func(a: String, b: String) -> bool:
		return int(TABLE[a].get("order", 0)) < int(TABLE[b].get("order", 0))
	)
	return out


static func has_character(character_id: String) -> bool:
	return TABLE.has(character_id)


static func get_def(character_id: String) -> Dictionary:
	return TABLE.get(character_id, {})


static func display_name(character_id: String) -> String:
	return str(get_def(character_id).get("display_name", character_id))


static func description(character_id: String) -> String:
	return str(get_def(character_id).get("description", ""))


static func tag_of(character_id: String) -> String:
	return str(get_def(character_id).get("tag", "?"))


static func color_of(character_id: String) -> Color:
	return get_def(character_id).get("color", Color(0.85, 0.87, 0.92))


static func skill_of(character_id: String) -> String:
	return str(get_def(character_id).get("skill", "shockwave"))


static func branch_of(character_id: String) -> String:
	return str(get_def(character_id).get("branch", "offense"))


## 开局武器 id 列表（不足 3 把时用核心三把补全）。
## 返回 Array[String] 以便直接喂给 WeaponDB.starter_kit(kit_ids: Array[String])。
static func starter_kit(character_id: String) -> Array[String]:
	var kit: Array[String] = []
	for weapon_id: Variant in (get_def(character_id).get("starter_kit", []) as Array):
		var key: String = str(weapon_id)
		if WeaponDB.has_weapon(key) and not kit.has(key):
			kit.append(key)
	for weapon: Variant in WeaponDB.core_three():
		if kit.size() >= 3:
			break
		if not kit.has(str((weapon as WeaponData).id)):
			kit.append(str((weapon as WeaponData).id))
	return kit


## 角色属性覆盖表（只含要改的键），交给 GameState 合并进 DEFAULT_PLAYER_STATS
static func stat_overrides(character_id: String) -> Dictionary:
	return (get_def(character_id).get("stats", {}) as Dictionary).duplicate(true)


## 角色是否已解锁：到达过对应层数，或累计通关次数达标
static func is_unlocked(character_id: String, best_floor: int, total_wins: int) -> bool:
	var unlock: Dictionary = get_def(character_id).get("unlock", {})
	if unlock.is_empty():
		return true
	if int(unlock.get("floor", 0)) > 0 and best_floor >= int(unlock["floor"]):
		return true
	if int(unlock.get("wins", 0)) > 0 and total_wins >= int(unlock["wins"]):
		return true
	return false


## 未解锁时的提示文案
static func unlock_hint(character_id: String) -> String:
	var unlock: Dictionary = get_def(character_id).get("unlock", {})
	if unlock.is_empty():
		return ""
	if int(unlock.get("floor", 0)) > 0:
		return "到达第 %d 层解锁" % int(unlock["floor"])
	if int(unlock.get("wins", 0)) > 0:
		return "通关 %d 次解锁" % int(unlock["wins"])
	return ""
