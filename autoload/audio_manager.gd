extends Node
## AudioMgr —— 音频管理（Autoload）。
##
## 全部音效/音乐为程序合成的原创 WAV（见 tools/gen_audio.py）。
## 采用对象池播放 SFX，避免频繁创建节点；BGM 双播放器交叉淡入淡出。
## 素材缺失时静默跳过，保证工程在任何阶段都能启动。

const SFX_DIR: String = "res://assets/audio/sfx/"
const BGM_DIR: String = "res://assets/audio/bgm/"

## SFX 注册表：逻辑名 -> 文件名（不含扩展名）。
## 与 assets/audio/sfx/ 下的真实文件严格一一对应（见 tools/gen_audio.py 的 SFX_NAMES），
## test_assets 套件会校验「注册表里的每一项都存在对应 wav」，避免播放时静默丢音。
const SFX: Dictionary = {
	# 武器
	"shoot_pistol": "shoot_pistol",
	"shoot_smg": "shoot_smg",
	"shoot_shotgun": "shoot_shotgun",
	"shoot_rifle": "shoot_rifle",
	"shoot_laser": "shoot_laser",
	"shoot_rocket": "shoot_rocket",
	"shoot_wand": "shoot_wand",
	"swing_blade": "swing_blade",
	"reload": "reload",
	"empty": "empty",
	# 命中 / 战斗反馈
	"hit_flesh": "hit_flesh",
	"hit_crit": "hit_crit",
	"hit_wall": "hit_wall",
	"explode_small": "explode_small",
	"explode_big": "explode_big",
	"break_crate": "break_crate",
	# 玩家
	"player_hurt": "player_hurt",
	"player_die": "player_die",
	"shield_break": "shield_break",
	"shield_regen": "shield_regen",
	"low_health": "low_health",
	"dash": "dash",
	"land": "land",
	"step": "step",
	"skill": "skill",
	"teleport_out": "teleport_out",
	# 敌人 / Boss
	"enemy_hurt": "enemy_hurt",
	"enemy_die": "enemy_die",
	"boss_roar": "boss_roar",
	"boss_charge": "boss_charge",
	"boss_slam": "boss_slam",
	"boss_summon": "boss_summon",
	"boss_die": "boss_die",
	# 掉落 / 交互
	"pickup_coin": "pickup_coin",
	"pickup_energy": "pickup_energy",
	"pickup_heart": "pickup_heart",
	"pickup_weapon": "pickup_weapon",
	"pickup_talent": "pickup_talent",
	"chest_open": "chest_open",
	"door_open": "door_open",
	"door_locked": "door_locked",
	"portal": "portal",
	"buy": "buy",
	"altar": "altar",
	# 流程 / UI
	"level_start": "level_start",
	"level_clear": "level_clear",
	"game_over": "game_over",
	"ui_click": "ui_click",
	"ui_hover": "ui_hover",
	"ui_back": "ui_back",
	"ui_pause": "ui_pause",
}

## BGM 注册表（对应 assets/audio/bgm/）
const BGM: Dictionary = {
	"menu": "menu",
	"dungeon_1": "dungeon_1",
	"dungeon_2": "dungeon_2",
	"dungeon_3": "dungeon_3",
	"shop": "shop",
	"boss": "boss",
	"victory": "victory",
	"gameover": "gameover",
}

const SFX_POOL_SIZE: int = 14
const BGM_FADE_SECONDS: float = 1.2

var _sfx_pool: Array[AudioStreamPlayer] = []
var _pool_cursor: int = 0
var _bgm_a: AudioStreamPlayer
var _bgm_b: AudioStreamPlayer
var _bgm_active: AudioStreamPlayer
var _current_bgm: String = ""
var _cache: Dictionary = {}
var _missing_warned: Dictionary = {}
## headless 运行（无音频设备：自动化测试 / CI / 专用服）时为 true。
## 此时只维护播放状态、不真正出声，避免退出时 AudioServer 仍持有 playback
## 而报 "N resources still in use at exit"。
var _silent: bool = false


func _ready() -> void:
	_silent = DisplayServer.get_name() == "headless"
	for i: int in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.autoplay = false
		add_child(p)
		_sfx_pool.append(p)

	_bgm_a = AudioStreamPlayer.new()
	_bgm_b = AudioStreamPlayer.new()
	add_child(_bgm_a)
	add_child(_bgm_b)
	_bgm_active = _bgm_a

	_apply_volumes()
	if not GameState.settings_changed.is_connected(_apply_volumes):
		GameState.settings_changed.connect(_apply_volumes)


# ==================== SFX ====================

## 播放音效。name 为 SFX 注册表里的逻辑名。
func play_sfx(sfx_name: String, pitch_variation: float = 0.0, volume_scale_db: float = 0.0) -> void:
	var stream: AudioStream = _get_stream(SFX_DIR, SFX, sfx_name)
	if stream == null:
		return
	if _silent or _sfx_pool.is_empty():
		return
	var player: AudioStreamPlayer = _sfx_pool[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % _sfx_pool.size()
	player.stream = stream
	player.volume_db = _db("sfx_volume") + volume_scale_db
	player.pitch_scale = 1.0 + (randf_range(-pitch_variation, pitch_variation) if pitch_variation > 0.0 else 0.0)
	player.play()


# ==================== BGM ====================

## 播放背景音乐，同名则不重启
func play_bgm(bgm_name: String) -> void:
	if bgm_name == _current_bgm:
		return
	var stream: AudioStream = _get_stream(BGM_DIR, BGM, bgm_name)
	if stream == null:
		_current_bgm = bgm_name
		return
	_current_bgm = bgm_name
	if _silent:
		return
	var next: AudioStreamPlayer = _bgm_b if _bgm_active == _bgm_a else _bgm_a
	next.stream = stream
	next.volume_db = -60.0
	next.play()

	var target_db: float = _db("bgm_volume")
	var fade_out := create_tween()
	fade_out.set_parallel(true)
	fade_out.tween_property(next, "volume_db", target_db, BGM_FADE_SECONDS)
	if _bgm_active.playing:
		fade_out.tween_property(_bgm_active, "volume_db", -60.0, BGM_FADE_SECONDS)
	var old: AudioStreamPlayer = _bgm_active
	_bgm_active = next
	fade_out.chain().tween_callback(func() -> void:
		if old.playing:
			old.stop())


func stop_bgm(fade: float = 0.6) -> void:
	_current_bgm = ""
	if _bgm_active == null or not _bgm_active.playing:
		return
	var t := create_tween()
	t.tween_property(_bgm_active, "volume_db", -60.0, fade)
	t.tween_callback(func() -> void: _bgm_active.stop())


## 立即硬停全部播放器并卸载音频流（无淡出）。
## 用于退出游戏、自动化测试收尾：若退出时 AudioServer 仍持有 playback，
## 进程结束会报 "N resources still in use at exit"。
func stop_all() -> void:
	_current_bgm = ""
	for p: AudioStreamPlayer in _sfx_pool:
		p.stop()
		p.stream = null
	for p: AudioStreamPlayer in [_bgm_a, _bgm_b]:
		if p == null:
			continue
		p.stop()
		p.stream = null
	_bgm_active = _bgm_a


## 退出游戏前调用：停止播放并释放缓存的音频流。
## 不清缓存的话 Godot 关闭时会报 AudioStreamWAV "resources still in use at exit"。
func shutdown() -> void:
	stop_all()
	_cache.clear()
	_missing_warned.clear()


# ==================== 内部 ====================

func _apply_volumes() -> void:
	if _bgm_active != null and _bgm_active.playing:
		_bgm_active.volume_db = _db("bgm_volume")


func _db(setting_key: String) -> float:
	var linear: float = clampf(float(GameState.settings.get(setting_key, 1.0)), 0.0, 1.0)
	var master: float = clampf(float(GameState.settings.get("master_volume", 1.0)), 0.0, 1.0)
	linear *= master
	if linear <= 0.001:
		return -60.0
	return linear_to_db(linear)


func _get_stream(dir: String, registry: Dictionary, key: String) -> AudioStream:
	if not registry.has(key):
		_warn_once("unknown:" + key, "AudioMgr: 未注册的音频 '%s'" % key)
		return null
	var path: String = dir + str(registry[key]) + ".wav"
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_warn_once(path, "AudioMgr: 素材缺失 %s（后续里程碑会生成）" % path)
		return null
	var stream: AudioStream = load(path)
	_cache[path] = stream
	return stream


func _warn_once(id: String, message: String) -> void:
	if _missing_warned.has(id):
		return
	_missing_warned[id] = true
	push_warning(message)
