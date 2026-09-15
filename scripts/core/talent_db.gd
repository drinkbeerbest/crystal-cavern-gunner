class_name TalentDB
extends RefCounted
## TalentDB —— 临时天赋表与工厂（M6）。
##
## 天赋是"限时增益"：拾取后写入 GameState.talents，由 GameState._apply_talent_modifiers()
## 把 modifiers 累加成 stats 的 `bonus_*` 字段；Player 读属性时用 `_stat(key)`（基础值 + bonus）。
## 到期后 bonus_ 键被整体重算，加成自动消失，不需要逐个回滚。
##
## 两种效果：
##   modifiers —— 持续期内的属性修正（可正可负，如 shield_regen_delay 为负表示更快回盾）
##   instant   —— 拾取瞬间一次性结算（回血 / 回盾 / 回能 / 给炸弹），不进 bonus_
##
## 扩展方式：往 TABLE 里加一条，并把图标帧放到 assets/pickups/talent_<id>_0..3.png
## （生成器 tools/gen_fx.py 的 TALENTS 列表同步加一行即可）。

const G := preload("res://scripts/core/game_const.gd")

## 天赋表：id -> 定义
const TABLE: Dictionary = {
	"speed": {
		"display_name": "疾风", "duration": 22.0, "weight": 22.0,
		"modifiers": {"move_speed": 46.0, "attack_speed_multiplier": 0.12},
		"instant": {},
		"description": "移速 +46，攻速 +12%",
	},
	"crit": {
		"display_name": "锐眼", "duration": 24.0, "weight": 20.0,
		"modifiers": {"crit_chance": 0.18, "crit_multiplier": 0.5},
		"instant": {},
		"description": "暴击率 +18%，暴击倍率 +0.5",
	},
	"damage": {
		"display_name": "狂怒", "duration": 20.0, "weight": 20.0,
		"modifiers": {"damage_multiplier": 0.35},
		"instant": {},
		"description": "全部伤害 +35%",
	},
	"shield": {
		"display_name": "晶壳", "duration": 26.0, "weight": 16.0,
		"modifiers": {"max_shield": 25.0, "shield_regen_rate": 6.0, "shield_regen_delay": -1.5},
		"instant": {"shield": 25.0},
		"description": "护盾上限 +25、回盾 +6/秒，并立即补 25 护盾",
	},
	"life": {
		"display_name": "生机", "duration": 18.0, "weight": 14.0,
		"modifiers": {"max_health": 20.0},
		"instant": {"health": 30.0},
		"description": "生命上限 +20，并立即回复 30 生命",
	},
	"energy": {
		"display_name": "涌能", "duration": 25.0, "weight": 18.0,
		"modifiers": {"max_energy": 25.0, "energy_regen": 4.0},
		"instant": {"energy": 40.0},
		"description": "能量上限 +25、回能 +4/秒，并立即补 40 能量",
	},
}

## 图标帧数（与 gen_fx.py 的 _talent_frame 一致）
const ICON_FRAMES: int = 4
const ICON_DIR: String = "res://assets/pickups/"


static func ids() -> Array:
	return TABLE.keys()


static func has_talent(talent_id: String) -> bool:
	return TABLE.has(talent_id)


static func get_def(talent_id: String) -> Dictionary:
	return TABLE.get(talent_id, {})


static func display_name(talent_id: String) -> String:
	return str(get_def(talent_id).get("display_name", talent_id))


static func description(talent_id: String) -> String:
	return str(get_def(talent_id).get("description", ""))


## 图标路径（frame 会绕回，用于 HUD / 拾取物的循环动画）
static func icon_path(talent_id: String, frame: int = 0) -> String:
	var index: int = posmod(frame, ICON_FRAMES)
	return ICON_DIR + "talent_%s_%d.png" % [talent_id, index]


## 生成一个可直接交给 GameState.add_talent() 的天赋实例（深拷贝，调用方可安全修改）
static func create(talent_id: String) -> Dictionary:
	if not TABLE.has(talent_id):
		push_warning("TalentDB: 未知天赋 id '%s'" % talent_id)
		return {}
	var def: Dictionary = TABLE[talent_id]
	var duration: float = float(def.get("duration", G.TALENT_DEFAULT_DURATION))
	return {
		"id": talent_id,
		"display_name": str(def.get("display_name", talent_id)),
		"duration": duration,
		"modifiers": (def.get("modifiers", {}) as Dictionary).duplicate(true),
		"instant": (def.get("instant", {}) as Dictionary).duplicate(true),
		"description": str(def.get("description", "")),
	}


## 按权重随机一个天赋实例。exclude 里的 id 不会出现（用于"不重复发同一个"）。
static func random(rng: RandomNumberGenerator, exclude: Array = []) -> Dictionary:
	var weights: Dictionary = {}
	for talent_id: Variant in TABLE.keys():
		if exclude.has(str(talent_id)):
			continue
		weights[str(talent_id)] = float(TABLE[talent_id].get("weight", 10.0))
	if weights.is_empty():
		for talent_id: Variant in TABLE.keys():
			weights[str(talent_id)] = float(TABLE[talent_id].get("weight", 10.0))
	var picked: Variant = G.weighted_pick(weights, rng)
	if picked == null:
		return {}
	return create(str(picked))


## 天赋实例的一次性效果（health / shield / energy / bombs）
static func instant_effects(entry: Dictionary) -> Dictionary:
	return (entry.get("instant", {}) as Dictionary).duplicate(true)
