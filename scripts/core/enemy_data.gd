class_name EnemyData
extends Resource
## EnemyData —— 敌人数值资源（M4）。
##
## 一个敌人的全部参数都在这里：生存、移动、接触伤害，以及三套按 archetype 取用的
## 行为参数（近战冲锋 / 远程射击 / 自爆），外加掉落表与贴图信息。
##
## 数值表集中在 `enemy_db.gd`，本文件只负责"字段定义 + 序列化 + 贴图取用 + 掉落摇奖"。
## 新增敌人：在 enemy_db.gd 的 TABLE 里加一条，并把贴图放到 assets/sprites/enemies/ 即可。

const G := preload("res://scripts/core/game_const.gd")

## 行为原型：决定用哪个 Enemy 子类
enum Archetype { MELEE, RANGED, BOMBER, BOSS, STALKER, SPLITTER, BURROWER, SUMMONER }
## 强度档位：精英血量/伤害/掉落更好，贴图带 _elite 后缀
enum Tier { NORMAL, ELITE }

const SPRITE_DIR: String = "res://assets/sprites/enemies/"

# ---------- 身份 ----------
@export var id: String = ""
@export var display_name: String = ""
@export var archetype: Archetype = Archetype.MELEE
@export var tier: Tier = Tier.NORMAL
@export var description: String = ""

# ---------- 生存 / 移动 ----------
@export var max_health: float = 30.0
@export var armor: float = 0.0             ## 固定减伤（每次受击减去，最低 1）
@export var move_speed: float = 92.0       ## 像素/秒
@export var body_radius: float = 7.0       ## 碰撞半径
@export var knockback_resist: float = 0.0  ## 0~1，越大越不吃击退
@export var sight_range: float = 330.0     ## 索敌半径
@export var score: int = 10                ## 击杀得分（结算用）

# ---------- 接触伤害（贴脸掉血） ----------
@export var contact_damage: float = 7.0
@export var contact_cooldown: float = 0.7

# ---------- MELEE：蓄力 -> 冲刺撞击 ----------
@export var charge_trigger_range: float = 132.0  ## 进入该距离才会起手
@export var charge_windup: float = 0.34          ## 起手预警时长
@export var charge_speed: float = 320.0          ## 冲刺速度
@export var charge_duration: float = 0.44        ## 冲刺最长时长
@export var charge_damage: float = 15.0          ## 撞击伤害
@export var charge_knockback: float = 250.0
@export var charge_cooldown: float = 1.9         ## 两次冲刺间隔
@export var charge_stun_on_wall: float = 0.42    ## 撞墙后眩晕时长

# ---------- RANGED：保持距离 -> 预警 -> 射击 ----------
@export var preferred_range: float = 152.0       ## 理想交战距离
@export var keep_distance_min: float = 96.0      ## 比这更近就后退
@export var aim_time: float = 0.42               ## 开火前预警（玩家可躲）
@export var fire_interval: float = 1.7           ## 两轮之间的间隔
@export var burst_count: int = 1                 ## 一轮几发
@export var burst_interval: float = 0.15         ## 连发间隔
@export var bullet_damage: float = 9.0
@export var bullet_speed: float = 265.0
@export var bullet_lifetime: float = 2.4
@export var bullet_radius: float = 4.0
@export var spread_deg: float = 3.0              ## 单发散布半角
@export var strafe_strength: float = 34.0        ## 横向游走速度

# ---------- BOMBER：接近 -> 蓄力 -> 自爆 ----------
@export var fuse_trigger_range: float = 48.0     ## 进入该距离开始引爆倒计时
@export var fuse_time: float = 0.78              ## 蓄力时长（可被打断/提前击杀）
@export var explosion_radius: float = 64.0
@export var explosion_damage: float = 32.0
@export var explosion_knockback: float = 300.0
@export var explode_on_death: bool = true        ## 被击杀时是否仍然炸开
@export var death_explosion_ratio: float = 0.7   ## 被击杀引爆的伤害占比
@export var wobble: float = 26.0                 ## 移动时的左右摆动幅度

# ---------- STALKER：潜行 -> 显形突刺 ----------
@export var strike_trigger_range: float = 96.0   ## 潜行到多近开始显形
## 显形前摇时长：玩家唯一的反应窗口。
## 隐形怪的平衡全押在这一项上——它给得越短，玩家越是「被白嫖」。
@export var reveal_time: float = 0.85
@export var strike_speed: float = 430.0          ## 突刺速度
@export var strike_duration: float = 0.32        ## 突刺最长时长
@export var strike_damage: float = 18.0
@export var strike_knockback: float = 300.0

# ---------- SPLITTER：死亡分裂 ----------
@export var split_into: String = ""              ## 碎片 id（留空 = 不会分裂）
@export var shard_contact_damage: float = 5.0   ## 碎片贴脸伤害（比母体低）

# ---------- BURROWER：钻地穿墙 -> 破土 ----------
@export var erupt_trigger_range: float = 120.0  ## 潜行到多近开始预警破土
@export var erupt_damage: float = 22.0
@export var erupt_knockback: float = 340.0

# ---------- SUMMONER：持续召唤 ----------
## summon_ring  召唤点距离自身的半径
## summon_life  召唤物的存活时间（秒）：到点自毁，所以"放着不管"不是解
## summon_clear_delay 复用 BOSS 段的同名字段，两者语义相同（召唤物清空后的禁召期）
@export var summon_ring: float = 46.0
@export var summon_life: float = 9.0

# ---------- BOSS：阶段 / 弹幕 / 召唤 / 砸地 ----------
@export var phase_threshold: float = 0.5         ## 血量比例低于该值进入阶段 2
@export var boss_sprite_scale: float = 1.0       ## Boss 贴图额外缩放（素材本身已比普通怪大）
@export var skill_interval: float = 1.4          ## 两个技能之间的走位喘息
@export var strafe_speed: float = 46.0           ## 走位时的横移速度
## 环形弹幕：一次性向四周均匀撒弹
@export var radial_count: int = 14
@export var radial_waves: int = 2                ## 一次技能撒几圈（圈间有角度错位）
@export var radial_wave_interval: float = 0.26
@export var radial_damage: float = 10.0
@export var radial_speed: float = 185.0
@export var radial_cooldown: float = 4.6
@export var radial_telegraph: float = 0.5
## 扇形弹幕：锁定玩家方向连喷
@export var fan_count: int = 7
@export var fan_spread_deg: float = 46.0
@export var fan_bursts: int = 3
@export var fan_burst_interval: float = 0.18
@export var fan_damage: float = 9.0
@export var fan_speed: float = 240.0
@export var fan_cooldown: float = 3.8
@export var fan_aim_time: float = 0.42
## 螺旋弹幕：边转身边持续吐弹
@export var spiral_arms: int = 3
@export var spiral_step_deg: float = 17.0
@export var spiral_ticks: int = 16
@export var spiral_interval: float = 0.1
@export var spiral_damage: float = 8.0
@export var spiral_speed: float = 165.0
@export var spiral_cooldown: float = 7.0
## 召唤小怪
@export var summon_ids: Array = ["husk"]         ## 从 EnemyDB 里取的敌人 id
@export var summon_count: int = 3
@export var summon_cap: int = 6                  ## 场上非 Boss 小怪上限
@export var summon_cooldown: float = 11.0
@export var summon_windup: float = 0.7
## 召唤物被清空后的「喘息期」（秒）：这段时间内 Boss 不许再召唤。
## 没有它的话，Boss 会把小怪丢出去→玩家清掉→冷却刚好转好→立刻再丢，
## 整场战斗变成无限刷杂兵，玩家永远等不到一个能喘口气的反打窗口。
@export var summon_clear_delay: float = 6.0
## 砸地：贴脸时的范围伤害
@export var slam_radius: float = 92.0
@export var slam_damage: float = 22.0
@export var slam_knockback: float = 260.0
@export var slam_windup: float = 0.45
@export var slam_cooldown: float = 5.2
@export var slam_trigger_range: float = 110.0

# ---------- BOSS：M9 新增三招 ----------
## 扫射激光：持续站在光束里就持续掉血，逼玩家"跑出扇区"而不是"在弹流里找空隙"
@export var sweep_degrees: float = 80.0        ## 来回扫过的总角度
@export var sweep_half_width_deg: float = 7.0 ## 光束半宽
@export var sweep_length: float = 340.0        ## 光束长度
@export var sweep_duration: float = 1.6        ## 扫射持续时间
@export var sweep_dps: float = 26.0            ## 每秒伤害
@export var sweep_windup: float = 0.7
@export var sweep_cooldown: float = 8.0
## 追踪导弹：分批慢速弹，作用是逼玩家换位而不是秒杀
@export var missile_count: int = 3             ## 每批几枚
@export var missile_damage: float = 14.0
@export var missile_speed: float = 150.0       ## 刻意慢：慢才可读、可躲
@export var missile_homing: float = 1.6
@export var missile_wave_interval: float = 0.35
@export var missile_windup: float = 0.6
@export var missile_cooldown: float = 7.0
## 闪现：瞬移到玩家附近并炸一圈。落点必有预警圈，否则就是纯 unfair
@export var blink_range: float = 190.0         ## 落点相对玩家的散布半径
@export var blink_blast_radius: float = 78.0
@export var blink_damage: float = 24.0
@export var blink_knockback: float = 380.0
@export var blink_windup: float = 0.55
## 位移途中的时间（这期间 Boss 不参与碰撞，玩家也打不到它）
@export var blink_travel_time: float = 0.14
@export var blink_cooldown: float = 6.0

## 阶段 2 强化
@export var phase2_speed_mul: float = 1.14
@export var phase2_cooldown_mul: float = 0.78
@export var phase2_extra_bullets: int = 4

# ---------- 掉落 ----------
@export var gold_min: int = 2
@export var gold_max: int = 6
@export var energy_amount: float = 12.0
@export var health_amount: float = 18.0
@export var shield_amount: float = 15.0
## 掉落概率表：键为 PickupKind 的逻辑名，值为 0~1 概率（luck 会整体放大）
@export var drops: Dictionary = {
	"energy": 0.34, "health": 0.10, "shield_cell": 0.06, "bomb": 0.04, "weapon": 0.02, "talent": 0.02,
}

# ---------- 表现 ----------
@export var sprite_base: String = "husk"   ## <sprite_dir><base>_<frame>.png
@export var sprite_dir: String = ""        ## 贴图目录覆盖（Boss 在 assets/sprites/bosses/），留空用 SPRITE_DIR
@export var frame_count: int = 3
@export var anim_fps: float = 9.0
@export var sprite_offset: Vector2 = Vector2(0, -4)
@export var sfx_hurt: String = "enemy_hurt"
@export var sfx_die: String = "enemy_die"
@export var sfx_attack: String = "swing_blade"
@export var sfx_shoot: String = "shoot_smg"
@export var sfx_fuse: String = "boss_charge"

var _frames: Array[Texture2D] = []
var _charge_levels: Dictionary = {}


# ==================== 贴图 ====================

func is_elite() -> bool:
	return tier == Tier.ELITE


## 贴图目录：默认敌人目录，Boss 等可用 sprite_dir 覆盖
func sprite_dir_path() -> String:
	return sprite_dir if sprite_dir != "" else SPRITE_DIR


## 贴图路径：普通 `husk_0.png`，精英 `husk_elite_0.png`
func sprite_path(frame_index: int) -> String:
	var suffix: String = "_elite" if is_elite() else ""
	return sprite_dir_path() + "%s%s_%d.png" % [sprite_base, suffix, clampi(frame_index, 0, frame_count - 1)]


## 普通帧序列（懒加载缓存）
func frames() -> Array[Texture2D]:
	if not _frames.is_empty():
		return _frames
	for i: int in range(frame_count):
		var path: String = sprite_path(i)
		if ResourceLoader.exists(path):
			_frames.append(load(path))
	return _frames


## 自爆蓄力帧（bloom_<frame>_c<level>.png，level 1~3），缺帧时回退普通帧
func charge_frames(level: int) -> Array[Texture2D]:
	var key: int = clampi(level, 1, 3)
	if _charge_levels.has(key):
		return _charge_levels[key]
	var list: Array[Texture2D] = []
	for i: int in range(frame_count):
		var path: String = SPRITE_DIR + "%s_%d_c%d.png" % [sprite_base, i, key]
		if ResourceLoader.exists(path):
			list.append(load(path))
	if list.is_empty():
		list = frames()
	_charge_levels[key] = list
	return list


# ==================== 掉落摇奖 ====================

## 摇一次掉落。返回 [{kind: G.PickupKind, amount: float}]，金币必然出现在最前（若有）。
## luck 为玩家幸运值（0~1），线性放大非金币掉落概率。
func roll_drops(rng: RandomNumberGenerator, luck: float = 0.0) -> Array:
	var out: Array = []
	var gold: int = rng.randi_range(gold_min, gold_max)
	if gold > 0:
		out.append({"kind": G.PickupKind.COIN, "amount": float(gold)})
	for key: Variant in drops.keys():
		var chance: float = clampf(float(drops[key]) * (1.0 + maxf(luck, 0.0)), 0.0, 1.0)
		if chance <= 0.0 or rng.randf() > chance:
			continue
		out.append(_make_drop(str(key)))
	return out


func _make_drop(key: String) -> Dictionary:
	match key:
		"energy":
			return {"kind": G.PickupKind.ENERGY, "amount": energy_amount}
		"health":
			return {"kind": G.PickupKind.HEALTH, "amount": health_amount}
		"shield_cell":
			return {"kind": G.PickupKind.SHIELD_CELL, "amount": shield_amount}
		"bomb":
			return {"kind": G.PickupKind.BOMB, "amount": 1.0}
		"weapon":
			return {"kind": G.PickupKind.WEAPON, "amount": 1.0}
		"talent":
			return {"kind": G.PickupKind.TALENT, "amount": 1.0}
	return {"kind": G.PickupKind.COIN, "amount": 1.0}


## 掉落条目数量统计（测试用）：按 kind 归并计数
static func count_kinds(drops: Array) -> Dictionary:
	var counts: Dictionary = {}
	for drop: Variant in drops:
		if not (drop is Dictionary):
			continue
		var kind: int = int((drop as Dictionary).get("kind", -1))
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


# ==================== 序列化 ====================

const FIELDS: Array[String] = [
	"id", "display_name", "archetype", "tier", "description",
	"max_health", "armor", "move_speed", "body_radius", "knockback_resist", "sight_range", "score",
	"contact_damage", "contact_cooldown",
	"charge_trigger_range", "charge_windup", "charge_speed", "charge_duration", "charge_damage",
	"charge_knockback", "charge_cooldown", "charge_stun_on_wall",
	"preferred_range", "keep_distance_min", "aim_time", "fire_interval", "burst_count",
	"burst_interval", "bullet_damage", "bullet_speed", "bullet_lifetime", "bullet_radius",
	"spread_deg", "strafe_strength",
	"fuse_trigger_range", "fuse_time", "explosion_radius", "explosion_damage",
	"explosion_knockback", "explode_on_death", "death_explosion_ratio", "wobble",
	"strike_trigger_range", "reveal_time", "strike_speed", "strike_duration",
	"strike_damage", "strike_knockback",
	"split_into", "shard_contact_damage",
	"erupt_trigger_range", "erupt_damage", "erupt_knockback",
	"summon_ring", "summon_life", "summon_clear_delay",
	"phase_threshold", "boss_sprite_scale", "skill_interval", "strafe_speed",
	"radial_count", "radial_waves", "radial_wave_interval", "radial_damage", "radial_speed",
	"radial_cooldown", "radial_telegraph",
	"fan_count", "fan_spread_deg", "fan_bursts", "fan_burst_interval", "fan_damage",
	"fan_speed", "fan_cooldown", "fan_aim_time",
	"spiral_arms", "spiral_step_deg", "spiral_ticks", "spiral_interval", "spiral_damage",
	"spiral_speed", "spiral_cooldown",
	"summon_ids", "summon_count", "summon_cap", "summon_cooldown", "summon_windup",
	"summon_clear_delay",
	"slam_radius", "slam_damage", "slam_knockback", "slam_windup", "slam_cooldown",
	"slam_trigger_range",
	"sweep_degrees", "sweep_half_width_deg", "sweep_length", "sweep_duration", "sweep_dps",
	"sweep_windup", "sweep_cooldown",
	"missile_count", "missile_damage", "missile_speed", "missile_homing",
	"missile_wave_interval", "missile_windup", "missile_cooldown",
	"blink_range", "blink_blast_radius", "blink_damage", "blink_knockback",
	"blink_windup", "blink_travel_time", "blink_cooldown",
	"phase2_speed_mul", "phase2_cooldown_mul", "phase2_extra_bullets",
	"gold_min", "gold_max", "energy_amount", "health_amount", "shield_amount", "drops",
	"sprite_base", "sprite_dir", "frame_count", "anim_fps", "sprite_offset",
	"sfx_hurt", "sfx_die", "sfx_attack", "sfx_shoot", "sfx_fuse",
]


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for field: String in FIELDS:
		out[field] = get(field)
	return out


func apply_dict(values: Dictionary) -> void:
	for field: String in FIELDS:
		if values.has(field):
			set(field, values[field])


func clone() -> EnemyData:
	var copy := EnemyData.new()
	copy.apply_dict(to_dict())
	return copy


## 按层数放大数值（返回自身，方便链式调用）。第 1 层为基准，不做任何放大。
func scale_for_floor(floor_index: int) -> EnemyData:
	var level: int = clampi(floor_index, 1, 8) - 1
	if level <= 0:
		return self
	max_health = roundf(max_health * (1.0 + G.ENEMY_HP_GROWTH_PER_FLOOR * float(level)))
	contact_damage = roundf(contact_damage * (1.0 + G.ENEMY_DAMAGE_GROWTH_PER_FLOOR * float(level)))
	charge_damage = roundf(charge_damage * (1.0 + G.ENEMY_DAMAGE_GROWTH_PER_FLOOR * float(level)))
	bullet_damage = roundf(bullet_damage * (1.0 + G.ENEMY_DAMAGE_GROWTH_PER_FLOOR * float(level)))
	explosion_damage = roundf(explosion_damage * (1.0 + G.ENEMY_DAMAGE_GROWTH_PER_FLOOR * float(level)))
	move_speed = roundf(move_speed * (1.0 + G.ENEMY_SPEED_GROWTH_PER_FLOOR * float(level)))
	gold_min = gold_min + level
	gold_max = gold_max + level * 2
	score = score + level * 5
	return self
