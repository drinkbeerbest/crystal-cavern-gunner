class_name TalentTree
extends RefCounted
## TalentTree —— 永久天赋树（每角色一棵，三支线 × 四层）。
##
## 和「临时天赋」（TalentDB，25 秒限时增益）是两回事：
##   TalentDB   = 局内爆发，打完就消失，是节奏调节器
##   TalentTree = 跨局永久加点，是**长期投入的唯一载体**
##
## 之前本游戏完全没有后者，元进度只有「账户金币换初始武器」一条直线，
## 没有纵深，于是「为什么要再开一局」这个问题没有答案。
##
## 每条支线 4 层：层数越高越贵，且第 2/3/4 层需要前置节点，
## 所以加点顺序本身也是决策（先点一条到底，还是三条各点一层）。
##
## 加点产出的是 stats 里的**永久修正键**（如 bonus_vanguard_damage），
## 由 GameState 汇总成 *_bonus 字段，Player 的 _stat() 直接受益。

const G := preload("res://scripts/core/game_const.gd")

## 支线
const BRANCHES: Array[String] = ["offense", "defense", "utility"]
const BRANCH_NAMES: Dictionary = {
	"offense": "锋刃", "defense": "晶壳", "utility": "机巧",
}
## 支线配色（HUD / 图鉴用）
const BRANCH_COLORS: Dictionary = {
	"offense": Color(1.00, 0.45, 0.38),
	"defense": Color(0.42, 0.74, 1.00),
	"utility": Color(0.62, 1.00, 0.52),
}

## 每条支线的层数
const TIERS: int = 4
## 单个节点的加点消耗（随层数递增）
const TIER_COST: Array[int] = [1, 1, 2, 3]
## 每棵树的节点总数（3 支线 × 4 层）
const NODES_PER_TREE: int = 12

## 天赋树：角色 id -> 节点数组
## 每个节点：
##   id / branch / tier / display_name / description
##   requires  上一层的节点 id（空 = 第一层）
##   stats     { stat_key: value }  加点后的永久修正（走 stats 的 bonus_ 通道）
##   unlocks   ["skill_turret"]    可选：解锁的东西（目前先占位）
const TREES: Dictionary = {
	"vanguard": [
		{"id": "vg_o1", "branch": "offense", "tier": 0, "display_name": "锋锐",
			"description": "全部伤害 +8%", "stats": {"damage_multiplier": 0.08}},
		{"id": "vg_o2", "branch": "offense", "tier": 1, "requires": "vg_o1", "display_name": "破甲",
			"description": "全部伤害再 +8%，暴击率 +4%", "stats": {"damage_multiplier": 0.08, "crit_chance": 0.04}},
		{"id": "vg_o3", "branch": "offense", "tier": 2, "requires": "vg_o2", "display_name": "狂怒",
			"description": "全部伤害再 +12%，攻速 +8%", "stats": {"damage_multiplier": 0.12, "attack_speed_multiplier": 0.08}},
		{"id": "vg_o4", "branch": "offense", "tier": 3, "requires": "vg_o3", "display_name": "无双",
			"description": "全部伤害再 +18%，暴击倍率 +0.35", "stats": {"damage_multiplier": 0.18, "crit_multiplier": 0.35}},

		{"id": "vg_d1", "branch": "defense", "tier": 0, "display_name": "厚甲",
			"description": "生命上限 +18", "stats": {"max_health": 18.0}},
		{"id": "vg_d2", "branch": "defense", "tier": 1, "requires": "vg_d1", "display_name": "固守",
			"description": "护盾上限 +15，立即回满", "stats": {"max_shield": 15.0}, "instant": {"shield": 999.0}},
		{"id": "vg_d3", "branch": "defense", "tier": 2, "requires": "vg_d2", "display_name": "生肌",
			"description": "移速 +12，生命上限 +14", "stats": {"move_speed": 12.0, "max_health": 14.0}},
		{"id": "vg_d4", "branch": "defense", "tier": 3, "requires": "vg_d3", "display_name": "不屈",
			"description": "回盾更快，护盾上限 +20", "stats": {"shield_regen_rate": 4.0, "max_shield": 20.0}},

		{"id": "vg_u1", "branch": "utility", "tier": 0, "display_name": "疾足",
			"description": "冲刺冷却 -15%", "stats": {"dash_cooldown": -0.13}},
		{"id": "vg_u2", "branch": "utility", "tier": 1, "requires": "vg_u1", "display_name": "开张",
			"description": "起始金币 +25", "stats": {"gold_start": 25.0}},
		{"id": "vg_u3", "branch": "utility", "tier": 2, "requires": "vg_u2", "display_name": "夺能",
			"description": "能量上限 +25，回能 +1.5/秒", "stats": {"max_energy": 25.0, "energy_regen": 1.5}},
		{"id": "vg_u4", "branch": "utility", "tier": 3, "requires": "vg_u3", "display_name": "战场直觉",
			"description": "拾取范围 +40，幸运 +0.1", "stats": {"pickup_radius": 40.0, "luck": 0.1}},
	],
	"ranger": [
		{"id": "rg_o1", "branch": "offense", "tier": 0, "display_name": "鹰眼",
			"description": "暴击率 +8%", "stats": {"crit_chance": 0.08}},
		{"id": "rg_o2", "branch": "offense", "tier": 1, "requires": "rg_o1", "display_name": "精准",
			"description": "暴击率再 +8%，暴击倍率 +0.3", "stats": {"crit_chance": 0.08, "crit_multiplier": 0.3}},
		{"id": "rg_o3", "branch": "offense", "tier": 2, "requires": "rg_o2", "display_name": "连射",
			"description": "攻速 +12%，弹速 +15%", "stats": {"attack_speed_multiplier": 0.12, "bullet_speed_multiplier": 0.15}},
		{"id": "rg_o4", "branch": "offense", "tier": 3, "requires": "rg_o3", "display_name": "致命",
			"description": "全部伤害 +20%，暴击率 +6%", "stats": {"damage_multiplier": 0.2, "crit_chance": 0.06}},

		{"id": "rg_d1", "branch": "defense", "tier": 0, "display_name": "轻甲",
			"description": "固定减伤 +1", "stats": {"armor": 1.0}},
		{"id": "rg_d2", "branch": "defense", "tier": 1, "requires": "rg_d1", "display_name": "灵巧",
			"description": "移速 +14，拾取范围 +20", "stats": {"move_speed": 14.0, "pickup_radius": 20.0}},
		{"id": "rg_d3", "branch": "defense", "tier": 2, "requires": "rg_d2", "display_name": "回气",
			"description": "生命上限 +16，回盾更快", "stats": {"max_health": 16.0, "shield_regen_rate": 3.0}},
		{"id": "rg_d4", "branch": "defense", "tier": 3, "requires": "rg_d3", "display_name": "韧性",
			"description": "护盾上限 +25，回盾间隔 -0.8 秒", "stats": {"max_shield": 25.0, "shield_regen_delay": -0.8}},

		{"id": "rg_u1", "branch": "utility", "tier": 0, "display_name": "节能",
			"description": "全部武器耗能 -6%", "stats": {"energy_cost_multiplier": -0.06}},
		{"id": "rg_u2", "branch": "utility", "tier": 1, "requires": "rg_u1", "display_name": "连携",
			"description": "回能 +2/秒，能量上限 +15", "stats": {"energy_regen": 2.0, "max_energy": 15.0}},
		{"id": "rg_u3", "branch": "utility", "tier": 2, "requires": "rg_u2", "display_name": "战场补给",
			"description": "开局多带 2 枚炸弹，起始金币 +30", "stats": {"start_bombs": 2.0, "gold_start": 30.0}},
		{"id": "rg_u4", "branch": "utility", "tier": 3, "requires": "rg_u3", "display_name": "神射",
			"description": "击退 +40%，穿透 +1", "stats": {"knockback_multiplier": 0.4, "pierce_bonus": 1.0}},
	],
	"sentinel": [
		{"id": "st_o1", "branch": "offense", "tier": 0, "display_name": "校准",
			"description": "全部伤害 +7%", "stats": {"damage_multiplier": 0.07}},
		{"id": "st_o2", "branch": "offense", "tier": 1, "requires": "st_o1", "display_name": "过载",
			"description": "攻速 +10%，伤害 +6%", "stats": {"attack_speed_multiplier": 0.1, "damage_multiplier": 0.06}},
		{"id": "st_o3", "branch": "offense", "tier": 2, "requires": "st_o2", "display_name": "散射组件",
			"description": "暴击率 +7%，弹速 +12%", "stats": {"crit_chance": 0.07, "bullet_speed_multiplier": 0.12}},
		{"id": "st_o4", "branch": "offense", "tier": 3, "requires": "st_o3", "display_name": "满载",
			"description": "全部伤害 +18%，攻速 +8%", "stats": {"damage_multiplier": 0.18, "attack_speed_multiplier": 0.08}},

		{"id": "st_d1", "branch": "defense", "tier": 0, "display_name": "装甲板",
			"description": "护盾上限 +20", "stats": {"max_shield": 20.0}},
		{"id": "st_d2", "branch": "defense", "tier": 1, "requires": "st_d1", "display_name": "缓冲",
			"description": "回盾 +3/秒，护盾上限 +15", "stats": {"shield_regen_rate": 3.0, "max_shield": 15.0}},
		{"id": "st_d3", "branch": "defense", "tier": 2, "requires": "st_d2", "display_name": "结构强化",
			"description": "生命上限 +22，固定减伤 +1", "stats": {"max_health": 22.0, "armor": 1.0}},
		{"id": "st_d4", "branch": "defense", "tier": 3, "requires": "st_d3", "display_name": "堡垒",
			"description": "护盾上限 +30，回盾间隔 -1 秒", "stats": {"max_shield": 30.0, "shield_regen_delay": -1.0}},

		{"id": "st_u1", "branch": "utility", "tier": 0, "display_name": "自修",
			"description": "拾取范围 +25", "stats": {"pickup_radius": 25.0}},
		{"id": "st_u2", "branch": "utility", "tier": 1, "requires": "st_u1", "display_name": "拆解",
			"description": "起始金币 +35，幸运 +0.08", "stats": {"gold_start": 35.0, "luck": 0.08}},
		{"id": "st_u3", "branch": "utility", "tier": 2, "requires": "st_u2", "display_name": "快速装配",
			"description": "技能冷却 -12%", "stats": {"skill_cooldown_multiplier": -0.12}},
		{"id": "st_u4", "branch": "utility", "tier": 3, "requires": "st_u3", "display_name": "过载电容",
			"description": "能量上限 +30，回能 +2.5/秒", "stats": {"max_energy": 30.0, "energy_regen": 2.5}},
	],
}


## 某角色的全部节点
static func nodes_of(character_id: String) -> Array:
	return TREES.get(character_id, [])


static func node_ids(character_id: String) -> Array:
	var out: Array = []
	for node: Dictionary in nodes_of(character_id):
		out.append(str(node.get("id", "")))
	return out


## 按 id 取节点，找不到返回 {}
static func get_node(character_id: String, node_id: String) -> Dictionary:
	for node: Dictionary in nodes_of(character_id):
		if str(node.get("id", "")) == node_id:
			return node
	return {}


static func branch_name(branch: String) -> String:
	return str(BRANCH_NAMES.get(branch, branch))


static func branch_color(branch: String) -> Color:
	return BRANCH_COLORS.get(branch, Color(0.85, 0.87, 0.92))


## 节点点数
static func cost_of(node: Dictionary) -> int:
	return TIER_COST[clampi(int(node.get("tier", 0)), 0, TIER_COST.size() - 1)]


## 该节点当前是否可加点：前置已点 + 自身未点
static func can_unlock(character_id: String, node_id: String, allocated: Array) -> bool:
	var node: Dictionary = get_node(character_id, node_id)
	if node.is_empty() or allocated.has(node_id):
		return false
	var requires: String = str(node.get("requires", ""))
	return requires.is_empty() or allocated.has(requires)


## 汇总已分配节点的永久修正：{ stat_key: 累加值 }
static func bonus_of(character_id: String, allocated: Array) -> Dictionary:
	var out: Dictionary = {}
	for node_id: Variant in allocated:
		var node: Dictionary = get_node(character_id, str(node_id))
		if node.is_empty():
			continue  # 存档里可能有旧版本已删除的节点，忽略即可
		for key: Variant in (node.get("stats", {}) as Dictionary).keys():
			var stat_key: String = str(key)
			out[stat_key] = float(out.get(stat_key, 0.0)) + float(node["stats"][key])
	return out


## 某角色已消耗的点数
static func spent_points_of(character_id: String, allocated: Array) -> int:
	var total: int = 0
	for node_id: Variant in allocated:
		var node: Dictionary = get_node(character_id, str(node_id))
		if not node.is_empty():
			total += cost_of(node)
	return total


## 该角色已经点满的层数统计 {branch: 已点层数}
static func progress_by_branch(character_id: String, allocated: Array) -> Dictionary:
	var out: Dictionary = {}
	for branch: String in BRANCHES:
		out[branch] = 0
	for node_id: Variant in allocated:
		var node: Dictionary = get_node(character_id, str(node_id))
		if not node.is_empty():
			var branch: String = str(node.get("branch", ""))
			if out.has(branch):
				out[branch] = int(out[branch]) + 1
	return out


## 该角色是否已点满整棵树
static func is_tree_complete(character_id: String, allocated: Array) -> bool:
	return allocated.size() >= nodes_of(character_id).size()
