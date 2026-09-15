class_name WeaponData
extends Resource
## WeaponData —— 武器数据资源（M3）。
##
## 一把武器的全部手感参数都在这里：伤害、射速、弹速、散射、弹丸数、耗能、
## 暴击加成、击退、穿透、后坐力、屏幕震动、弹道类型（投射 / 激光 / 爆炸 / 追踪 / 近战）。
##
## 数值表集中在 `weapon_db.gd`，本文件只负责"字段定义 + 序列化 + 贴图取用"。
## 新增武器：在 weapon_db.gd 的 TABLE 里加一条即可，无需改本文件。

## 弹道类型
enum Kind {
	PROJECTILE,  ## 普通直射弹（手枪 / 冲锋枪 / 霰弹枪 / 步枪）
	HITSCAN,     ## 即时命中激光（无弹体，沿射线伤害全部目标）
	EXPLOSIVE,   ## 命中后范围爆炸（火箭筒）
	HOMING,      ## 追踪弹（魔杖）
	MELEE,       ## 近战挥砍（短刃）
}

## 稀有度（对应 assets/ui/rarity_0..3.png）
enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY }

const ICON_DIR: String = "res://assets/ui/weapons/"
const SPRITE_DIR: String = "res://assets/weapons/"
const RARITY_NAMES: Array[String] = ["普通", "精良", "稀有", "传说"]

# ---------- 身份 ----------
@export var id: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.PROJECTILE
@export var rarity: Rarity = Rarity.COMMON
@export var description: String = ""
@export var price: int = 60

# ---------- 手感 / 数值 ----------
@export var damage: float = 10.0            ## 单发（单颗弹丸）基础伤害
@export var fire_rate: float = 4.0          ## 每秒射击次数
@export var bullet_speed: float = 420.0     ## 弹速（像素/秒），hitscan / 近战忽略
@export var spread_deg: float = 2.0         ## 散射半角（度）
@export var pellets: int = 1                ## 每次射击弹丸数
@export var energy_cost: float = 2.0        ## 每次射击耗能
@export var crit_bonus: float = 0.05        ## 附加暴击率
@export var knockback: float = 90.0         ## 击退强度（像素/秒冲量）
@export var pierce: int = 0                 ## 穿透敌人数（0 = 命中即消失）
@export var bullet_lifetime: float = 1.6    ## 弹体存活秒数
@export var auto_fire: bool = true          ## 是否可按住连发
@export var recoil: float = 26.0            ## 自身后坐力
@export var shake: float = 1.2              ## 屏幕震动强度
@export var damage_variance: float = 0.1    ## 伤害浮动比例（±10%）

# ---------- 特殊弹道 ----------
@export var beam_range: float = 420.0       ## HITSCAN 射程
@export var explosion_radius: float = 0.0   ## EXPLOSIVE 爆炸半径
@export var homing_strength: float = 0.0    ## HOMING 转向强度（弧度/秒）
@export var melee_range: float = 46.0       ## MELEE 攻击半径
@export var melee_arc_deg: float = 110.0    ## MELEE 扇形半角

# ---------- 表现 ----------
@export var sfx: String = "shoot_pistol"    ## AudioMgr.SFX 的逻辑名
@export var projectile_frames: Array = []   ## 弹体帧（相对 assets/fx/ 的文件名，不含扩展名）
@export var muzzle_offset: float = 13.0     ## 枪口距角色中心的距离

var _icon: Texture2D = null
var _held: Texture2D = null
var _proj_textures: Array[Texture2D] = []


## 两发之间的间隔（秒），未叠加玩家攻速加成
func fire_interval() -> float:
	return 1.0 / maxf(fire_rate, 0.05)


func rarity_name() -> String:
	return RARITY_NAMES[clampi(int(rarity), 0, RARITY_NAMES.size() - 1)]


func is_melee() -> bool:
	return kind == Kind.MELEE


func is_hitscan() -> bool:
	return kind == Kind.HITSCAN


## HUD 用的 20x20 图标
func icon_texture() -> Texture2D:
	if _icon == null:
		var path: String = ICON_DIR + id + ".png"
		if ResourceLoader.exists(path):
			_icon = load(path)
	return _icon


## 角色手上持有的武器贴图
func held_texture() -> Texture2D:
	if _held == null:
		var path: String = SPRITE_DIR + id + ".png"
		if ResourceLoader.exists(path):
			_held = load(path)
	return _held


## 弹体动画帧（懒加载并缓存）
func projectile_textures() -> Array[Texture2D]:
	if not _proj_textures.is_empty():
		return _proj_textures
	for frame_name: Variant in projectile_frames:
		var path: String = "res://assets/fx/" + str(frame_name) + ".png"
		if ResourceLoader.exists(path):
			_proj_textures.append(load(path))
	if _proj_textures.is_empty() and ResourceLoader.exists("res://assets/fx/bullet_p_0.png"):
		_proj_textures.append(load("res://assets/fx/bullet_p_0.png"))
	return _proj_textures


# ==================== 序列化（存档 / 掉落传递） ====================

const FIELDS: Array[String] = [
	"id", "display_name", "kind", "rarity", "description", "price",
	"damage", "fire_rate", "bullet_speed", "spread_deg", "pellets", "energy_cost",
	"crit_bonus", "knockback", "pierce", "bullet_lifetime", "auto_fire", "recoil",
	"shake", "damage_variance", "beam_range", "explosion_radius", "homing_strength",
	"melee_range", "melee_arc_deg", "sfx", "projectile_frames", "muzzle_offset",
]


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for field: String in FIELDS:
		out[field] = get(field)
	return out


func apply_dict(data: Dictionary) -> void:
	for field: String in FIELDS:
		if data.has(field):
			set(field, data[field])


func clone() -> WeaponData:
	var copy := WeaponData.new()
	copy.apply_dict(to_dict())
	return copy
