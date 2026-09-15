# HANDOFF —— 2D 俯视角地牢射击游戏 交接文档

> 本文档用于把当前工程交接给下一个执行 Agent。工程位于 `D:\game1`（非 git 仓库），Godot 位于 `D:\godot\Godot_v4.7.2-stable_win64.exe`。
> 所有素材均为 `tools/` 下的 Python 脚本程序化生成的原创资源，**禁止**引入任何网络素材。

---

## 1. 当前状态总览

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M1 | 工程骨架 / Autoload / 输入映射 | 已完成 |
| M2 | 原创美术与音频素材管线 | 已完成 |
| M3 | 玩家 + 三武器 + 战斗核心 | 已完成 |
| M4 | 三类敌人 AI（近战冲锋 / 远程 / 自爆） | 已完成 |
| M5 | 随机地牢（5–10 房 + Boss 房 + 3 层 + 钥匙门 + 传送门） | 已完成 |
| M6 | 掉落 / 炸弹 / 临时天赋 / 祭坛 / 商店扩品 | 已完成 |
| **M7** | **Boss 战（2 种 Boss，弹幕 / 冲撞 / 召唤，两阶段）** | **进行中：仅完成勘察与设计，未写任何代码** |
| M8 | UI、菜单与完整流程补齐 | 未开始（部分骨架已在 M1/M3/M5/M6 落地，需先核对完成度） |
| M9 | 整局联调、自动化测试、缺陷修复 | 未开始 |
| M10 | README + 打包交付 | 未开始（工程内**目前没有任何 .md 文件**） |

M6 收尾时的基线（接手后请先重跑一次确认）：无头测试 792/792 通过，真窗口自检 118/118 连续 4 次稳定，字体字符集 1310 字，孤儿节点 0。

---

## 2. 运行与测试命令

```bash
# 直接运行游戏（真窗口）
"D:/godot/Godot_v4.7.2-stable_win64.exe" --path "D:/game1"

# 无头全量自动化测试（主要验收手段）
"D:/godot/Godot_v4.7.2-stable_win64.exe" --headless --path "D:/game1" res://tests/test_main.tscn

# 真窗口自检（逐节 PASS/FAIL，含截图；比无头测试更接近实机）
"D:/godot/Godot_v4.7.2-stable_win64.exe" --path "D:/game1" res://tests/launch_check.tscn

# 重新导入资源（新增 class_name、改动 .ttf、新增 png/wav 后必须执行）
"D:/godot/Godot_v4.7.2-stable_win64.exe" --headless --path "D:/game1" --import

# 字体重建 + 缺字检查（工程内任何中文文本变化后必须执行）
python tools/gen_font.py
python tools/check_charset.py

# 素材重新生成（改美术/音频时）
python tools/build_assets.py
```

改 `.gd` 文件**不需要**重新 import；新增 `class_name`、改 `.ttf`、加新 png/wav **必须**先 `--import`。

---

## 3. 工程文件树与关键文件职责

```
D:\game1\
├── project.godot                  工程配置：主场景、Autoload、InputMap、渲染/窗口设置
├── .gitignore                     已忽略 .godot 导入缓存
├── assets\                        全部原创素材（程序化生成，勿手工替换）
│   ├── sprites\
│   │   ├── player\                玩家 4 方向 × 4 帧
│   │   ├── enemies\               husk / hexeye / bloom（含 _elite 与 bloom 蓄力帧 c1~c3）
│   │   └── bosses\                warden_0..3.png(56×58)、weaver_0..3.png(64×60) ← M7 待接线
│   ├── weapons\  pickups\  props\  tiles\  ui\   武器图标 / 拾取物 / 场景物件 / 地砖墙体门 / UI 元素
│   │                              ui 内已有 boss_bar_9.png(32×14)、bar_fill_boss.png、minimap_boss.png
│   ├── fx\                        hit/spark/dust/smoke/slash/ring/heal/shield_pop/level_ring/muzzle/explode
│   │                              + bullet_p_*、bullet_e_*(8×8)、bullet_boss.png(14×14)、telegraph.png(32×32)
│   ├── audio\sfx\                 含 boss_roar / boss_charge / boss_slam / boss_summon / boss_die
│   ├── audio\bgm\                 menu / dungeon_1..3 / shop / boss / victory / gameover（WAV 循环）
│   └── fonts\                     程序化点阵字体 .ttf（1310 字符集，由 tools/gen_font.py 生成）
├── autoload\
│   ├── game_state.gd              局内状态：run_active/floor_index/gold/weapons/talents/bombs/stats/kills，
│   │                              new_run / advance_floor（floor_index >= G.TOTAL_FLOORS 返回 false = 通关）/
│   │                              end_run(victory) / save_current_run / has_floor_key
│   ├── event_bus.gd               全局信号总线（见 §5.3 Boss 相关信号）
│   ├── audio_manager.gd           play_sfx(name, pitch_variation, volume_db) / play_bgm(name) / stop_bgm(fade)，
│   │                              SFX 与 BGM 注册表在此文件顶部
│   ├── input_config.gd            输入映射与按键提示
│   └── save_manager.gd            存档读写（"继续游戏"依赖）
├── scenes\main.tscn               唯一场景入口（主菜单 / 游戏世界 / HUD 均在此装配）
├── scripts\
│   ├── main.gd                    根控制器：菜单 ↔ 游戏世界切换
│   ├── core\
│   │   ├── game_const.gd          G：碰撞层、PickupKind、RoomKind、TOTAL_FLOORS=3、
│   │   │                          BOSS_ROOM_SIZE=Vector2i(33,21)、WAVE_* 波次常量、ENEMY_ACTIVATE_DELAY
│   │   ├── combat_util.gd         分组名（GROUP_ENEMIES 等）、伤害来源常量
│   │   ├── dungeon_layout.gd      确定性纯逻辑地牢生成（rooms/neighbors/start_index/boss_index/is_boss_door）
│   │   ├── enemy_data.gd          敌人数值资源：Archetype{MELEE,RANGED,BOMBER,BOSS}、Tier{NORMAL,ELITE}、
│   │   │                          全部字段 + SPRITE_DIR(const) + sprite_path()/frames()/roll_drops()/FIELDS
│   │   ├── enemy_db.gd            TABLE 数值表、ELITE_OVERRIDES、ARCHETYPE_SCRIPTS、
│   │   │                          wave_for_room()/wave_for_wave_type()、WAVE_TYPE_WEIGHTS
│   │   ├── weapon_data.gd / weapon_db.gd   武器数值与工厂（手枪/霰弹枪/激光枪）
│   │   ├── talent_db.gd           6 个临时天赋（speed/crit/damage/shield/life/energy）
│   │   └── fx.gd / fx_sprite.gd   Fx.play(layer, anim, pos, opts) / Fx.single(...) / Fx.texture(name)，
│   │                              FRAME_COUNTS 与 DEFAULT_FPS 定义在 fx.gd 顶部
│   ├── entities\
│   │   ├── player.gd              WASD 移动、鼠标瞄准、射击、冲刺（无敌帧）、技能、E 交互、受击/死亡
│   │   ├── enemy.gd               Enemy 基类（状态机 + 受击契约 + 击退 + 分离力 + 死亡动画 + 掉落钩子）
│   │   ├── enemy_husk.gd          近战冲锋模板（蓄力→冲刺→撞墙眩晕）← Boss 冲撞可复用
│   │   ├── enemy_hexeye.gd        远程射击模板（保持距离→预警→burst）← Boss 弹幕可复用
│   │   ├── enemy_bloom.gd         自爆模板（引信→范围伤害，被击杀也引爆）
│   │   ├── bullet.gd              通用弹丸：from_player 决定阵营，每帧射线扫描命中，
│   │   │                          custom_textures / pierce_left / homing / explode_radius / sprite_scale
│   │   ├── laser_beam.gd          激光枪 hitscan 表现
│   │   ├── thrown_bomb.gd         炸弹（F 键）：引信 1.0s、伤害 58、半径 78、击退 340、自伤衰减到 50%
│   │   ├── damage_number.gd       伤害数字 / 世界飘字（setup_text(text, color, big)）
│   │   └── training_dummy.gd      M3 战斗试验场沙包
│   ├── game\
│   │   ├── game_world.gd          世界主控：双模式（arena 试验场 / dungeon 地牢）、房间装配、门/传送门、
│   │   │                          清怪开门、钥匙开锁、换层、通关判定（详见 §5.2 接线点）
│   │   ├── enemy_spawner.gd       波次调度：setup/start_wave/spawn_enemy/pick_spawn_position/alive_count/
│   │   │                          alive_enemies/enemies_of_archetype/kill_all/despawn_all + wave_cleared 信号
│   │   ├── room_builder.gd / room_floor.gd   房间墙体、地砖、装饰、障碍
│   │   ├── door.gd                门（boss_door 需钥匙，configure(...) 决定初始开合）
│   │   ├── portal.gd              传送门（Boss 房清空后生成，进入即换层）
│   │   ├── floor_key.gd           精英房掉落的地牢钥匙（拾取后 has_floor_key=true）
│   │   ├── chest.gd / shop_pad.gd / altar.gd   宝箱 / 商店垫（6 件商品）/ 祈愿祭坛（30 金随机天赋）
│   │   ├── pickup.gd              7 类掉落物：collect()/can_collect()/magnet_radius=74/_arm_timer
│   │   └── camera_rig.gd          相机跟随与震屏
│   └── ui\
│       ├── main_menu.gd           主菜单（开始 / 继续 / 设置 / 退出）
│       ├── hud.gd                 生命/护盾/能量/金币/小地图/武器/天赋栏/炸弹数/Boss 血条/toast/暂停面板
│       ├── result_screen.gd       胜利/失败结算
│       └── boot_screen.gd         启动检查画面
├── tests\
│   ├── test_main.gd / test_main.tscn   无头测试入口；SUITE_PATHS（第 11 行）+ 运行时 load()；看门狗 720s
│   ├── test_suite.gd              TestSuite 基类：suite_name() + run(t)；断言 check/eq/neq/near/gt/gte/lte/not_null
│   ├── suites\                    test_boot / test_assets / test_player / test_enemy /
│   │                              test_dungeon / test_dungeon_flow / test_pickup（共 7 个套件）
│   └── launch_check.gd/.tscn      真窗口自检（分节，M6 段在第 11 节）
└── tools\
    ├── pixel.py                   像素绘制基础库（所有素材脚本共用）
    ├── build_assets.py            素材总入口（串起下列生成器）
    ├── gen_characters.py / gen_fx.py / gen_ui.py / gen_world.py / gen_audio.py
    ├── gen_font.py                生成点阵 .ttf（扫工程内中文 → 字符集）
    ├── check_charset.py           缺字检查（**会扫描 .gd 注释里的汉字**）
    ├── patch_import_settings.py   批量修正 png/wav 的 .import 设置
    └── _preview.py                素材预览（临时工具）
```

---

## 4. 剩余任务清单（按执行顺序）

### 任务 A：M7 Boss 战（当前 in_progress，**代码尚未动笔**）

**范围**：至少 2 种 Boss，覆盖三类技能——弹幕（扇形 / 环形 / 螺旋）、冲撞（预警线 + 高速位移 + 撞墙眩晕）、召唤小怪；含阶段切换（血量阈值触发技能强化）、Boss 血条 UI、房间封闭与开战触发、击败后掉落与通关判定。

**完成条件**：无头测试验证 Boss 技能释放与阶段切换；实际运行 Boss 战完整可打并可通关（第 3 层 Boss 死亡 → 传送门 → `GameState.advance_floor()` 返回 false → `end_run(true)`）。

**推荐实现顺序（8 步）**：

1. `scripts/core/enemy_data.gd`
   - 新增 `@export var sprite_dir: String = ""`（空字符串回退到 `SPRITE_DIR`），并改 `sprite_path()` 与 `charge_frames()` 使用它——**Boss 素材在 `assets/sprites/bosses/`，而现有 `SPRITE_DIR` 硬编码指向 `assets/sprites/enemies/`，不处理会加载不到贴图**。
   - 追加 Boss 专用行为字段（建议）：`phase_threshold: float = 0.5`、`radial_count: int = 16`、`radial_speed: float = 190.0`、`radial_damage: float = 12.0`、`spiral_arms: int = 3`、`spiral_step_deg: float = 14.0`、`fan_count/fan_spread_deg`、`summon_ids: Array = []`、`summon_count: int = 4`、`summon_cooldown: float = 9.0`、`slam_radius/slam_damage`。
   - **务必把新字段名同步加进文件末尾的 `FIELDS: Array[String]`**（序列化/字典转资源用），漏加会导致 `enemy_db.TABLE` 里写的值被静默忽略。
2. `scripts/core/enemy_db.gd`
   - 加 `const BOSS_SCRIPT: GDScript = preload("res://scripts/entities/enemy_boss.gd")`，并在 `ARCHETYPE_SCRIPTS` 里映射 `A.BOSS`。
   - `TABLE` 增两条：`"warden"`（晶核监守者，冲撞 + 环形弹幕 + 召唤，sprite_base `warden`，frame_count 4）与 `"weaver"`（织弹者，扇形/螺旋弹幕强化型，sprite_base `weaver`，frame_count 4）。血量建议 `900 + 层数×250` 量级，`knockback_resist` ≥ 0.9，`armor` 2~4，`gold_min/gold_max` 拉高（如 60~120），`drops` 里 weapon/talent 概率拉满。
   - **不要把 warden/weaver 加进 `WAVE_TYPE_WEIGHTS`**，否则普通房间会随机刷出 Boss。
3. 新建 `scripts/entities/enemy_boss.gd`（`class_name EnemyBoss extends Enemy`）
   - 必须暴露 HUD 需要的三个属性：`var display_name: String`、`var max_health_value: float`（`health` 已由基类提供）。
   - 生命周期信号：`_ready()` 或 activate 时 `EventBus.boss_spawned.emit(self)`；受伤时在覆写的 `take_hit()` 里 `EventBus.boss_health_changed.emit(health, max_health_value)`；死亡时 `EventBus.boss_died.emit(self)`；阶段切换 `EventBus.boss_phase_changed.emit(self, phase_index)`。
   - 覆写 `interrupt()` 或在受击逻辑中提高抗性，避免被小手枪的击退（基类 `INTERRUPT_KNOCKBACK = 150.0`）无限打断技能。
   - 技能状态机建议：`IDLE/CHASE` → 按冷却轮转 `CHARGE`(冲撞，复用 `enemy_husk.gd` 的 windup→charge→撞墙 `stun()` 反打窗口) / `RADIAL`(环形弹幕) / `FAN`(扇形) / `SPIRAL`(螺旋，多帧递增角度) / `SUMMON`(召唤) / `SLAM`(范围砸地)。
   - 阶段：`health / max_health_value <= data.phase_threshold` 时 `phase_index = 2`，提升射速/弹数/移速并解锁新技能组合，同时 `AudioMgr.play_sfx("boss_roar")` + `Fx.play(fx_layer, "level_ring", ...)` + `EventBus.boss_phase_changed`。
   - 弹幕发射统一用基类 `fire_bullet(direction, damage, speed, lifetime, radius, textures)`，Boss 弹传 `textures = [Fx.texture("bullet_boss")]`（14×14）；发射前用 `Fx.texture("telegraph")` 或 `Fx.play(..., "ring", ...)` 做预警。
   - 召唤小怪：需要世界引用。推荐在 `enemy.gd` 加 `var world_node: Node2D`，并在 `enemy_spawner.gd` 的 `spawn_enemy()`（第 134 行起，注入点在第 148–149 行 `enemy.bullet_layer = _bullet_layer` / `enemy.fx_layer = _fx_layer`）旁边补一行 `enemy.world_node = world`，Boss 内即可调 `world_node.spawn_enemy("hexeye", pos)` / `world_node.spawn_enemy("husk", pos)`。召唤上限建议 6~8 只，超过则跳过。
4. `scripts/game/game_world.gd`
   - `_boss_wave_ids()`（第 897 行，当前 `return []`）改为按层返回 Boss：如第 1 层 `["warden"]`、第 2 层 `["weaver"]`、第 3 层 `["warden"]`（或按设计做双 Boss）。返回非空后 `_activate_current_room()`（第 868 行）会自动 `_set_doors_open(false)` + `spawner.start_wave(boss_ids)`，房间封闭与开战触发现成可用。
   - **Boss 与小怪不同屏**：`_boss_wave_ids()` 只返回 Boss 本身，小怪全部由 Boss 召唤产生。
   - 进入 Boss 房时 `AudioMgr.play_bgm("boss")`，房间清空后恢复 `AudioMgr.play_bgm("dungeon_%d" % GameState.floor_index)`。
   - `_mark_room_cleared()`（第 902 行）已在 `G.RoomKind.BOSS` 分支置 `boss_room_cleared = true` 并 `_spawn_portal(center, false)`；第 3 层进传送门 → `_advance_floor()`（约第 990 行）→ `GameState.advance_floor()` 返回 false → `finished = true` + `end_run(true)`，通关链路**已存在，不要另造**。
   - 不要新增"Boss 专属钥匙"：`G.PickupKind` 里没有该类型，M5 的钥匙是精英房 `floor_key.gd`。Boss 房清空直接开传送门即可。
5. `scripts/ui/hud.gd`
   - Boss 血条已实现：`_build_boss_bar()`（第 265 行）、`_on_boss_spawned()`（第 740 行，读取 boss 的 `display_name/health/max_health_value`）、`_on_boss_health_changed()`（第 753 行）、`_on_boss_died()`（第 760 行隐藏面板），信号连接在第 310–315 行。
   - **待新增**：阶段横幅（监听 `EventBus.boss_phase_changed`，用现成 `show_toast(text, seconds)` 或做一个居中大字动画）、"小怪已清空"提示（Boss 召唤物清零时 toast）。
6. 新建 `tests/suites/test_boss.gd`（`extends TestSuite`）
   - 断言：EnemyDB 能造出 warden/weaver 且贴图非空；Boss 登场 emit `boss_spawned` 且 `display_name/max_health_value` 有效；受击 emit `boss_health_changed`；血量降到阈值下 `phase_index` 变 2 且 emit `boss_phase_changed`；三类技能各自触发（可用计数器字段，如 `charges_done` / `radials_fired` / `summons_done`，参照 `enemy_husk.gd` 里 `charges_done`/`wall_stuns`/`charge_hits` 的测试观测写法）；召唤物真实出现在世界；Boss 死亡 → `boss_died` + 掉落非空 + 房间判清空 + 传送门生成。
   - **必须**把 `"res://tests/suites/test_boss.gd"` 加进 `tests/test_main.gd` 的 `SUITE_PATHS`（第 11 行数组）。
   - 建世界参照 `tests/suites/test_dungeon_flow.gd`：先 `await get_tree().physics_frame` → `GameState.new_run()` → `world.dungeon_mode = true` → `add_child(world)`；玩家血线用 `_tough_player` 沙包打法；清理用 `_free_world`（等两帧）。
7. `tests/launch_check.gd` 新增 M7 自检节（真窗口）：Boss 房进入→血条出现→阶段横幅→三类技能可见→死亡掉钥匙/传送门→无 ERROR 日志、无孤儿节点、截图。
8. 跑无头 + 真窗口双验收，并回归 `arena_mode` / `DEMO_WAVE` 试验场流程（不能被 Boss 改动影响）。

**已确认可复用的资产**：Boss 贴图（warden/weaver 各 4 帧）、`bullet_boss.png`、`telegraph.png`、5 个 Boss 音效、Boss BGM、HUD Boss 血条贴图、`EventBus` 五个 Boss 信号、Boss 房尺寸 `G.BOSS_ROOM_SIZE`、`EnemyData.Archetype.BOSS` 枚举、husk 冲撞与 hexeye 弹幕两套行为模板。

---

### 任务 B：M8 UI、菜单与完整游戏流程

**范围**：主菜单（开始 / 继续 / 设置 / 退出，含存档支持"继续"）、设置面板（音量、全屏/窗口、按键提示）、游戏内 HUD（生命/护盾/能量、金币、小地图、当前武器、天赋图标、层数）、Esc 暂停菜单（继续 / 设置 / 返回主菜单 / 重开）、胜利/失败结算与一键重开。

**注意**：`scripts/ui/main_menu.gd`、`hud.gd`、`result_screen.gd`、`boot_screen.gd`、`autoload/save_manager.gd` **已有骨架且大部分功能在 M1/M3/M5/M6 落地**。接手后第一步应是实机逐项核对完成度，只补缺口，不要重写。

**完成条件**：实际运行验证菜单跳转、暂停/恢复正常、重开后状态完全重置（金币/武器/天赋/炸弹/层数/击杀数）、结算界面可回主菜单。

---

### 任务 C：M9 整局联调、自动化测试与缺陷修复

**范围**：无头测试覆盖属性/武器/敌人/地牢生成/掉落/Boss/流程状态机；手动跑通完整一局（开始 → 探索 → 战斗 → Boss → 胜利/失败 → 重开）；修复所有报错、脚本解析错误、碰撞穿透、卡顿、节点泄漏；校准手感（移速、射速、击退、难度曲线）。

**完成条件**：全部测试通过、控制台无 ERROR / SCRIPT ERROR、完整一局可复现跑通、无孤儿节点。

---

### 任务 D：M10 README 与打包交付

**范围**：撰写 `D:\game1\README.md`，必须包含五部分——安装、运行、操作说明、目录结构、扩展方式（含"新增武器 / 新增敌人 / 新增房间"的代码入口示例）；清理临时文件与调试代码（如 `tools/_preview.py` 视情况保留）；把 `D:\game1` 打包成**单个 zip（排除 `.godot` 目录）** 并通过 `file_export` 交付。

**完成条件**：README 五部分齐备、命令可直接复制执行、zip 解压后可直接运行。

---

## 5. 关键接口速查（Boss 实现直接依赖）

### 5.1 `Enemy` 基类（`scripts/entities/enemy.gd`）

```gdscript
enum State { DORMANT, IDLE, CHASE, ATTACK, STUNNED, DEAD }

# 注入 / 生命周期
func configure(enemy_data: EnemyData) -> void
func activate() -> void
func set_target(node: Node2D) -> void
func _think(_delta: float) -> void          # 子类覆写的主入口
func _post_move(_delta: float) -> void      # 子类可覆写的位移后钩子

# 受击契约（打敌人自身用这个）
func take_hit(amount: float, is_crit: bool, knockback: Vector2, source: int) -> void
func interrupt() -> void                    # knockback >= INTERRUPT_KNOCKBACK(150) 时打断动作
func die() -> void
func stun(duration: float) -> void
func heal(amount: float) -> void
func is_dead_or_disabled() -> bool

# 对玩家造成伤害（语义是"敌人打它的目标"，误用会反杀玩家）
func damage_target(amount: float, knockback: Vector2, is_crit: bool = false) -> bool

# 发射敌方弹丸（Boss 弹幕用这个）
func fire_bullet(direction: Vector2, damage: float, speed: float, lifetime: float = 2.4,
        radius: float = 4.0, textures: Array[Texture2D] = []) -> Bullet

# 辅助
func set_state(new_state: State) -> void
func state_name() -> String
func _fx_host() -> Node2D                   # 特效挂载层（优先 fx_layer）
func _bullet_host() -> Node2D
func _refresh_target() -> void

# 常用字段
var data / max_health / health / state / activated / dead / facing / target
var bullet_layer / fx_layer / auto_free / _sprite
var move_velocity / external_velocity / last_collided_wall / separation_force
var activate_timer / attack_cooldown / contact_cooldown_timer / stun_timer / death_timer / state_time
var _rng                                     # 基类自带的随机数发生器
```

### 5.2 `game_world.gd` Boss 接线点

| 行号（约） | 内容 |
|---|---|
| 86 | `var boss_room_cleared: bool` |
| 540 / 547 | `spawn_wave(ids)` / `spawn_enemy(enemy_id, at_position)` |
| 554 | `clear_entities(keep_player)` |
| 850 | 房间物件装配：`G.RoomKind.BOSS` 且 cleared → `_spawn_portal(center, false)` |
| 868 | `_activate_current_room()`：Boss 房 → `_boss_wave_ids()` 非空则关门 + `start_wave` |
| **897** | **`_boss_wave_ids()` → 当前 `return []`，这是 Boss 投放的唯一入口** |
| 902 | `_mark_room_cleared(quiet)`：置 cleared、开门、按房型给奖励 |
| 990 | `_advance_floor()`：最后一层通关判定 |
| 1064/1095 | 钥匙开门：`_unlock_boss_door(door)` |

### 5.3 `EventBus` Boss 相关信号（`autoload/event_bus.gd` 第 34–37 行）

```gdscript
signal boss_spawned(boss: Node)
signal boss_phase_changed(boss: Node, phase_index: int)
signal boss_health_changed(current: float, max_value: float)
signal boss_died(boss: Node)
```

### 5.4 `EnemySpawner`（`scripts/game/enemy_spawner.gd`）

```gdscript
func setup(p_world, p_interior: Rect2, p_floor_index := 1, p_room_kind := G.RoomKind.COMBAT, p_seed := 0)
func start_wave(ids: Array = []) -> Array      # ids 为空则按房型/层数自动规划
func spawn_enemy(enemy_id: String, at_position: Variant = null) -> Enemy
func pick_spawn_position(radius: float = 8.0) -> Vector2
func alive_count() -> int / alive_enemies() -> Array / enemies_of_archetype(archetype: int) -> Array
func kill_all() -> int / despawn_all() -> void / prune_freed() -> void
signal wave_started(ids) / batch_spawned(batch_index, ids) / wave_cleared
var activate_on_spawn: bool / auto_free: bool   # 测试里常设 auto_free = false
```

---

## 6. 硬约束与踩坑记录（**违反任一条都会导致返工**）

1. **类缓存 / 资源导入**：新增 `class_name`、改 `.ttf`、新增 png/wav 后必须先跑 `--headless --path "D:/game1" --import`，否则报 "class not found" 或贴图加载失败。
2. **字体**：工程内任何中文变化（**包括 `.gd` 注释里的汉字**，`check_charset.py` 会扫描注释）都必须重跑 `python tools/gen_font.py` + `python tools/check_charset.py`。注释里写生僻字同样要重建。当前字符集 1310 字。
3. **测试套件注册**：新套件只能走 `tests/test_main.gd` 的 `SUITE_PATHS` 数组 + 运行时 `load()`；**用 `preload` 会挂死 test_main**。
4. **物理时效**：
   - `PhysicsServer2D.is_flushing_queries()` **不可用**；
   - 物理回调链中修改 `Area2D.monitoring` 必须 `set_deferred`；
   - 换房 / 换层 / 开门必须 `call_deferred`；
   - `intersect_shape` 必须放在 `physics_frame` 续体之后；
   - 测试里的续体恢复点用 `physics_frame` 或 `call_deferred`，否则会报 `Can't change this state while flushing queries`。
5. **`damage_target` 语义**：`Enemy.damage_target(amount, knockback, is_crit)` 是"敌人对它的目标（玩家）造成伤害"；要打敌人自身必须用 `Enemy.take_hit(amount, is_crit, knockback, source)`。误用会反杀玩家，并连锁触发世界 `end_run`。
6. **玩家死亡链会破坏世界状态**：`game_world.gd` 的门 / 传送门入口都有 `if finished: return`；玩家死亡走完 `_death_timer` 会置 `finished = true` 并 `end_run(false)`，挡掉后续所有断言。真窗口自检里保命靠 `_dungeon_top_up()`：取消 `_death_timer`、复位 `finished` / `GameState.run_active`、还原 `die()` 改掉的 `collision_layer` 与贴图、最后 `player.set_invulnerable(120.0)`。
7. **`Pickup.collect()` 在 `target.dead` 时拒绝结算**；玩家血量会被自身 clamp 回 `max_health()`。
8. **多世界输入串扰**：自检里旧世界即使 `visible = false` 仍在跑 `_physics_process`，`Input.action_press` 会被两个玩家各响应一次（曾导致炸弹双扣）。新建检查世界前先 `_world.player.set_physics_process(false)` + `set_process(false)`。
9. **lambda 捕获已释放对象**会抛 `Lambda capture ... freed` 污染日志；改用轮询世界容器（如 `_find_bomb_node(dw) == null`、`_find_pickup_of_kind(dw, COIN) == null`）。
10. **击退残余会干扰定位类断言**：断言前先清 `player.velocity` / `_external_velocity`（否则会甩出 74px 磁吸半径）。
11. **M6 既有数值（改动前请知悉）**：`BOMB_DAMAGE=58`、`BOMB_RADIUS=78`、`BOMB_KNOCKBACK=340`、引信 1.0s、自伤按距离衰减到 50%、`MAX_BOMBS=9`、`START_BOMBS=2`、`ALTAR_TALENT_PRICE=30`、商店 6 件（heal/shield/energy/bomb/weapon/talent，仅 bomb 可重复购买）、`Pickup.magnet_radius=74`。
12. **用户级硬约束**：所有素材必须原创（程序化生成）；电脑端键鼠操作；每轮回复须含"本轮目标 / 修改文件 / 关键代码说明 / 运行方法 / 测试结果 / 已知问题 / 下一步"；遇报错先自行修复直到 MVP 可运行；最终交付单个 zip（排除 `.godot`）+ README 五部分。

---

## 7. 验收标准（整体）

- 项目可启动，无阻塞报错。
- 能完成一局：开始 → 探索 → 战斗 → Boss → 胜利/失败 → 重开。
- 操作流畅，碰撞正确，暂停/恢复/重开正常。
- README 覆盖：安装、运行、操作、目录结构、扩展方式。

## 8. 已知问题 / 风险

- Boss 素材目录与 `EnemyData.SPRITE_DIR` 不一致（见任务 A 第 1 步），是 M7 第一个必然踩到的坑。
- `enemy_data.gd` 目前没有 Boss 专用字段，`FIELDS` 序列化表需同步维护，否则数值静默失效。
- Boss 召唤小怪需要世界引用，`enemy_spawner.spawn_enemy()` 目前只注入 `bullet_layer` / `fx_layer` / 目标，不注入 world（见任务 A 第 3 步）。
- 普通房间波次权重表若误加 Boss id，会导致 Boss 随机出现在战斗房，务必检查 `WAVE_TYPE_WEIGHTS`。
- 工程目前没有任何 `.md` 文件，README 从零写。
- `arena_mode` / `DEMO_WAVE`（M3/M4 战斗试验场）在 Boss 改动后需回归验证一次。
