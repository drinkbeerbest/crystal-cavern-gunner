extends TestSuite
## 素材完整性测试套件。
##
## 校验 assets/ 下全部原创素材（美术 / 音频 / 字体）：
##   1. 目录与数量：每个素材目录的文件数量与生成器产出一致（防漏生成 / 误删）
##   2. 图片：可加载为 Texture2D、带 Alpha 通道、尺寸与生成器约定一致
##   3. 音频：可加载为 AudioStreamWAV、16bit 单声道 22050Hz、循环轨设置了 forward loop
##   4. 字体：可加载为 FontFile，且覆盖 UI 需要的全部中文字符与 ASCII
##   5. 关键命名：动画帧序列（传送门 / 火把 / 爆炸 / 天赋）与武器 ID 必须成套存在


func suite_name() -> String:
	return "assets"


# ---------------------------------------------------------------- 期望清单

## 带 Alpha 通道的 Image 格式（Godot 4.7 已移除 Image.has_alpha()，改用格式判定）
const ALPHA_FORMATS: Array[int] = [
	Image.FORMAT_LA8, Image.FORMAT_RGBA8, Image.FORMAT_RGBA4444, Image.FORMAT_RGBAF,
]

const EXPECT_COUNTS: Dictionary = {
	"sprites/player": 16,
	"sprites/enemies": 34,
	"sprites/bosses": 8,
	"tiles": 21,
	"props": 30,
	"fx": 62,
	"pickups": 41,
	"ui": 49,
	"ui/weapons": 12,
	"weapons": 12,
	"audio/sfx": 51,
	"audio/bgm": 8,
}

const PLAYER_DIRS: Array[String] = ["down", "up", "left", "right"]
const WEAPON_IDS: Array[String] = [
	"pistol", "smg", "shotgun", "rifle", "laser", "rocket", "wand", "blade",
	"gatling", "sniper", "crossbow", "grenade_launcher",
]
const BOSS_IDS: Array[String] = ["warden", "weaver"]
const TALENT_IDS: Array[String] = [
	"crit", "damage", "energy", "life", "shield", "speed",
]
# 帧序列：路径前缀 -> 帧数
const FRAME_SEQ: Dictionary = {
	"props/portal": 8,
	"props/altar": 4,
	"props/torch": 4,
	"props/brazier": 4,
	"fx/explode": 8,
	"fx/hit": 4,
	"fx/spark": 4,
	"fx/dust": 4,
	"fx/smoke": 4,
	"fx/slash": 4,
	"fx/ring": 4,
	"fx/heal": 4,
	"fx/shield_pop": 4,
	"fx/level_ring": 6,
	"fx/muzzle": 3,
	"pickups/coin": 4,
	"pickups/energy": 4,
	"pickups/bomb": 4,
}
const KEY_SFX: Array[String] = [
	"shoot_pistol", "shoot_smg", "shoot_shotgun", "shoot_rifle", "shoot_laser",
	"shoot_rocket", "shoot_wand", "swing_blade", "hit_flesh", "hit_crit",
	"player_hurt", "player_die", "shield_break", "dash", "skill",
	"pickup_coin", "pickup_heart", "pickup_weapon", "pickup_talent",
	"door_open", "chest_open", "portal", "ui_click", "ui_back",
	"boss_roar", "boss_charge", "boss_slam", "boss_summon", "boss_die",
	"level_clear", "game_over", "level_start",
]
const LOOP_BGM: Array[String] = ["menu", "dungeon_1", "dungeon_2", "dungeon_3", "boss", "shop"]
const ONESHOT_BGM: Array[String] = ["victory", "gameover"]
# UI 里实际会用到的中文字符（必须都在字体子集内）
const CJK_SAMPLE: String = "晶窟枪魂开始游戏继续设置退出暂停恢复重开主菜单音量全屏按键生命护盾能量金币层数房间商店宝箱祭坛传送门天赋暴击伤害速度拾取购买出售锁定已通关失败胜利得分当前武器技能冲刺交互确定取消返回提示难度普通困难噩梦加载中请稍候"

# 源码字符覆盖扫描：与 tools/gen_font.py 的 SCAN_EXT / SKIP_DIRS 对应
const SCAN_EXT: Array[String] = [".gd", ".tscn", ".tres", ".cfg", ".godot"]
const SKIP_DIRS: Array[String] = ["assets", "addons"]


# ---------------------------------------------------------------- 主体

func run(t: Node) -> void:
	var pngs: Array = []
	var wavs: Array = []
	_walk("res://assets", pngs, wavs)

	# --- 1. 总量
	t.eq(pngs.size(), 286, "PNG 总数 = 286（含根 icon.png）")
	t.eq(wavs.size(), 59, "WAV 总数 = 59（51 音效 + 8 BGM）")

	# --- 2. 每个目录的文件数量
	var per_dir: Dictionary = {}
	for p: String in pngs:
		var d: String = _dir_of(p)
		per_dir[d] = int(per_dir.get(d, 0)) + 1
	for d: String in EXPECT_COUNTS:
		if d.begins_with("audio"):
			continue
		t.eq(int(per_dir.get(d, 0)), EXPECT_COUNTS[d], "目录 %s 图片数量 = %d" % [d, EXPECT_COUNTS[d]])
	var sfx_n: int = 0
	var bgm_n: int = 0
	for p: String in wavs:
		if p.contains("/sfx/"):
			sfx_n += 1
		elif p.contains("/bgm/"):
			bgm_n += 1
	t.eq(sfx_n, EXPECT_COUNTS["audio/sfx"], "音效数量 = 51")
	t.eq(bgm_n, EXPECT_COUNTS["audio/bgm"], "BGM 数量 = 8")

	# --- 3. 图片：类型 / Alpha / 尺寸
	var no_alpha: Array[String] = []
	var zero_size: Array[String] = []
	var bad_type: Array[String] = []
	for p: String in pngs:
		var res: Resource = load(p)
		if res == null:
			bad_type.append(p)
			continue
		if not (res is Texture2D):
			bad_type.append(p)
			continue
		var tex: Texture2D = res
		if tex.get_width() <= 0 or tex.get_height() <= 0:
			zero_size.append(p)
		var img: Image = tex.get_image()
		if img == null or not ALPHA_FORMATS.has(img.get_format()):
			no_alpha.append(p)
	t.check(bad_type.is_empty(), "全部 PNG 可加载为 Texture2D（失败 %d）%s" % [bad_type.size(), _brief(bad_type)])
	t.check(zero_size.is_empty(), "全部 PNG 尺寸有效（失败 %d）%s" % [zero_size.size(), _brief(zero_size)])
	t.check(no_alpha.is_empty(), "全部 PNG 带 Alpha 通道（失败 %d）%s" % [no_alpha.size(), _brief(no_alpha)])

	# --- 4. 关键尺寸约定（与生成器一致，改动需同步生成器）
	_check_size(t, "res://assets/sprites/player/down_0.png", 22, 26, "玩家精灵 22x26")
	_check_size(t, "res://assets/sprites/bosses/warden_0.png", 56, 58, "Boss warden 56x58")
	_check_size(t, "res://assets/sprites/bosses/weaver_0.png", 64, 60, "Boss weaver 64x60")
	_check_size(t, "res://assets/tiles/floor_a_0.png", 32, 32, "地砖 32x32")
	_check_size(t, "res://assets/fx/explode_0.png", 48, 48, "爆炸帧 48x48")
	_check_size(t, "res://assets/icon.png", 128, 128, "工程图标 128x128")

	# --- 5. 成套命名
	var missing: Array[String] = []
	for dir_name: String in PLAYER_DIRS:
		for i: int in range(4):
			missing.append_array(_require("res://assets/sprites/player/%s_%d.png" % [dir_name, i]))
	for wid: String in WEAPON_IDS:
		missing.append_array(_require("res://assets/weapons/%s.png" % wid))
		missing.append_array(_require("res://assets/ui/weapons/%s.png" % wid))
	for bid: String in BOSS_IDS:
		for i: int in range(4):
			missing.append_array(_require("res://assets/sprites/bosses/%s_%d.png" % [bid, i]))
	for tid: String in TALENT_IDS:
		for i: int in range(4):
			missing.append_array(_require("res://assets/pickups/talent_%s_%d.png" % [tid, i]))
	for prefix: String in FRAME_SEQ:
		for i: int in range(FRAME_SEQ[prefix]):
			missing.append_array(_require("res://assets/%s_%d.png" % [prefix, i]))
	for base: String in ["bar_fill_hp", "bar_fill_shield", "bar_fill_energy", "bar_fill_boss",
			"bar_fill_dash", "bar_bg_9", "panel_9", "panel_dark_9", "slot_9", "boss_bar_9",
			"btn_9_normal", "btn_9_hover", "btn_9_pressed", "btn_9_disabled",
			"rarity_0", "rarity_1", "rarity_2", "rarity_3", "crosshair_0", "cursor",
			"icon_heart", "icon_coin", "icon_energy", "icon_shield", "icon_pause",
			"minimap_player", "minimap_boss", "minimap_current", "minimap_start",
			"minimap_treasure", "minimap_shop", "minimap_normal", "minimap_unknown"]:
		missing.append_array(_require("res://assets/ui/%s.png" % base))
	for tiles: String in ["floor_a_0", "floor_b_0", "wall_top_0", "wall_face_0", "wall_pillar",
			"carpet_0", "pit", "floor_crack", "floor_moss",
			"door_h_closed", "door_h_open", "door_v_closed", "door_v_open",
			"door_h_boss", "door_v_boss"]:
		missing.append_array(_require("res://assets/tiles/%s.png" % tiles))
	t.check(missing.is_empty(), "关键素材成套存在（缺失 %d）%s" % [missing.size(), _brief(missing)])

	# --- 6. 音频
	var bad_audio: Array[String] = []
	var bad_spec: Array[String] = []
	for p: String in wavs:
		var res: Resource = load(p)
		if res == null or not (res is AudioStreamWAV):
			bad_audio.append(p)
			continue
		var s: AudioStreamWAV = res
		if s.format != AudioStreamWAV.FORMAT_16_BITS:
			bad_spec.append(p + ":format=" + str(s.format))
		elif s.stereo:
			bad_spec.append(p + ":stereo")
		elif s.mix_rate != 22050 and s.mix_rate != 44100:
			bad_spec.append(p + ":rate=" + str(s.mix_rate))
		elif s.get_length() < 0.02:
			bad_spec.append(p + ":too_short")
	t.check(bad_audio.is_empty(), "全部 WAV 可加载为 AudioStreamWAV（失败 %d）%s" % [bad_audio.size(), _brief(bad_audio)])
	t.check(bad_spec.is_empty(), "全部 WAV 为 16bit / 单声道 / 22050 或 44100Hz / 时长>20ms（异常 %d）%s" % [bad_spec.size(), _brief(bad_spec)])

	for name: String in KEY_SFX:
		missing.append_array(_require("res://assets/audio/sfx/%s.wav" % name))
	t.check(missing.is_empty(), "关键音效齐备（缺失 %d）%s" % [missing.size(), _brief(missing)])

	var loop_bad: Array[String] = []
	for name: String in LOOP_BGM:
		var s: AudioStreamWAV = load("res://assets/audio/bgm/%s.wav" % name)
		if s == null or s.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			loop_bad.append(name)
	for name: String in ONESHOT_BGM:
		var s2: AudioStreamWAV = load("res://assets/audio/bgm/%s.wav" % name)
		if s2 == null or s2.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			loop_bad.append(name + "(应为不循环)")
	t.check(loop_bad.is_empty(), "BGM 循环设置正确：6 首循环 / 2 首结算不循环（异常 %s）" % str(loop_bad))
	var boss_bgm: AudioStreamWAV = load("res://assets/audio/bgm/boss.wav")
	t.gt(boss_bgm.get_length(), 10.0, "Boss BGM 时长 > 10 秒（实际 %.1f 秒）" % boss_bgm.get_length())

	# --- 7. 字体
	var font_res: Resource = load("res://assets/fonts/pixel_ui.ttf")
	t.not_null(font_res, "UI 字体 pixel_ui.ttf 可加载")
	t.check(font_res is FontFile, "UI 字体类型为 FontFile")
	var font: FontFile = font_res
	# Godot 4.7 的 FontFile 没有 get_char_index()，字形覆盖用基类 Font.has_char() 判定
	var miss_glyph: Array[String] = []
	for ch: String in CJK_SAMPLE:
		if not font.has_char(ch.unicode_at(0)):
			miss_glyph.append(ch)
	t.check(miss_glyph.is_empty(), "字体覆盖 UI 中文字符（缺字 %d）%s" % [miss_glyph.size(), _brief(miss_glyph)])
	var miss_ascii: Array[String] = []
	for code: int in range(32, 127):
		if not font.has_char(code):
			miss_ascii.append(char(code))
	t.check(miss_ascii.is_empty(), "字体覆盖 ASCII 32-126（缺字 %d）%s" % [miss_ascii.size(), _brief(miss_ascii)])

	# --- 7b. 游戏源码里出现的非 ASCII 字符必须都能渲染（防运行期缺字/豆腐块）
	# 与 tools/gen_font.py 的 collect_chars() 同源：新增中文文案后重跑
	# `python tools/build_assets.py font` 即可把它们并入字体子集。
	var scan_files: Array = []
	_scan_sources("res://", scan_files)
	var src_missing: Array[String] = []
	var scanned: int = 0
	for path: String in scan_files:
		var fa: FileAccess = FileAccess.open(path, FileAccess.READ)
		if fa == null:
			continue
		var text: String = fa.get_as_text()
		fa.close()
		scanned += 1
		for ch: String in text:
			var code: int = ch.unicode_at(0)
			if code > 127 and not font.has_char(code) and not src_missing.has(ch):
				src_missing.append(ch)
	t.check(src_missing.is_empty(), "源码非 ASCII 字符全部可渲染（扫描 %d 文件，缺字 %d）%s" % [scanned, src_missing.size(), _brief(src_missing)])

	# --- 8. 工程纹理过滤为最近邻（像素风不糊）
	var filter_val: int = ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", -1)
	t.eq(filter_val, 0, "默认纹理过滤 = Nearest(0)，保证像素风锐利")


# ---------------------------------------------------------------- 辅助

## 递归收集工程源码文件（用于字体覆盖扫描），跳过 assets / addons / 隐藏目录
func _scan_sources(path: String, out: Array) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full: String = path.path_join(entry)
			if d.current_is_dir():
				if not SKIP_DIRS.has(entry):
					_scan_sources(full, out)
			else:
				for ext: String in SCAN_EXT:
					if entry.ends_with(ext):
						out.append(full)
						break
		entry = d.get_next()
	d.list_dir_end()


func _walk(path: String, pngs: Array, wavs: Array) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full: String = path.path_join(entry)
			if d.current_is_dir():
				_walk(full, pngs, wavs)
			elif entry.ends_with(".png"):
				pngs.append(full)
			elif entry.ends_with(".wav"):
				wavs.append(full)
		entry = d.get_next()
	d.list_dir_end()


## 返回 res://assets/ 下 png 所属的相对目录（如 "sprites/player"）
func _dir_of(path: String) -> String:
	var rel: String = path.trim_prefix("res://assets/")
	var idx: int = rel.rfind("/")
	return rel.substr(0, idx) if idx >= 0 else "."


func _require(path: String) -> Array:
	return [] if ResourceLoader.exists(path) else [path]


func _check_size(t: Node, path: String, w: int, h: int, label: String) -> void:
	var tex: Texture2D = load(path)
	if tex == null:
		t.check(false, label + "（文件缺失）")
		return
	t.check(tex.get_width() == w and tex.get_height() == h,
			"%s（实际 %dx%d）" % [label, tex.get_width(), tex.get_height()])


func _brief(items: Array) -> String:
	if items.is_empty():
		return ""
	var head: Array = items.slice(0, 4)
	var s: String = str(head)
	return s if items.size() <= 4 else s + " ...+%d" % (items.size() - 4)
