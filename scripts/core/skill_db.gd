class_name SkillDB
extends RefCounted
## SkillDB —— 主动技能表（每角色一招，打法完全不同）。
##
## 原先全角色共用一个「晶能冲击波」：范围大、不准、没有决策——
## 玩家按 Space 只是把按钮按下去，不会改变任何打法。
## 现在技能是**角色身份的一部分**：
##   剑士  突进斩 —— 主动位移穿过敌群，位移即伤害，讲究"钻进去再钻出来"
##   射手  箭    雨 —— 原地向八方各射一发，讲究"被围住时的解法"
##   工程机 哨戒炮台 —— 丢下一座自动开火的炮台，讲究"用场地换输出"
##
## 三个技能的共同设计约束：**没有一个是无条件最优**。
## 剑士要贴脸（远程角色用等于自杀），射手要站位，炮台要提前布置。

## 技能类型
enum Kind { SHOCKWAVE, DASH_SLASH, BARRAGE, TURRET }

## 技能表：id -> 定义
## cooldown      冷却（秒）
## energy_cost   能量消耗
## damage        单次伤害
## radius        作用半径（冲击波 / 箭雨 / 炮台索敌）
## knockback     击退
const TABLE: Dictionary = {
	"shockwave": {
		"display_name": "晶能冲击波", "kind": Kind.SHOCKWAVE, "cooldown": 4.8,
		"energy_cost": 20.0, "damage": 44.0, "radius": 115.0, "knockback": 380.0,
		"icon": "icon_skill.png",
		"description": "以自身为中心炸开一圈晶能，把贴脸的敌人推开。",
	},
	"dash_slash": {
		"display_name": "突进斩", "kind": Kind.DASH_SLASH, "cooldown": 3.6,
		"energy_cost": 18.0, "damage": 52.0, "radius": 52.0, "knockback": 260.0,
		"icon": "icon_skill.png",
		"description": "朝瞄准方向瞬突一段距离，沿途切开所有敌人（突进期间无敌）。",
	},
	"barrage": {
		"display_name": "八方箭雨", "kind": Kind.BARRAGE, "cooldown": 5.6,
		"energy_cost": 26.0, "damage": 26.0, "radius": 0.0, "knockback": 90.0,
		"count": 8, "spread_deg": 360.0,
		"icon": "icon_skill.png",
		"description": "原地向八方同时射出八枚追踪晶弹，专治被围。",
	},
	"turret": {
		"display_name": "哨戒炮台", "kind": Kind.TURRET, "cooldown": 12.0,
		"energy_cost": 34.0, "damage": 13.0, "radius": 260.0, "knockback": 60.0,
		"duration": 9.0, "fire_interval": 0.22, "bullet_speed": 420.0,
		"icon": "icon_skill.png",
		"description": "丢下一座自动锁定开火的炮台，存在 9 秒后自毁。",
	},
}

## 突进斩的实际位移距离（不在表里，因为它是手感参数不是平衡参数）
const DASH_SLASH_DISTANCE: float = 210.0
## 突进斩的无敌时长
const DASH_SLASH_IFRAMES: float = 0.22


static func ids() -> Array:
	return TABLE.keys()


static func has_skill(skill_id: String) -> bool:
	return TABLE.has(skill_id)


static func get_def(skill_id: String) -> Dictionary:
	return TABLE.get(skill_id, {})


static func display_name(skill_id: String) -> String:
	return str(get_def(skill_id).get("display_name", skill_id))


static func description(skill_id: String) -> String:
	return str(get_def(skill_id).get("description", ""))


static func cooldown_of(skill_id: String) -> float:
	return float(get_def(skill_id).get("cooldown", 5.0))


static func energy_cost_of(skill_id: String) -> float:
	return float(get_def(skill_id).get("energy_cost", 20.0))


static func kind_of(skill_id: String) -> int:
	return int(get_def(skill_id).get("kind", Kind.SHOCKWAVE))


## 数值：给 Player 内部使用，带安全默认值
static func value(skill_id: String, key: String, fallback: float) -> float:
	return float(get_def(skill_id).get(key, fallback))
