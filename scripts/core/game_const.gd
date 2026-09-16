extends Node
## GameConst —— 全局常量与平衡性默认值（静态类，无需实例化）。
##
## 所有数值集中在这里，方便调平衡；新增内容（武器/敌人/房间）也应优先复用这些常量。

# ---------- 像素与相机 ----------
## 一个瓦片的边长（素材按 32x32 出图：floor / wall_top；墙面 wall_face 为 32x40）
const TILE_SIZE: int = 32
## 相机缩放：1280x720 视口下可见约 640x360 世界像素（20x11 瓦片）
const CAMERA_ZOOM: float = 2.0
## 房间尺寸（单位：瓦片，含四周墙体），随机在其中挑选
const ROOM_SIZES: Array[Vector2i] = [
	Vector2i(21, 13), Vector2i(25, 15), Vector2i(27, 15), Vector2i(29, 17),
]
const BOSS_ROOM_SIZE: Vector2i = Vector2i(33, 21)
const START_ROOM_SIZE: Vector2i = Vector2i(19, 13)

# ---------- 地牢 ----------
const MIN_ROOMS_PER_FLOOR: int = 5
const MAX_ROOMS_PER_FLOOR: int = 10
const TOTAL_FLOORS: int = 3

# ---------- 物理层（位掩码，必须是 2 的幂） ----------
const LAYER_WORLD: int = 1
const LAYER_PLAYER: int = 2
const LAYER_ENEMY: int = 4
const LAYER_PLAYER_BULLET: int = 8
const LAYER_ENEMY_BULLET: int = 16
const LAYER_PICKUP: int = 32
const LAYER_INTERACT: int = 64

const MASK_PLAYER: int = LAYER_WORLD | LAYER_ENEMY
const MASK_ENEMY: int = LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY
const MASK_PLAYER_BULLET: int = LAYER_WORLD | LAYER_ENEMY
const MASK_ENEMY_BULLET: int = LAYER_WORLD | LAYER_PLAYER
const MASK_PICKUP: int = LAYER_PLAYER
const MASK_INTERACT: int = LAYER_PLAYER

# ---------- 玩家默认属性 ----------
## 生命 / 护盾 / 能量 / 金币 / 移速 / 暴击 等，全部可被天赋与装备修改
const DEFAULT_PLAYER_STATS: Dictionary = {
	"max_health": 100.0,
	"health": 100.0,
	"max_shield": 50.0,
	"shield": 50.0,
	"shield_regen_delay": 4.0,      # 受击后多少秒开始回盾
	"shield_regen_rate": 9.0,       # 每秒回复护盾
	"max_energy": 100.0,
	"energy": 100.0,
	"energy_regen": 7.0,            # 每秒回复能量（低于三把主武器的耗能速率，能量才是真资源）
	"move_speed": 205.0,            # 像素/秒
	"dash_speed": 640.0,
	"dash_duration": 0.16,
	"dash_cooldown": 0.85,
	"skill_cooldown": 4.8,
	"crit_chance": 0.10,
	"crit_multiplier": 1.8,
	"damage_multiplier": 1.0,
	"attack_speed_multiplier": 1.0,
	"bullet_speed_multiplier": 1.0,
	"knockback_multiplier": 1.0,
	"pickup_radius": 74.0,
	"armor": 0.0,                   # 固定减伤
	"luck": 0.0,                    # 影响掉落品质
}

const START_GOLD: int = 0

# ---------- 玩家战斗常量 ----------
## 出生保护时长（秒）
const SPAWN_PROTECTION: float = 1.2
## 受击后的无敌帧时长
const INVULN_AFTER_HIT: float = 0.55
## 武器栏位数
const MAX_WEAPON_SLOTS: int = 3
## 切枪硬直（秒）
const WEAPON_SWITCH_DELAY: float = 0.22
## 交互半径（像素）
const INTERACT_RADIUS: float = 30.0
## 玩家碰撞半径
const PLAYER_BODY_RADIUS: float = 6.0

# ---------- 技能：晶能冲击波 ----------
const SKILL_ID: String = "shockwave"
const SKILL_ENERGY_COST: float = 20.0
const SKILL_DAMAGE: float = 44.0
const SKILL_RADIUS: float = 115.0
const SKILL_KNOCKBACK: float = 380.0

# ---------- 爆炸 ----------
## 火箭等爆炸弹的直接命中伤害占比（范围伤害另按距离衰减）
const EXPLOSION_SELF_RATIO: float = 0.85

# ---------- 敌人 ----------
## 生成后多久解除"凝聚"状态并开始行动（留出登场特效时间）
const ENEMY_ACTIVATE_DELAY: float = 0.42
## 死亡动画（缩小淡出）时长，结束后自动释放节点
const ENEMY_DEATH_ANIM_TIME: float = 0.34
## 敌人之间的最小间隔余量（避免完全重叠成一坨）
const ENEMY_SEPARATION_PADDING: float = 3.0
## 分离力的最大强度（像素/秒），过大时会把敌人推出墙体
const ENEMY_SEPARATION_MAX: float = 130.0
## 每层数值成长率（第 1 层为基准）
const ENEMY_HP_GROWTH_PER_FLOOR: float = 0.35
const ENEMY_DAMAGE_GROWTH_PER_FLOOR: float = 0.25
const ENEMY_SPEED_GROWTH_PER_FLOOR: float = 0.04
## 受击硬直（打断冲锋/瞄准的短暂失控）
const ENEMY_FLINCH_TIME: float = 0.1

# ---------- 波次配置 ----------
## 房型 -> 第 1 层的基础敌人数（键为 RoomKind 的整数值：1=COMBAT 2=ELITE 3=TREASURE 5=BOSS）
## START(0) 与 SHOP(4) 不出怪；BOSS(5) 的怪由 M7 的 Boss 流程单独生成。
const WAVE_BASE_COUNT: Dictionary = {1: 4, 2: 6, 3: 2}
## 每深入一层，每个房间多出多少敌人
const WAVE_COUNT_PER_FLOOR: int = 1
## 单房间敌人数量上限（避免小房间挤爆）
const WAVE_MAX_COUNT: int = 12
## 每层把普通怪替换成精英怪的概率（键为层数，超出取最后一档）
const WAVE_ELITE_CHANCE: Dictionary = {1: 0.0, 2: 0.14, 3: 0.26}
## 每层的类型权重（键为层数）：近战 / 远程 / 自爆
const WAVE_TYPE_WEIGHTS: Dictionary = {
	1: {"husk": 50.0, "hexeye": 32.0, "bloom": 18.0},
	2: {"husk": 38.0, "hexeye": 34.0, "bloom": 28.0},
	3: {"husk": 32.0, "hexeye": 34.0, "bloom": 34.0},
}
## 一波拆成几批投放，以及批次之间的间隔（秒）
const WAVE_BATCHES: int = 2
const WAVE_BATCH_DELAY: float = 3.2
## 生成点与玩家的最小距离（不给玩家贴脸刷怪）
const WAVE_MIN_DISTANCE_TO_PLAYER: float = 96.0
## 生成点距墙/障碍的最小余量（像素）
const WAVE_SPAWN_MARGIN: float = 14.0

# ---------- 掉落物类型 ----------
enum PickupKind {
	COIN,        # 金币
	ENERGY,      # 能量球
	HEALTH,      # 血包
	WEAPON,      # 随机武器
	TALENT,      # 临时天赋
	BOMB,        # 炸弹（可投掷）
	SHIELD_CELL, # 护盾电池
}

# ---------- 拾取物行为 ----------
## 在场时长（秒），到期前一段时间开始闪烁提示
const PICKUP_LIFETIME: float = 24.0
const PICKUP_BLINK_TIME: float = 3.5
## 掉落撒开：出手初速与减速时间（避免一堆金币重叠在同一点）
const PICKUP_SCATTER_SPEED: float = 96.0
const PICKUP_SCATTER_TIME: float = 0.26
## 吸附：进入吸附半径后被拉向玩家，最大追踪速度（像素/秒）
const PICKUP_MAGNET_SPEED: float = 470.0
## 吸附半径下限（玩家 pickup_radius 被削弱时也不至于捡不到东西）
const PICKUP_MAGNET_MIN: float = 34.0
## 拾取判定半径（与玩家身体半径相加后使用）
const PICKUP_COLLECT_RADIUS: float = 9.0
## 上下浮动的幅度与速度（像素 / 弧度每秒）
const PICKUP_BOB_HEIGHT: float = 2.0
const PICKUP_BOB_SPEED: float = 4.2
## 默认回复量（掉落表没给 amount 时兜底）
const PICKUP_HEAL: float = 18.0
const PICKUP_HEAL_BIG: float = 40.0
const PICKUP_ENERGY: float = 16.0
const PICKUP_SHIELD: float = 15.0
## 单枚金币价值浮动（掉落表给的 amount 为总金币数，此处用于宝箱/祭坛等自行生成金币）
const COIN_VALUE_MIN: int = 2
const COIN_VALUE_MAX: int = 6

# ---------- 炸弹 ----------
## 开局携带数量与持有上限
const START_BOMBS: int = 2
const MAX_BOMBS: int = 9
## 出手初速与最远飞行距离（超过就落地）
const BOMB_THROW_SPEED: float = 300.0
const BOMB_THROW_RANGE: float = 138.0
## 落地后的引信时长（秒）
const BOMB_FUSE: float = 1.0
## 爆炸半径 / 伤害 / 击退
const BOMB_RADIUS: float = 98.0
const BOMB_DAMAGE: float = 75.0
const BOMB_KNOCKBACK: float = 390.0
## 两次投掷的最小间隔
const BOMB_COOLDOWN: float = 0.34
## 玩家自伤比例（避免贴脸炸自己秒杀）
const BOMB_SELF_DAMAGE_RATIO: float = 0.3

# ---------- 临时天赋 ----------
## 同时生效的天赋上限（超出时最早到期的先被顶掉）
const TALENT_MAX_SLOTS: int = 3
## 天赋默认持续时长（秒），天赋表未指定时使用
const TALENT_DEFAULT_DURATION: float = 25.0

# ---------- 祭坛 / 商店 ----------
## 祭坛：花金币换随机天赋或炸弹，每座祭坛可用次数有限
const ALTAR_TALENT_PRICE: int = 30
const ALTAR_BOMB_PRICE: int = 18
const ALTAR_USE_LIMIT: int = 2
## 商店新增货品价格
const SHOP_TALENT_PRICE: int = 55
const SHOP_BOMB_PRICE: int = 20

# ---------- 房间类型 ----------
enum RoomKind {
	START,     # 起始房
	COMBAT,    # 普通战斗房
	ELITE,     # 精英房（更强敌人 + 更好掉落）
	TREASURE,  # 宝箱房
	SHOP,      # 商店房
	BOSS,      # Boss 房
}

# ---------- 伤害来源 ----------
enum DamageSource { PLAYER_BULLET, PLAYER_MELEE, EXPLOSION, ENEMY_BULLET, ENEMY_CONTACT, BOSS }

# ---------- 工具 ----------
## 把任意数值夹到区间内（Godot 的 clampf 只支持 float，这里给 int 用）
static func clampi(value: int, min_value: int, max_value: int) -> int:
	return int(clamp(float(value), float(min_value), float(max_value)))


## 判断某位掩码是否包含指定层
static func has_layer(mask: int, layer: int) -> bool:
	return (mask & layer) != 0


## 按权重表随机抽取一个 key，weights: {key: weight}
static func weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var total: float = 0.0
	for k: Variant in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		return null
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for k: Variant in weights.keys():
		acc += float(weights[k])
		if roll <= acc:
			return k
	return weights.keys().back()
