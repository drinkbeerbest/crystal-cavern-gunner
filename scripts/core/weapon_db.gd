class_name WeaponDB
extends RefCounted
## WeaponDB —— 武器数值表与工厂（M3）。
##
## 全部武器以字典常量定义，`create(id)` 返回一份独立实例（可安全改数值做精英/强化版）。
## GameState 存档反序列化时调用 `WeaponDB.from_dict()`（见 game_state.gd 的 _deserialize_weapons）。
##
## 扩展方式：往 TABLE 里加一条字典，图标放到 assets/ui/weapons/<id>.png、
## 持握贴图放到 assets/weapons/<id>.png、弹体帧放到 assets/fx/，即可被掉落/商店/测试自动识别。

const K := WeaponData.Kind
const R := WeaponData.Rarity

## 武器表：id -> 参数（缺省字段由 _build 用 WeaponData 默认值补齐）
const TABLE: Dictionary = {
	"pistol": {
		"display_name": "晶核手枪", "kind": K.PROJECTILE, "rarity": R.COMMON, "price": 0,
		"damage": 13, "fire_rate": 4.4, "bullet_speed": 430.0, "spread_deg": 2.4,
		"pellets": 1, "energy_cost": 2, "crit_bonus": 0.05, "knockback": 90.0,
		"pierce": 0, "bullet_lifetime": 1.5, "auto_fire": true, "recoil": 22.0, "shake": 1.0,
		"sfx": "shoot_pistol", "projectile_frames": ["bullet_p_0", "bullet_p_1"],
		"description": "制式晶能手枪，耗能极低，稳定可靠。",
	},
	"smg": {
		"display_name": "碎晶冲锋枪", "kind": K.PROJECTILE, "rarity": R.UNCOMMON, "price": 90,
		"damage": 9, "fire_rate": 9.5, "bullet_speed": 470.0, "spread_deg": 6.0,
		"pellets": 1, "energy_cost": 3, "crit_bonus": 0.03, "knockback": 55.0,
		"pierce": 0, "bullet_lifetime": 1.2, "auto_fire": true, "recoil": 16.0, "shake": 0.8,
		"sfx": "shoot_smg", "projectile_frames": ["bullet_p_0", "bullet_p_1"],
		"description": "射速极快但散射偏大，贴脸输出首选。",
	},
	"shotgun": {
		"display_name": "裂岩霰弹枪", "kind": K.PROJECTILE, "rarity": R.UNCOMMON, "price": 110,
		"damage": 10, "fire_rate": 1.5, "bullet_speed": 400.0, "spread_deg": 15.0,
		"pellets": 5, "energy_cost": 8, "crit_bonus": 0.02, "knockback": 190.0,
		"pierce": 0, "bullet_lifetime": 0.55, "auto_fire": false, "recoil": 120.0, "shake": 3.2,
		"sfx": "shoot_shotgun", "projectile_frames": ["bullet_shot"],
		"description": "一次喷出五枚弹丸，近距爆发极高，弹丸飞不远。",
	},
	"rifle": {
		"display_name": "穿晶步枪", "kind": K.PROJECTILE, "rarity": R.RARE, "price": 150,
		"damage": 38, "fire_rate": 1.15, "bullet_speed": 640.0, "spread_deg": 1.0,
		"pellets": 1, "energy_cost": 6, "crit_bonus": 0.12, "knockback": 230.0,
		"pierce": 1, "bullet_lifetime": 1.8, "auto_fire": false, "recoil": 70.0, "shake": 2.2,
		"sfx": "shoot_rifle", "projectile_frames": ["bullet_p_1", "bullet_p_0"],
		"description": "高精度单发步枪，可穿透一名敌人。",
	},
	"laser": {
		"display_name": "聚焦激光枪", "kind": K.HITSCAN, "rarity": R.RARE, "price": 180,
		"damage": 27, "fire_rate": 2.6, "bullet_speed": 0.0, "spread_deg": 0.5,
		"pellets": 1, "energy_cost": 13, "crit_bonus": 0.08, "knockback": 40.0,
		"pierce": 99, "bullet_lifetime": 0.0, "auto_fire": true, "recoil": 12.0, "shake": 1.4,
		"beam_range": 430.0,
		"sfx": "shoot_laser", "projectile_frames": ["bullet_laser"],
		"description": "即时命中的晶能光束，贯穿直线上的一切目标。",
	},
	"rocket": {
		"display_name": "崩岩火箭筒", "kind": K.EXPLOSIVE, "rarity": R.LEGENDARY, "price": 260,
		"damage": 66, "fire_rate": 0.85, "bullet_speed": 300.0, "spread_deg": 1.0,
		"pellets": 1, "energy_cost": 18, "crit_bonus": 0.05, "knockback": 260.0,
		"pierce": 0, "bullet_lifetime": 2.2, "auto_fire": false, "recoil": 150.0, "shake": 4.5,
		"explosion_radius": 62.0,
		"sfx": "shoot_rocket", "projectile_frames": ["bullet_orb"],
		"description": "命中后炸开，对范围内所有敌人造成伤害。",
	},
	"wand": {
		"display_name": "游晶魔杖", "kind": K.HOMING, "rarity": R.RARE, "price": 170,
"damage": 29, "fire_rate": 1.7, "bullet_speed": 285.0, "spread_deg": 9.0,
		"pellets": 1, "energy_cost": 8, "crit_bonus": 0.06, "knockback": 70.0,
		"pierce": 0, "bullet_lifetime": 2.6, "auto_fire": true, "recoil": 10.0, "shake": 1.0,
		"homing_strength": 6.5,
		"sfx": "shoot_wand", "projectile_frames": ["bullet_orb"],
		"description": "射出会自行追踪最近敌人的晶灵弹。",
	},
	"blade": {
		"display_name": "断晶短刃", "kind": K.MELEE, "rarity": R.UNCOMMON, "price": 80,
		"damage": 42, "fire_rate": 1.9, "bullet_speed": 0.0, "spread_deg": 0.0,
		"pellets": 1, "energy_cost": 0, "crit_bonus": 0.1, "knockback": 210.0,
		"pierce": 99, "bullet_lifetime": 0.0, "auto_fire": true, "recoil": 0.0, "shake": 1.6,
		"melee_range": 92.0, "melee_arc_deg": 160.0,
		"sfx": "swing_blade", "projectile_frames": ["slash_0"],
		"description": "不耗能的近战武器，扇形挥砍并强力击退。",
	},
	"gatling": {
		"display_name": "晶能加特林", "kind": K.PROJECTILE, "rarity": R.LEGENDARY, "price": 220,
		"damage": 10, "fire_rate": 12.0, "bullet_speed": 520.0, "spread_deg": 10.0,
		"pellets": 1, "energy_cost": 2, "crit_bonus": 0.02, "knockback": 30.0,
		"pierce": 0, "bullet_lifetime": 0.9, "auto_fire": true, "recoil": 14.0, "shake": 1.0,
		"sfx": "shoot_smg", "projectile_frames": ["bullet_p_0", "bullet_p_1"],
		"description": "极致射速的转管机枪，贴脸消灭一切目标。",
	},
	"sniper": {
		"display_name": "深渊狙击枪", "kind": K.PROJECTILE, "rarity": R.LEGENDARY, "price": 290,
"damage": 98, "fire_rate": 0.65, "bullet_speed": 800.0, "spread_deg": 0.5,
		"pellets": 1, "energy_cost": 15, "crit_bonus": 0.18, "knockback": 320.0,
		"pierce": 2, "bullet_lifetime": 2.5, "auto_fire": false, "recoil": 140.0, "shake": 3.8,
		"sfx": "shoot_rifle", "projectile_frames": ["bullet_p_1"],
		"description": "超远射程与极高穿透，一击必杀的重型武器。",
	},
	"crossbow": {
		"display_name": "晶石穿心箭", "kind": K.PROJECTILE, "rarity": R.RARE, "price": 140,
		"damage": 55, "fire_rate": 1.0, "bullet_speed": 580.0, "spread_deg": 1.5,
		"pellets": 1, "energy_cost": 7, "crit_bonus": 0.1, "knockback": 180.0,
		"pierce": 1, "bullet_lifetime": 1.6, "auto_fire": false, "recoil": 60.0, "shake": 2.0,
		"sfx": "shoot_rifle", "projectile_frames": ["bullet_p_0"],
		"description": "高伤慢速的穿心箭，可穿透一名敌人。",
	},
	"boomerang": {
		"display_name": "回旋晶刃", "kind": K.BOOMERANG, "rarity": R.RARE, "price": 175,
		"damage": 22.0, "fire_rate": 1.35, "bullet_speed": 470.0, "spread_deg": 2.0,
		"pellets": 1, "energy_cost": 6.0, "crit_bonus": 0.08, "knockback": 120.0,
		"pierce": 0, "bullet_lifetime": 2.4, "auto_fire": false, "recoil": 0.0, "shake": 1.0,
		"return_speed": 1.0,
		"sfx": "swing_blade", "projectile_frames": ["slash_0"],
		"description": "脱手后原路飞回：去程和返程都能切开敌人，站位比瞄得更重要。",
	},
	"arc_coil": {
		"display_name": "链式电弧", "kind": K.CHAIN, "rarity": R.RARE, "price": 185,
		"damage": 19.0, "fire_rate": 2.2, "bullet_speed": 700.0, "spread_deg": 1.0,
		"pellets": 1, "energy_cost": 9.0, "crit_bonus": 0.06, "knockback": 60.0,
		"pierce": 0, "bullet_lifetime": 1.1, "auto_fire": true, "recoil": 8.0, "shake": 1.1,
		"chain_targets": 4, "chain_range": 200.0, "chain_falloff": 0.8,
		"sfx": "shoot_laser", "projectile_frames": ["bullet_laser"],
		"description": "命中的瞬间在敌群之间连锁跳跃，最适合扎堆的怪。",
	},
	"seed_mine": {
		"display_name": "晶籽布雷", "kind": K.MINE, "rarity": R.UNCOMMON, "price": 95,
		"damage": 46.0, "fire_rate": 1.1, "bullet_speed": 300.0, "spread_deg": 9.0,
		"pellets": 1, "energy_cost": 5.0, "crit_bonus": 0.05, "knockback": 240.0,
		"pierce": 0, "bullet_lifetime": 0.5, "auto_fire": true, "recoil": 0.0, "shake": 0.6,
		"mine_lifetime": 16.0, "mine_trigger_range": 48.0, "mine_explosion_radius": 82.0,
		"sfx": "empty", "projectile_frames": ["bullet_orb"],
		"description": "沿途撒下晶籽，敌人踩上去才炸。倒着往后走是安全的。",
	},
	"ricochet_core": {
		"display_name": "跳弹核", "kind": K.RICOCHET, "rarity": R.RARE, "price": 165,
		"damage": 24.0, "fire_rate": 1.8, "bullet_speed": 560.0, "spread_deg": 2.0,
		"pellets": 1, "energy_cost": 7.0, "crit_bonus": 0.07, "knockback": 90.0,
		"pierce": 0, "bullet_lifetime": 2.6, "auto_fire": true, "recoil": 6.0, "shake": 0.9,
		"ricochet_times": 4,
		"sfx": "shoot_pistol", "projectile_frames": ["bullet_p_1"],
		"description": "撞墙不消失而是改变方向继续飞，在狭小房间里伤害翻倍。",
	},
	"cryo_pistol": {
		"display_name": "寒晶手枪", "kind": K.FROST, "rarity": R.UNCOMMON, "price": 120,
		"damage": 11.0, "fire_rate": 5.0, "bullet_speed": 500.0, "spread_deg": 2.0,
		"pellets": 1, "energy_cost": 2.0, "crit_bonus": 0.04, "knockback": 60.0,
		"pierce": 0, "bullet_lifetime": 1.2, "auto_fire": true, "recoil": 12.0, "shake": 0.8,
		"slow_factor": 0.42, "slow_duration": 2.8,
		"sfx": "shoot_pistol", "projectile_frames": ["bullet_p_0", "bullet_p_1"],
		"description": "单发很弱，但会把命中的敌人冻慢——控场用武器，叠攻速收益最高。",
	},
	"shard_nova": {
		"display_name": "碎晶环刃", "kind": K.BOOMERANG, "rarity": R.LEGENDARY, "price": 245,
		"damage": 17.0, "fire_rate": 1.6, "bullet_speed": 520.0, "spread_deg": 6.0,
		"pellets": 3, "energy_cost": 8.0, "crit_bonus": 0.1, "knockback": 100.0,
		"pierce": 0, "bullet_lifetime": 2.2, "auto_fire": false, "recoil": 0.0, "shake": 1.3,
		"return_speed": 1.25,
		"sfx": "swing_blade", "projectile_frames": ["slash_0"],
		"description": "一次甩出三枚环刃，去返两轮共六次切割。贴脸时收益最高。",
	},
	"warden_coil": {
		"display_name": "守望电枢", "kind": K.CHAIN, "rarity": R.LEGENDARY, "price": 265,
		"damage": 25.0, "fire_rate": 1.9, "bullet_speed": 760.0, "spread_deg": 1.0,
		"pellets": 1, "energy_cost": 11.0, "crit_bonus": 0.1, "knockback": 70.0,
		"pierce": 0, "bullet_lifetime": 1.2, "auto_fire": true, "recoil": 8.0, "shake": 1.2,
		"chain_targets": 6, "chain_range": 240.0, "chain_falloff": 0.88,
		"sfx": "shoot_laser", "projectile_frames": ["bullet_laser"],
		"description": "六段连锁、衰减极低。精英房里一发能串起整波怪。",
	},
	"grenade_launcher": {
		"display_name": "崩裂爆弹枪", "kind": K.EXPLOSIVE, "rarity": R.RARE, "price": 210,
		"damage": 53, "fire_rate": 1.3, "bullet_speed": 240.0, "spread_deg": 3.0,
		"pellets": 1, "energy_cost": 14, "crit_bonus": 0.04, "knockback": 200.0,
		"pierce": 0, "bullet_lifetime": 1.8, "auto_fire": false, "recoil": 110.0, "shake": 3.5,
		"explosion_radius": 55.0,
		"sfx": "shoot_rocket", "projectile_frames": ["bullet_orb"],
		"description": "发射延时爆弹，对落点周围造成范围杀伤。",
	},
}

## 起始武器
const STARTER_ID: String = "pistol"

## 掉落权重（按稀有度，层数越高稀有度权重越大）
const RARITY_WEIGHTS: Dictionary = {
	0: {0: 70.0, 1: 24.0, 2: 6.0, 3: 0.0},
	1: {0: 45.0, 1: 34.0, 2: 17.0, 3: 4.0},
	2: {0: 26.0, 1: 32.0, 2: 30.0, 3: 12.0},
	3: {0: 14.0, 1: 26.0, 2: 38.0, 3: 22.0},
}

const G := preload("res://scripts/core/game_const.gd")


static func ids() -> Array:
	return TABLE.keys()


static func has_weapon(weapon_id: String) -> bool:
	return TABLE.has(weapon_id)


## 生成一把新武器实例（每次调用都是独立对象）
static func create(weapon_id: String) -> WeaponData:
	if not TABLE.has(weapon_id):
		push_warning("WeaponDB: 未知武器 id '%s'" % weapon_id)
		return null
	var data := WeaponData.new()
	data.id = weapon_id
	data.apply_dict(TABLE[weapon_id])
	return data


static func starter() -> WeaponData:
	return create(STARTER_ID)


static func all() -> Array:
	var out: Array = []
	for weapon_id: Variant in TABLE.keys():
		out.append(create(str(weapon_id)))
	return out


## 三把标准初始/试验武器（手枪 / 霰弹枪 / 激光枪）
static func core_three() -> Array:
	return [create("pistol"), create("shotgun"), create("laser")]


## 开局武器组：按玩家图鉴设定的 3 把武器 id 生成实例列表。
## 去重处理（同一 id 只保留一份），不足 3 把时从核心三把补全。
static func starter_kit(kit_ids: Array[String]) -> Array:
	var out: Array = []
	var seen: Array[String] = []
	for weapon_id: String in kit_ids:
		if weapon_id.is_empty():
			continue
		var weapon: WeaponData = create(weapon_id)
		if weapon != null and not seen.has(weapon_id):
			out.append(weapon)
			seen.append(weapon_id)
	# 补全到 3 把（从核心三把按优先级）
	for weapon: Variant in core_three():
		if out.size() >= 3:
			break
		if not seen.has(str(weapon.id)):
			out.append(create(str(weapon.id)))
			seen.append(str(weapon.id))
	return out


static func from_dict(data: Dictionary) -> WeaponData:
	var weapon_id: String = str(data.get("id", ""))
	if not TABLE.has(weapon_id):
		return null
	var weapon: WeaponData = create(weapon_id)
	weapon.apply_dict(data)
	return weapon


## 按层数随机一把武器（rng 由 GameState 提供，保证同种子可复现）
static func random(rng: RandomNumberGenerator, floor_index: int = 1) -> WeaponData:
	var weights: Dictionary = RARITY_WEIGHTS.get(clampi(floor_index, 0, 3), RARITY_WEIGHTS[0])
	var rarity: Variant = G.weighted_pick(weights, rng)
	var candidates: Array = []
	for weapon_id: Variant in TABLE.keys():
		var entry: Dictionary = TABLE[weapon_id]
		if int(entry.get("rarity", 0)) == int(rarity) and int(entry.get("price", 0)) > 0:
			candidates.append(str(weapon_id))
	if candidates.is_empty():
		for weapon_id: Variant in TABLE.keys():
			if int(TABLE[weapon_id].get("price", 0)) > 0:
				candidates.append(str(weapon_id))
	if candidates.is_empty():
		return starter()
	return create(candidates[rng.randi_range(0, candidates.size() - 1)])


## 商店货架：按层数取 n 把不重复武器
static func shop_offer(rng: RandomNumberGenerator, floor_index: int, count: int = 3) -> Array:
	var pool: Array = []
	for weapon_id: Variant in TABLE.keys():
		if int(TABLE[weapon_id].get("price", 0)) > 0:
			pool.append(str(weapon_id))
	var out: Array = []
	while out.size() < count and not pool.is_empty():
		var idx: int = rng.randi_range(0, pool.size() - 1)
		out.append(create(pool[idx]))
		pool.remove_at(idx)
	return out
