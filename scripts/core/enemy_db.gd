class_name EnemyDB
extends RefCounted
## EnemyDB —— 敌人数值表、工厂与波次规划（M4）。
##
## 三类基础敌人对应三种行为原型：
##   husk   近战冲锋（晶壳行者）—— 追踪 + 蓄力冲刺撞击，撞墙会眩晕；
##   hexeye 远程射击（六目浮灵）—— 保持距离横向游走，预警后射敌弹；
##   bloom  自爆（孢晶囊）    —— 贴身蓄力后炸开，被击杀也会引爆。
## 精英版（`<id>_elite`）不是单独一张表，而是基础条目叠加 ELITE_OVERRIDES，
## 这样调平衡时不会出现"精英数值忘了跟着改"的情况。
##
## 扩展方式：往 TABLE 加一条字典 + 在 ARCHETYPE_SCRIPTS 里确认原型有对应子类，
## 贴图放到 assets/sprites/enemies/<sprite_base>_<frame>.png（精英再加 _elite），
## 然后把 id 加进 WAVE_TYPE_WEIGHTS 就能被房间波次自动选中。

const G := preload("res://scripts/core/game_const.gd")
const A := EnemyData.Archetype
const T := EnemyData.Tier

const MELEE_SCRIPT: GDScript = preload("res://scripts/entities/enemy_husk.gd")
const RANGED_SCRIPT: GDScript = preload("res://scripts/entities/enemy_hexeye.gd")
const BOMBER_SCRIPT: GDScript = preload("res://scripts/entities/enemy_bloom.gd")
const BOSS_SCRIPT: GDScript = preload("res://scripts/entities/enemy_boss.gd")
const STALKER_SCRIPT: GDScript = preload("res://scripts/entities/enemy_stalker.gd")
const SPLITTER_SCRIPT: GDScript = preload("res://scripts/entities/enemy_splitter.gd")
const BURROWER_SCRIPT: GDScript = preload("res://scripts/entities/enemy_burrower.gd")
const SUMMONER_SCRIPT: GDScript = preload("res://scripts/entities/enemy_summoner.gd")

## 敌人数值表：id -> 参数（缺省字段由 EnemyData 默认值补齐）
const TABLE: Dictionary = {
	"husk": {
		"display_name": "晶壳行者", "archetype": A.MELEE, "tier": T.NORMAL,
		"max_health": 34.0, "armor": 0.0, "move_speed": 96.0, "body_radius": 7.0,
		"knockback_resist": 0.1, "sight_range": 330.0, "score": 10,
		"contact_damage": 7.0, "contact_cooldown": 0.7,
		"charge_trigger_range": 132.0, "charge_windup": 0.34, "charge_speed": 320.0,
		"charge_duration": 0.44, "charge_damage": 15.0, "charge_knockback": 250.0,
		"charge_cooldown": 1.9, "charge_stun_on_wall": 0.42,
		"gold_min": 2, "gold_max": 5,
		"drops": {"energy": 0.30, "health": 0.10, "shield_cell": 0.05, "bomb": 0.05, "weapon": 0.02, "talent": 0.02},
		"sprite_base": "husk", "frame_count": 3, "anim_fps": 10.0,
		"sfx_attack": "boss_charge",
		"description": "被晶壳寄生的矿道行者，锁定目标后低头猛冲。",
	},
	"hexeye": {
		"display_name": "六目浮灵", "archetype": A.RANGED, "tier": T.NORMAL,
		"max_health": 26.0, "armor": 0.0, "move_speed": 80.0, "body_radius": 7.0,
		"knockback_resist": 0.0, "sight_range": 380.0, "score": 12,
		"contact_damage": 5.0, "contact_cooldown": 0.8,
		"preferred_range": 152.0, "keep_distance_min": 96.0, "aim_time": 0.42,
		"fire_interval": 1.7, "burst_count": 1, "burst_interval": 0.15,
		"bullet_damage": 9.0, "bullet_speed": 265.0, "bullet_lifetime": 2.4,
		"bullet_radius": 4.0, "spread_deg": 3.0, "strafe_strength": 34.0,
		"gold_min": 3, "gold_max": 6,
		"drops": {"energy": 0.38, "health": 0.10, "shield_cell": 0.08, "weapon": 0.03, "talent": 0.03},
		"sprite_base": "hexeye", "frame_count": 4, "anim_fps": 8.0,
		"sfx_shoot": "shoot_wand",
		"description": "悬浮的晶眼集合体，保持距离吐射晶弹。",
	},
"bloom": {
		"display_name": "孢晶囊", "archetype": A.BOMBER, "tier": T.NORMAL,
		"max_health": 22.0, "armor": 0.0, "move_speed": 104.0, "body_radius": 8.0,
		"knockback_resist": 0.0, "sight_range": 300.0, "score": 14,
		"contact_damage": 4.0, "contact_cooldown": 0.9,
		"fuse_trigger_range": 48.0, "fuse_time": 0.78, "explosion_radius": 64.0,
		"explosion_damage": 32.0, "explosion_knockback": 300.0,
		"explode_on_death": true, "death_explosion_ratio": 0.7, "wobble": 26.0,
		"gold_min": 2, "gold_max": 7,
		"drops": {"energy": 0.40, "health": 0.12, "bomb": 0.10, "shield_cell": 0.05, "weapon": 0.02, "talent": 0.02},
		"sprite_base": "bloom", "frame_count": 4, "anim_fps": 11.0,
		"sfx_fuse": "boss_charge",
		"description": "鼓胀的孢子晶囊，靠近后急速膨胀炸开。",
	},
	"reaver_hound": {
		"display_name": "掠晶猎犬", "archetype": A.MELEE, "tier": T.NORMAL,
		"max_health": 28.0, "armor": 0.0, "move_speed": 128.0, "body_radius": 7.0,
		"knockback_resist": 0.15, "sight_range": 340.0, "score": 12,
		"contact_damage": 6.0, "contact_cooldown": 0.65,
		"charge_trigger_range": 150.0, "charge_windup": 0.22, "charge_speed": 385.0,
		"charge_duration": 0.36, "charge_damage": 13.0, "charge_knockback": 220.0,
		"charge_cooldown": 1.35, "charge_stun_on_wall": 0.3,
		"gold_min": 2, "gold_max": 5,
		"drops": {"energy": 0.32, "health": 0.10, "shield_cell": 0.05, "bomb": 0.05, "weapon": 0.02, "talent": 0.02},
		"sprite_base": "reaver_hound", "frame_count": 3, "anim_fps": 13.0,
		"sfx_attack": "boss_charge",
		"description": "被晶噬感染的猎犬，比矿道行者更快更凶，短距连扑咬碎猎物。",
	},
	"shadewalker": {
		"display_name": "影袭者", "archetype": A.STALKER, "tier": T.NORMAL,
		# 血量刻意压到全场最低档：它的伤害来自「你看不见」而不是「它很硬」，
		# 给它厚血等于让玩家在看不见目标的情况下慢慢磨，挫败感翻倍。
		"max_health": 18.0, "armor": 0.0, "move_speed": 118.0, "body_radius": 7.0,
		"knockback_resist": 0.0, "sight_range": 380.0, "score": 16,
		"contact_damage": 4.0, "contact_cooldown": 0.9,
		# 显形前摇 0.85s：足够玩家看到红光后转身跑掉
		"strike_trigger_range": 104.0, "reveal_time": 0.85,
		"strike_speed": 440.0, "strike_duration": 0.30,
		"strike_damage": 17.0, "strike_knockback": 280.0,
		"gold_min": 3, "gold_max": 7,
		"drops": {"energy": 0.34, "health": 0.10, "shield_cell": 0.06, "weapon": 0.03, "talent": 0.03},
		"sprite_base": "husk", "frame_count": 3, "anim_fps": 13.0,
		"sfx_attack": "boss_charge", "sfx_fuse": "level_start",
		"description": "半透明的潜行者。始终留有残影，贴近后显形突刺——但它很脆，见红光就撤。",
	},
	"crystal_grub": {
		"display_name": "裂晶虫", "archetype": A.SPLITTER, "tier": T.NORMAL,
		"max_health": 40.0, "armor": 0.0, "move_speed": 78.0, "body_radius": 10.0,
		"knockback_resist": 0.2, "sight_range": 300.0, "score": 15,
		"contact_damage": 6.0, "contact_cooldown": 0.8,
		"split_into": "grub_shard", "shard_contact_damage": 4.0,
		"gold_min": 3, "gold_max": 6,
		"drops": {"energy": 0.3, "health": 0.14, "shield_cell": 0.06, "bomb": 0.06, "weapon": 0.02, "talent": 0.02},
		"sprite_base": "bloom", "frame_count": 4, "anim_fps": 8.0,
		"sfx_die": "break_crate",
		"description": "缓慢滚动的晶囊。被击杀时会裂成两只高速碎片。",
	},
	"grub_shard": {
		"display_name": "晶囊碎片", "archetype": A.MELEE, "tier": T.NORMAL,
		"max_health": 14.0, "armor": 0.0, "move_speed": 128.0, "body_radius": 5.0,
		"knockback_resist": 0.0, "sight_range": 340.0, "score": 3,
		"contact_damage": 4.0, "contact_cooldown": 0.7,
		"gold_min": 0, "gold_max": 1,
		"drops": {"energy": 0.12},
		"sprite_base": "hexeye", "frame_count": 4, "anim_fps": 14.0,
		"description": "裂晶虫崩出的碎片。脆、快、不会再分裂。",
	},
	"burrower": {
		"display_name": "穿地兽", "archetype": A.BURROWER, "tier": T.NORMAL,
		"max_health": 44.0, "armor": 1.0, "move_speed": 104.0, "body_radius": 9.0,
		"knockback_resist": 0.25, "sight_range": 420.0, "score": 20,
		"contact_damage": 5.0, "contact_cooldown": 0.9,
		"erupt_trigger_range": 130.0, "erupt_damage": 21.0, "erupt_knockback": 330.0,
		"gold_min": 4, "gold_max": 8,
		"drops": {"energy": 0.32, "health": 0.12, "shield_cell": 0.08, "bomb": 0.06, "weapon": 0.03, "talent": 0.02},
		"sprite_base": "reaver_hound", "frame_count": 3, "anim_fps": 12.0,
		"sfx_fuse": "boss_charge", "sfx_attack": "boss_slam",
		"description": "潜行时可穿过墙体，贴近后在地面预警圈里破土砸下。",
	},
	"brood_mother": {
		"display_name": "晶巢母体", "archetype": A.SUMMONER, "tier": T.NORMAL,
		"max_health": 58.0, "armor": 1.0, "move_speed": 62.0, "body_radius": 11.0,
		"knockback_resist": 0.4, "sight_range": 400.0, "score": 24,
		"contact_damage": 5.0, "contact_cooldown": 1.0,
		"preferred_range": 210.0, "keep_distance_min": 120.0,
		"summon_ids": ["husk"], "summon_count": 2, "summon_cap": 4,
		"summon_cooldown": 6.5, "summon_windup": 0.6,
		"summon_ring": 52.0, "summon_life": 9.0, "summon_clear_delay": 4.0,
		"gold_min": 5, "gold_max": 9,
		"drops": {"energy": 0.4, "health": 0.16, "shield_cell": 0.08, "bomb": 0.1, "weapon": 0.04, "talent": 0.04},
		"sprite_base": "bloom", "frame_count": 4, "anim_fps": 7.0,
		"sfx_shoot": "boss_summon",
		"description": "自身脆弱但不断产出小怪。召唤物有寿命，清空后它也要歇一阵。",
	},
	"warden": {
		"display_name": "晶核监守者", "archetype": A.BOSS, "tier": T.NORMAL,
		"max_health": 862.0, "armor": 3.0, "move_speed": 82.0, "body_radius": 17.0,
		"knockback_resist": 0.9, "sight_range": 460.0, "score": 300,
		"contact_damage": 14.0, "contact_cooldown": 0.55,
		# ---------- 冲撞 ----------
		"charge_trigger_range": 230.0, "charge_windup": 0.5, "charge_speed": 330.0,
		"charge_duration": 0.5, "charge_damage": 24.0, "charge_knockback": 300.0,
		"charge_cooldown": 6.0, "charge_stun_on_wall": 0.55,
		# ---------- 环形弹幕 ----------
		"radial_count": 14, "radial_waves": 2, "radial_wave_interval": 0.28,
		"radial_damage": 11.0, "radial_speed": 190.0, "radial_cooldown": 5.0,
		"radial_telegraph": 0.55,
		# ---------- 召唤 ----------
		"summon_ids": ["husk"], "summon_count": 3, "summon_cap": 6,
		"summon_cooldown": 10.0, "summon_windup": 0.8,
		"summon_clear_delay": 6.5,
		# ---------- 砸地 ----------
		"slam_radius": 96.0, "slam_damage": 24.0, "slam_knockback": 280.0,
		"slam_windup": 0.5, "slam_cooldown": 5.5, "slam_trigger_range": 120.0,
		# ---------- 阶段 ----------
		"phase_threshold": 0.5, "skill_interval": 1.25, "strafe_speed": 46.0,
		"phase2_speed_mul": 1.12, "phase2_cooldown_mul": 0.78, "phase2_extra_bullets": 4,
		# ---------- 强化弹幕（阶段 2 解锁扇形） ----------
		"fan_count": 6, "fan_spread_deg": 44.0, "fan_bursts": 2, "fan_burst_interval": 0.16,
		"fan_damage": 10.0, "fan_speed": 235.0, "fan_cooldown": 4.2, "fan_aim_time": 0.45,
		"spiral_arms": 2, "spiral_step_deg": 16.0, "spiral_ticks": 12, "spiral_interval": 0.11,
		"spiral_damage": 8.0, "spiral_speed": 170.0, "spiral_cooldown": 7.0,
		"gold_min": 70, "gold_max": 120,
		"drops": {"energy": 0.9, "health": 0.5, "shield_cell": 0.4, "bomb": 0.25, "weapon": 0.4, "talent": 0.35},
		"sprite_base": "warden", "sprite_dir": "res://assets/sprites/bosses/",
		"frame_count": 4, "anim_fps": 7.0,
		"boss_sprite_scale": 1.0,
		"sfx_attack": "boss_charge", "sfx_shoot": "boss_roar", "sfx_die": "boss_die", "sfx_hurt": "enemy_hurt",
		"description": "镇守晶矿核心的巨型监守者：撼地冲锋、环形晶弹、呼唤矿道仆从。",
	},
	"weaver": {
		"display_name": "织弹者", "archetype": A.BOSS, "tier": T.NORMAL,
		"max_health": 788.0, "armor": 2.0, "move_speed": 96.0, "body_radius": 16.0,
		"knockback_resist": 0.9, "sight_range": 480.0, "score": 320,
		"contact_damage": 12.0, "contact_cooldown": 0.6,
		# ---------- 扇形弹幕 ----------
		"fan_count": 7, "fan_spread_deg": 48.0, "fan_bursts": 3, "fan_burst_interval": 0.17,
		"fan_damage": 9.0, "fan_speed": 245.0, "fan_cooldown": 3.9, "fan_aim_time": 0.42,
		# ---------- 螺旋弹幕 ----------
		"spiral_arms": 3, "spiral_step_deg": 18.0, "spiral_ticks": 16, "spiral_interval": 0.1,
		"spiral_damage": 8.0, "spiral_speed": 180.0, "spiral_cooldown": 6.4,
		# ---------- 环形弹幕 ----------
		"radial_count": 12, "radial_waves": 2, "radial_wave_interval": 0.3,
		"radial_damage": 10.0, "radial_speed": 185.0, "radial_cooldown": 5.4,
		"radial_telegraph": 0.5,
		# ---------- 召唤 ----------
		"summon_ids": ["hexeye"], "summon_count": 2, "summon_cap": 6,
		"summon_cooldown": 12.0, "summon_windup": 0.7,
		"summon_clear_delay": 8.0,
		# ---------- 砸地（贴脸防身） ----------
		"slam_radius": 88.0, "slam_damage": 20.0, "slam_knockback": 260.0,
		"slam_windup": 0.45, "slam_cooldown": 6.0, "slam_trigger_range": 105.0,
		# ---------- 阶段 ----------
		"phase_threshold": 0.5, "skill_interval": 1.1, "strafe_speed": 56.0,
		"phase2_speed_mul": 1.16, "phase2_cooldown_mul": 0.72, "phase2_extra_bullets": 5,
		"charge_trigger_range": 240.0, "charge_windup": 0.45, "charge_speed": 310.0,
		"charge_duration": 0.5, "charge_damage": 22.0, "charge_knockback": 290.0,
		"charge_cooldown": 7.0, "charge_stun_on_wall": 0.5,
		"gold_min": 60, "gold_max": 120,
		"drops": {"energy": 0.9, "health": 0.5, "shield_cell": 0.4, "bomb": 0.25, "weapon": 0.42, "talent": 0.38},
		"sprite_base": "weaver", "sprite_dir": "res://assets/sprites/bosses/",
		"frame_count": 4, "anim_fps": 8.0,
		"boss_sprite_scale": 1.0,
"sfx_attack": "boss_slam", "sfx_shoot": "boss_roar", "sfx_die": "boss_die", "sfx_hurt": "enemy_hurt",
		"description": "用晶丝编织弹幕的织者：扇形连喷与螺旋光弹编织成网，狂暴后更难闪避。",
	},
	"lasher": {
		"display_name": "晶镰领主", "archetype": A.BOSS, "tier": T.NORMAL,
		"max_health": 1080.0, "armor": 3.0, "move_speed": 96.0, "body_radius": 17.0,
		"knockback_resist": 0.9, "sight_range": 500.0, "score": 360,
		"contact_damage": 15.0, "contact_cooldown": 0.55,
		# ---------- 冲撞：连续两次的高速突进 ----------
		"charge_trigger_range": 250.0, "charge_windup": 0.4, "charge_speed": 385.0,
		"charge_duration": 0.5, "charge_damage": 26.0, "charge_knockback": 330.0,
		"charge_cooldown": 5.2, "charge_stun_on_wall": 0.5,
		# ---------- 扇形弹幕：宽扇 + 多波 ----------
		"fan_count": 9, "fan_spread_deg": 62.0, "fan_bursts": 3, "fan_burst_interval": 0.15,
		"fan_damage": 11.0, "fan_speed": 250.0, "fan_cooldown": 4.0, "fan_aim_time": 0.45,
		# ---------- 螺旋弹幕：多臂慢速弹雨 ----------
		"spiral_arms": 3, "spiral_step_deg": 13.0, "spiral_ticks": 18, "spiral_interval": 0.09,
		"spiral_damage": 8.0, "spiral_speed": 178.0, "spiral_cooldown": 5.6,
		# ---------- 环形弹幕 ----------
		"radial_count": 18, "radial_waves": 2, "radial_wave_interval": 0.24,
		"radial_damage": 12.0, "radial_speed": 210.0, "radial_cooldown": 4.4,
		"radial_telegraph": 0.48,
		# ---------- 召唤 + 砸地 ----------
		"summon_ids": ["burrower", "grub_shard"], "summon_count": 3, "summon_cap": 6,
		"summon_cooldown": 8.0, "summon_windup": 0.7, "summon_clear_delay": 5.0,
		"slam_radius": 110.0, "slam_damage": 26.0, "slam_knockback": 310.0,
		"slam_windup": 0.5, "slam_cooldown": 4.8, "slam_trigger_range": 135.0,
		# ---------- 阶段 ----------
		"phase_threshold": 0.5, "skill_interval": 1.1, "strafe_speed": 54.0,
		"phase2_speed_mul": 1.16, "phase2_cooldown_mul": 0.7, "phase2_extra_bullets": 5,
		"gold_min": 90, "gold_max": 150,
		"drops": {"energy": 0.95, "health": 0.6, "shield_cell": 0.45, "bomb": 0.3, "weapon": 0.5, "talent": 0.45},
		"sprite_base": "warden", "sprite_dir": "res://assets/sprites/bosses/",
		"frame_count": 4, "anim_fps": 8.0,
		"boss_sprite_scale": 1.0,
		"sfx_attack": "swing_blade", "sfx_shoot": "boss_roar", "sfx_die": "boss_die", "sfx_hurt": "enemy_hurt",
		"description": "把整座矿脉的速度塞进一把镰刀：更快的突进、更密的弹幕，还会从地里唤出穿地兽。",
	},
	"husk_king": {
		"display_name": "晶骸王座", "archetype": A.BOSS, "tier": T.NORMAL,
		"max_health": 1420.0, "armor": 5.0, "move_speed": 84.0, "body_radius": 19.0,
		"knockback_resist": 0.95, "sight_range": 520.0, "score": 500,
		"contact_damage": 18.0, "contact_cooldown": 0.5,
		"charge_trigger_range": 240.0, "charge_windup": 0.5, "charge_speed": 350.0,
		"charge_duration": 0.55, "charge_damage": 30.0, "charge_knockback": 350.0,
		"charge_cooldown": 5.6, "charge_stun_on_wall": 0.6,
		"radial_count": 20, "radial_waves": 3, "radial_wave_interval": 0.22,
		"radial_damage": 13.0, "radial_speed": 200.0, "radial_cooldown": 4.2,
		"radial_telegraph": 0.5,
		"fan_count": 10, "fan_spread_deg": 70.0, "fan_bursts": 4, "fan_burst_interval": 0.13,
		"fan_damage": 12.0, "fan_speed": 260.0, "fan_cooldown": 3.6, "fan_aim_time": 0.4,
		"spiral_arms": 4, "spiral_step_deg": 11.0, "spiral_ticks": 22, "spiral_interval": 0.08,
		"spiral_damage": 9.0, "spiral_speed": 185.0, "spiral_cooldown": 5.0,
		"summon_ids": ["husk_elite", "shadewalker"], "summon_count": 4, "summon_cap": 8,
		"summon_cooldown": 7.0, "summon_windup": 0.6, "summon_clear_delay": 4.5,
		"slam_radius": 128.0, "slam_damage": 32.0, "slam_knockback": 350.0,
		"slam_windup": 0.45, "slam_cooldown": 4.2, "slam_trigger_range": 150.0,
		"phase_threshold": 0.55, "skill_interval": 0.95, "strafe_speed": 50.0,
		"phase2_speed_mul": 1.2, "phase2_cooldown_mul": 0.66, "phase2_extra_bullets": 6,
		"gold_min": 120, "gold_max": 200,
		"drops": {"energy": 1.0, "health": 0.7, "shield_cell": 0.5, "bomb": 0.35, "weapon": 0.55, "talent": 0.5},
		"sprite_base": "reaper", "sprite_dir": "res://assets/sprites/bosses/",
		"frame_count": 4, "anim_fps": 7.0,
		"boss_sprite_scale": 1.15,
		"sfx_attack": "boss_slam", "sfx_shoot": "boss_roar", "sfx_die": "boss_die", "sfx_hurt": "enemy_hurt",
		"description": "矿脉的终点形态：三层弹幕循环 + 精英召唤，容错极低。",
	},
	"reaper": {
		"display_name": "晶脉收割者", "archetype": A.BOSS, "tier": T.NORMAL,
		"max_health": 1015.0, "armor": 4.0, "move_speed": 88.0, "body_radius": 18.0,
		"knockback_resist": 0.95, "sight_range": 500.0, "score": 380,
		"contact_damage": 16.0, "contact_cooldown": 0.5,
		# ---------- 冲撞（重镰突进） ----------
		"charge_trigger_range": 250.0, "charge_windup": 0.45, "charge_speed": 360.0,
		"charge_duration": 0.5, "charge_damage": 28.0, "charge_knockback": 320.0,
		"charge_cooldown": 5.8, "charge_stun_on_wall": 0.6,
		# ---------- 环形弹幕（晶镰挥出的死亡之环） ----------
		"radial_count": 16, "radial_waves": 2, "radial_wave_interval": 0.26,
		"radial_damage": 13.0, "radial_speed": 205.0, "radial_cooldown": 4.6,
		"radial_telegraph": 0.5,
		# ---------- 召唤（掠晶猎犬群） ----------
		"summon_ids": ["reaver_hound"], "summon_count": 4, "summon_cap": 8,
		"summon_cooldown": 9.0, "summon_windup": 0.75,
		"summon_clear_delay": 5.5,
		# ---------- 砸地（挥镰震地） ----------
		"slam_radius": 105.0, "slam_damage": 28.0, "slam_knockback": 300.0,
		"slam_windup": 0.5, "slam_cooldown": 5.0, "slam_trigger_range": 130.0,
		# ---------- 阶段 ----------
		"phase_threshold": 0.5, "skill_interval": 1.2, "strafe_speed": 48.0,
		"phase2_speed_mul": 1.14, "phase2_cooldown_mul": 0.74, "phase2_extra_bullets": 5,
		# ---------- 强化弹幕（阶段 2 解锁扇形） ----------
		"fan_count": 8, "fan_spread_deg": 50.0, "fan_bursts": 3, "fan_burst_interval": 0.15,
		"fan_damage": 12.0, "fan_speed": 255.0, "fan_cooldown": 3.8, "fan_aim_time": 0.4,
		"spiral_arms": 2, "spiral_step_deg": 14.0, "spiral_ticks": 10, "spiral_interval": 0.12,
		"spiral_damage": 9.0, "spiral_speed": 175.0, "spiral_cooldown": 6.5,
		"gold_min": 80, "gold_max": 140,
		"drops": {"energy": 0.95, "health": 0.55, "shield_cell": 0.45, "bomb": 0.3, "weapon": 0.45, "talent": 0.4},
		"sprite_base": "reaper", "sprite_dir": "res://assets/sprites/bosses/",
		"frame_count": 4, "anim_fps": 7.0,
		"boss_sprite_scale": 1.0,
		"sfx_attack": "boss_slam", "sfx_shoot": "boss_roar", "sfx_die": "boss_die", "sfx_hurt": "enemy_hurt",
		"description": "深渊最底层的收割者：镰刃挥出死亡之环、震地碎晶，并呼唤成群掠晶猎犬碾碎闯入者。",
	},
}

## 精英版在基础条目上的覆盖（先乘算血量/伤害，再改行为参数）
const ELITE_OVERRIDES: Dictionary = {
	"husk": {
		"max_health": 66.0, "move_speed": 104.0, "armor": 1.0, "knockback_resist": 0.35,
		"contact_damage": 10.0, "charge_damage": 22.0, "charge_windup": 0.3,
		"charge_cooldown": 1.5, "charge_speed": 350.0, "score": 26,
		"gold_min": 6, "gold_max": 12,
		"drops": {"energy": 0.5, "health": 0.28, "shield_cell": 0.16, "bomb": 0.12, "weapon": 0.10, "talent": 0.08},
	},
	"hexeye": {
		"max_health": 52.0, "move_speed": 86.0, "armor": 1.0, "knockback_resist": 0.25,
		"contact_damage": 7.0, "bullet_damage": 12.0, "burst_count": 3, "burst_interval": 0.14,
		"fire_interval": 1.5, "aim_time": 0.36, "spread_deg": 5.0, "preferred_range": 168.0,
		"score": 30, "gold_min": 7, "gold_max": 14,
		"drops": {"energy": 0.55, "health": 0.3, "shield_cell": 0.2, "weapon": 0.12, "talent": 0.1},
	},
"bloom": {
		"max_health": 44.0, "move_speed": 112.0, "armor": 0.0, "knockback_resist": 0.15,
		"explosion_radius": 78.0, "explosion_damage": 44.0, "fuse_time": 0.62,
		"fuse_trigger_range": 56.0, "score": 32, "gold_min": 6, "gold_max": 13,
		"drops": {"energy": 0.55, "health": 0.3, "bomb": 0.22, "shield_cell": 0.14, "weapon": 0.1, "talent": 0.08},
	},
	"reaver_hound": {
		"max_health": 56.0, "move_speed": 142.0, "armor": 1.0, "knockback_resist": 0.35,
		"contact_damage": 9.0, "charge_damage": 19.0, "charge_windup": 0.2,
		"charge_cooldown": 1.15, "charge_speed": 420.0, "score": 28,
		"gold_min": 6, "gold_max": 12,
		"drops": {"energy": 0.5, "health": 0.28, "shield_cell": 0.16, "bomb": 0.12, "weapon": 0.1, "talent": 0.08},
	},
}

const ELITE_SUFFIX: String = "_elite"
const ELITE_NAME_PREFIX: String = "精英·"


static func ids() -> Array:
	var out: Array = []
	for base_id: Variant in TABLE.keys():
		out.append(str(base_id))
		# Boss 原型没有精英版，只有基础敌人有 <id>_elite
		if int(TABLE[base_id].get("archetype", A.MELEE)) != A.BOSS:
			out.append(str(base_id) + ELITE_SUFFIX)
	return out


static func base_ids() -> Array:
	return TABLE.keys()


static func has_enemy(enemy_id: String) -> bool:
	return TABLE.has(base_id_of(enemy_id))


## 精英 id -> 基础 id（"husk_elite" -> "husk"）
static func base_id_of(enemy_id: String) -> String:
	if enemy_id.ends_with(ELITE_SUFFIX):
		return enemy_id.substr(0, enemy_id.length() - ELITE_SUFFIX.length())
	return enemy_id


static func is_elite_id(enemy_id: String) -> bool:
	return enemy_id.ends_with(ELITE_SUFFIX) and TABLE.has(base_id_of(enemy_id))


static func elite_id_of(enemy_id: String) -> String:
	return base_id_of(enemy_id) + ELITE_SUFFIX


## 原型 -> 子类脚本
static func script_for(data: EnemyData) -> GDScript:
	match data.archetype:
		A.MELEE:
			return MELEE_SCRIPT
		A.RANGED:
			return RANGED_SCRIPT
		A.BOMBER:
			return BOMBER_SCRIPT
		A.BOSS:
			return BOSS_SCRIPT
		A.STALKER:
			return STALKER_SCRIPT
		A.SPLITTER:
			return SPLITTER_SCRIPT
		A.BURROWER:
			return BURROWER_SCRIPT
		A.SUMMONER:
			return SUMMONER_SCRIPT
	return MELEE_SCRIPT


## 生成一份独立的敌人数值（含层数成长）。返回 null 表示 id 未知。
static func create_data(enemy_id: String, floor_index: int = 1) -> EnemyData:
	var base_id: String = base_id_of(enemy_id)
	if not TABLE.has(base_id):
		push_warning("EnemyDB: 未知敌人 id '%s'" % enemy_id)
		return null
	var data := EnemyData.new()
	data.id = enemy_id
	data.apply_dict(TABLE[base_id])
	if is_elite_id(enemy_id):
		data.tier = T.ELITE
		data.display_name = ELITE_NAME_PREFIX + str(data.display_name)
		data.apply_dict(ELITE_OVERRIDES.get(base_id, {}))
	return data.scale_for_floor(floor_index)


## 创建一个敌人节点（尚未加入场景树，调用方负责 add_child）
static func create(enemy_id: String, floor_index: int = 1) -> Enemy:
	var data: EnemyData = create_data(enemy_id, floor_index)
	if data == null:
		return null
	var script: GDScript = script_for(data)
	var enemy: Enemy = script.new()
	enemy.configure(data)
	return enemy


# ==================== 波次规划 ====================

## 该房型该层应出多少敌人（START / SHOP / BOSS 为 0，Boss 房由 M7 单独处理）
static func wave_count(rng: RandomNumberGenerator, floor_index: int, room_kind: int) -> int:
	var base: int = int(G.WAVE_BASE_COUNT.get(room_kind, 0))
	if base <= 0:
		return 0
	var level: int = clampi(floor_index, 1, 8)
	var count: int = base + G.WAVE_COUNT_PER_FLOOR * (level - 1)
	# 同一层内的房间数量略有起伏（±1），避免每间房都一样多
	count += rng.randi_range(-1, 1)
	return G.clampi(count, 1, G.WAVE_MAX_COUNT)


## 按层数权重摇一个敌人 id（含精英判定）
static func roll_enemy_id(rng: RandomNumberGenerator, floor_index: int) -> String:
	var level: int = clampi(floor_index, 1, G.TOTAL_FLOORS)
	var weights: Dictionary = G.WAVE_TYPE_WEIGHTS.get(level, G.WAVE_TYPE_WEIGHTS[G.TOTAL_FLOORS])
	var picked: Variant = G.weighted_pick(weights, rng)
	if picked == null:
		picked = "husk"
	var base_id: String = str(picked)
	if not TABLE.has(base_id):
		base_id = "husk"
	var elite_chance: float = float(G.WAVE_ELITE_CHANCE.get(level, 0.26))
	if rng.randf() < elite_chance:
		return base_id + ELITE_SUFFIX
	return base_id


## 一个房间的完整波次：返回敌人 id 数组（长度 = wave_count）
static func wave_for_room(rng: RandomNumberGenerator, floor_index: int, room_kind: int) -> Array:
	var out: Array = []
	var count: int = wave_count(rng, floor_index, room_kind)
	for i: int in range(count):
		out.append(roll_enemy_id(rng, floor_index))
	return out


## 把 id 数组切成若干批次（波次投放），返回 [[id, ...], [id, ...]]
static func split_batches(ids: Array, batches: int = G.WAVE_BATCHES) -> Array:
	var batch_count: int = clampi(batches, 1, 4)
	if ids.size() <= batch_count:
		return [ids.duplicate()]
	var out: Array = []
	for i: int in range(batch_count):
		out.append([])
	for index: int in range(ids.size()):
		(out[index % batch_count] as Array).append(ids[index])
	out = out.filter(func(batch: Array) -> bool: return not batch.is_empty())
	return out
