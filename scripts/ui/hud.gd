class_name HUD
extends CanvasLayer
## HUD —— 战斗界面层（M3 版本，M8 会接入完整菜单与小地图）。
##
## 显示内容：生命 / 护盾 / 能量条、金币、层数、武器栏（图标 + 稀有度 + 名称描述）、
## 冲刺与技能冷却、交互提示、准星、低血量红晕、Boss 血条、飘字提示、暂停面板。
##
## 布局约定：UI 素材是 1x 像素图（bar_bg_9 只有 16x10），而窗口是 1280x720，
## 所以 HUD 在一个 640x360 的"逻辑画布"上排版，整体放大 UI_SCALE=2 倍，
## 与相机 zoom=2 的世界像素比例保持一致，放大后依然是锐利的像素风。
##
## 暂停由 HUD 负责：它自身 process_mode = ALWAYS，因此 Esc 在游戏暂停时依然可响应，
## 而世界节点（玩家/敌人/子弹）会跟着 get_tree().paused 一起冻结。

const G := preload("res://scripts/core/game_const.gd")
const TALENT_DB := preload("res://scripts/core/talent_db.gd")

const UI_DIR: String = "res://assets/ui/"
const PICKUP_DIR: String = "res://assets/pickups/"
const FONT: FontFile = preload("res://assets/fonts/pixel_ui.ttf")
const UI_SCALE: float = 2.0
const LOGICAL_SIZE: Vector2 = Vector2(640, 360)

const COLOR_TEXT: Color = Color(0.93, 0.94, 0.98)
const COLOR_DIM: Color = Color(0.70, 0.72, 0.80)
const COLOR_GOLD: Color = Color(1.0, 0.84, 0.34)
const COLOR_WARN: Color = Color(1.0, 0.44, 0.40)
const COLOR_OK: Color = Color(0.58, 1.0, 0.68)
## 稀有度对应颜色（与 assets/ui/rarity_0..3.png 同序）
const RARITY_COLORS: Array[Color] = [
	Color(0.78, 0.80, 0.86), Color(0.44, 0.90, 0.55),
	Color(0.42, 0.70, 1.0), Color(1.0, 0.68, 0.24),
]

const LOW_HP_RATIO: float = 0.35
const TOAST_DEFAULT_LIFE: float = 2.4

var player: Player = null
var world: Node = null
var is_paused: bool = false

# ---------- 节点引用 ----------
var _root: Control
var _ui: Control
var _hp_bar: TextureProgressBar
var _shield_bar: TextureProgressBar
var _energy_bar: TextureProgressBar
var _hp_text: Label
var _gold_label: Label
var _floor_label: Label
var _key_icon: TextureRect
var _weapon_name: Label
var _weapon_desc: Label
var _slots: Array = []
var _slot_icons: Array = []
var _slot_marks: Array = []
var _dash_cd: TextureProgressBar
var _skill_cd: TextureProgressBar
var _prompt: Label
var _toast: Label
var _vignette: TextureRect
var _crosshair: TextureRect
var _fps_label: Label
var _boss_panel: Control
var _boss_bar: TextureProgressBar
var _boss_name: Label
## M7：Boss 阶段横幅（转阶段时在血条下方弹出）
var _phase_banner: Label
var _phase_timer: float = 0.0
var _pause_overlay: Control
## M8：暂停面板内嵌设置子面板（音量/全屏/晃动/帧率），F2 或按钮打开
var _pause_canvas: Control
var _pause_settings: Control
## M6：天赋栏（图标 + 剩余时间条）与炸弹计数
var _talent_dock: Control
var _talent_slots: Array = []
var _talent_bars: Array = []
var _bomb_icon: TextureRect
var _bomb_label: Label

var _toast_timer: float = 0.0
var _crosshair_flash: float = 0.0
var _fps_timer: float = 0.0
var _low_hp_time: float = 0.0
## 天赋图标动画计时 / 上一次显示的炸弹数（避免每帧刷 Label）
var _talent_time: float = 0.0
var _bomb_shown: int = -1


func _ready() -> void:
	layer = 20
	# 暂停时 HUD 仍要响应 Esc / 刷新面板
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if player != null:
		_refresh_all()


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## 由 GameWorld 调用；可在 add_child 前后任意时机调用
func setup(target_player: Player, owner_world: Node = null) -> void:
	player = target_player
	world = owner_world
	if _root != null:
		_refresh_all()


# ==================== 构建 ====================

func _build() -> void:
	_root = Control.new()
	_root.name = "HudRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_ui = Control.new()
	_ui.name = "LogicalCanvas"
	_ui.size = LOGICAL_SIZE
	_ui.scale = Vector2(UI_SCALE, UI_SCALE)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ui)

	_build_status_panel()
	_build_top_right()
	_build_weapon_dock()
	_build_cooldowns()
	_build_talent_dock()
	_build_prompt_and_toast()
	_build_boss_bar()
	_build_phase_banner()
	_build_vignette()
	_build_crosshair()
	_build_pause_overlay()

	_update_mouse_mode()


func _build_status_panel() -> void:
	var panel := _nine_patch("panel_dark_9.png", Vector2(6, 6), Vector2(156, 56), 6)

	_icon("icon_heart.png", Vector2(12, 12), panel)
	_hp_bar = _bar("bar_fill_hp.png", Vector2(26, 12), Vector2(126, 9), 3, panel)
	_icon("icon_shield.png", Vector2(13, 25), panel, Vector2(0.62, 0.62))
	_shield_bar = _bar("bar_fill_shield.png", Vector2(26, 25), Vector2(126, 6), 3, panel)
	_icon("icon_energy.png", Vector2(13, 35), panel, Vector2(0.62, 0.62))
	_energy_bar = _bar("bar_fill_energy.png", Vector2(26, 35), Vector2(126, 6), 3, panel)

	_hp_text = _label("", Vector2(26, 43), Vector2(88, 9), 6, COLOR_TEXT, panel)
	_gold_label = _label("", Vector2(118, 43), Vector2(60, 9), 6, COLOR_GOLD, panel,
			HORIZONTAL_ALIGNMENT_RIGHT)
	_icon("icon_coin.png", Vector2(110, 43), panel, Vector2(0.72, 0.72))


func _build_top_right() -> void:
	_icon("icon_floor.png", Vector2(LOGICAL_SIZE.x - 78, 8), _ui, Vector2(0.9, 0.9))
	_floor_label = _label("第 1 层", Vector2(LOGICAL_SIZE.x - 64, 8), Vector2(56, 10), 7,
			COLOR_TEXT, _ui, HORIZONTAL_ALIGNMENT_LEFT)
	_fps_label = _label("", Vector2(LOGICAL_SIZE.x - 64, 20), Vector2(56, 9), 6, COLOR_DIM, _ui)
	_fps_label.visible = false
	# 地牢钥匙指示：拿到钥匙才亮，提示玩家"现在可以开 Boss 门了"
	_key_icon = _icon("icon_key.png", Vector2(LOGICAL_SIZE.x - 94, 8), _ui, Vector2(0.9, 0.9))
	_key_icon.visible = GameState.has_floor_key


func _build_weapon_dock() -> void:
	var dock := Control.new()
	dock.name = "WeaponDock"
	dock.size = Vector2(180, 46)
	dock.position = Vector2((LOGICAL_SIZE.x - 180) * 0.5, LOGICAL_SIZE.y - 52)
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(dock)

	for i: int in range(G.MAX_WEAPON_SLOTS):
		var slot := _nine_patch("slot_9.png", Vector2(4 + i * 26, 0), Vector2(22, 22), 4, dock)
		var icon := TextureRect.new()
		icon.texture = _tex("weapons/pistol.png")
		icon.size = Vector2(20, 20)
		icon.position = Vector2(1, 1)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate.a = 0.35
		slot.add_child(icon)

		var mark := _nine_patch("rarity_0.png", Vector2(-2, -2), Vector2(26, 26), 4, slot)
		mark.modulate = Color(1, 1, 1, 0)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var key := _label(str(i + 1), Vector2(2, 12), Vector2(8, 8), 6, COLOR_DIM, slot)
		_slots.append(slot)
		_slot_icons.append(icon)
		_slot_marks.append(mark)

	_weapon_name = _label("", Vector2(-40, 26), Vector2(260, 9), 7, COLOR_TEXT, dock,
			HORIZONTAL_ALIGNMENT_CENTER)
	_weapon_desc = _label("", Vector2(-60, 36), Vector2(300, 9), 6, COLOR_DIM, dock,
			HORIZONTAL_ALIGNMENT_CENTER)


func _build_cooldowns() -> void:
	var base := Vector2(10, LOGICAL_SIZE.y - 46)
	_dash_cd = _radial("bar_fill_dash.png", base, 16, _ui)
	_icon("icon_dash.png", base + Vector2(2, 2), _ui, Vector2(1.0, 1.0))
	_skill_cd = _radial("bar_fill_energy.png", base + Vector2(22, 0), 16, _ui)
	_icon("icon_skill.png", base + Vector2(24, 2), _ui, Vector2(1.0, 1.0))
	_label("Shift", base + Vector2(-1, 18), Vector2(20, 8), 5, COLOR_DIM, _ui, HORIZONTAL_ALIGNMENT_CENTER)
	_label("Space", base + Vector2(21, 18), Vector2(20, 8), 5, COLOR_DIM, _ui, HORIZONTAL_ALIGNMENT_CENTER)

	# 炸弹计数：图标 + 剩余枚数（F 键投掷）
	_nine_patch("slot_9.png", base + Vector2(44, 0), Vector2(16, 16), 3, _ui)
	_bomb_icon = TextureRect.new()
	_bomb_icon.texture = _tex_abs(PICKUP_DIR + "bomb_0.png")
	_bomb_icon.size = Vector2(12, 12)
	_bomb_icon.position = base + Vector2(46, 2)
	_bomb_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bomb_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bomb_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_bomb_icon)
	_bomb_label = _label("0", base + Vector2(61, 3), Vector2(18, 9), 7, COLOR_TEXT, _ui)
	_label("F", base + Vector2(43, 18), Vector2(20, 8), 5, COLOR_DIM, _ui, HORIZONTAL_ALIGNMENT_CENTER)


## 天赋栏：最多 G.TALENT_MAX_SLOTS 格，每格 = 天赋图标 + 剩余时间条
func _build_talent_dock() -> void:
	_talent_dock = Control.new()
	_talent_dock.name = "TalentDock"
	_talent_dock.position = Vector2(6, 66)
	_talent_dock.size = Vector2(float(G.TALENT_MAX_SLOTS) * 24.0, 26)
	_talent_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_talent_dock.visible = false
	_ui.add_child(_talent_dock)
	for i: int in range(G.TALENT_MAX_SLOTS):
		var slot := _nine_patch("slot_9.png", Vector2(i * 24, 0), Vector2(20, 20), 4, _talent_dock)
		var icon := TextureRect.new()
		icon.size = Vector2(16, 16)
		icon.position = Vector2(2, 1)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var bar := TextureProgressBar.new()
		bar.texture_under = _tex("bar_bg_9.png")
		bar.texture_progress = _tex("bar_fill_energy.png")
		bar.nine_patch_stretch = true
		_set_stretch_margin(bar, 2)
		bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
		bar.position = Vector2(i * 24, 21)
		bar.size = Vector2(20, 3)
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = 1.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_talent_dock.add_child(bar)
		_talent_slots.append(icon)
		_talent_bars.append(bar)


func _build_prompt_and_toast() -> void:
	_prompt = _label("", Vector2(LOGICAL_SIZE.x * 0.5 - 90, LOGICAL_SIZE.y - 78), Vector2(180, 10), 7,
			COLOR_OK, _ui, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.visible = false

	_toast = _label("", Vector2(LOGICAL_SIZE.x * 0.5 - 150, 62), Vector2(300, 12), 8,
			COLOR_TEXT, _ui, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.modulate.a = 0.0


func _build_boss_bar() -> void:
	_boss_panel = Control.new()
	_boss_panel.name = "BossBar"
	_boss_panel.position = Vector2(LOGICAL_SIZE.x * 0.5 - 110, 22)
	_boss_panel.size = Vector2(220, 26)
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.visible = false
	_ui.add_child(_boss_panel)

	_nine_patch("boss_bar_9.png", Vector2(0, 10), Vector2(220, 14), 4, _boss_panel)
	_boss_bar = _bar("bar_fill_boss.png", Vector2(4, 13), Vector2(212, 8), 3, _boss_panel)
	_boss_name = _label("", Vector2(0, 0), Vector2(220, 10), 7, COLOR_WARN, _boss_panel,
			HORIZONTAL_ALIGNMENT_CENTER)


## M7：Boss 阶段横幅，默认隐藏；boss_phase_changed 时弹出并按 _phase_timer 淡出
func _build_phase_banner() -> void:
	_phase_banner = _label("", Vector2(LOGICAL_SIZE.x * 0.5 - 100, 44), Vector2(200, 12), 9,
			COLOR_WARN, _ui, HORIZONTAL_ALIGNMENT_CENTER)
	_phase_banner.modulate.a = 0.0


func _build_vignette() -> void:
	_vignette = TextureRect.new()
	_vignette.texture = _tex("vignette.png")
	_vignette.size = LOGICAL_SIZE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate = Color(1.0, 0.18, 0.16, 0.0)
	_ui.add_child(_vignette)


func _build_crosshair() -> void:
	# 准星放在未缩放的 root 上，直接跟随系统鼠标坐标
	_crosshair = TextureRect.new()
	_crosshair.texture = _tex("crosshair_0.png")
	_crosshair.size = Vector2(16, 16)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)
	if not EventBus.weapon_fired.is_connected(_on_weapon_fired):
		EventBus.weapon_fired.connect(_on_weapon_fired)
	if not EventBus.interactable_focused.is_connected(_on_interactable_focused):
		EventBus.interactable_focused.connect(_on_interactable_focused)
	if not EventBus.interactable_blurred.is_connected(_on_interactable_blurred):
		EventBus.interactable_blurred.connect(_on_interactable_blurred)
	if not EventBus.toast_message.is_connected(show_toast):
		EventBus.toast_message.connect(show_toast)
	if not GameState.floor_changed.is_connected(_on_floor_changed):
		GameState.floor_changed.connect(_on_floor_changed)
	if not GameState.key_changed.is_connected(_on_key_changed):
		GameState.key_changed.connect(_on_key_changed)
	if not EventBus.boss_spawned.is_connected(_on_boss_spawned):
		EventBus.boss_spawned.connect(_on_boss_spawned)
	if not EventBus.boss_health_changed.is_connected(_on_boss_health_changed):
		EventBus.boss_health_changed.connect(_on_boss_health_changed)
	if not EventBus.boss_died.is_connected(_on_boss_died):
		EventBus.boss_died.connect(_on_boss_died)
	if not EventBus.boss_phase_changed.is_connected(_on_boss_phase_changed):
		EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	if not EventBus.boss_minions_cleared.is_connected(_on_boss_minions_cleared):
		EventBus.boss_minions_cleared.connect(_on_boss_minions_cleared)


func _build_pause_overlay() -> void:
	_pause_overlay = Control.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.visible = false
	_root.add_child(_pause_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(dim)

	# 暂停面板同样在 640x360 逻辑画布上排版（_pause_overlay 本身在未缩放空间）
	_pause_canvas = Control.new()
	_pause_canvas.name = "PauseCanvas"
	_pause_canvas.size = LOGICAL_SIZE
	_pause_canvas.scale = Vector2(UI_SCALE, UI_SCALE)
	_pause_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(_pause_canvas)

	var panel := _nine_patch("panel_9.png", Vector2(LOGICAL_SIZE.x * 0.5 - 100, LOGICAL_SIZE.y * 0.5 - 74),
			Vector2(200, 148), 6, _pause_canvas)
	_label("已 暂 停", Vector2(0, 12), Vector2(200, 14), 12, COLOR_TEXT, panel, HORIZONTAL_ALIGNMENT_CENTER)
	var lines: Array[String] = [
		"Esc      继续游戏",
		"Enter    重新开始本局",
		"M        返回主菜单",
		"F2       打开设置",
		"F3       显示 / 隐藏帧率",
	]
	for i: int in range(lines.size()):
		_label(lines[i], Vector2(28, 40 + i * 14), Vector2(160, 10), 7, COLOR_DIM, panel)
	_label("晶窟枪魂 · v%s" % str(ProjectSettings.get_setting("application/config/version", "0.1.0")),
			Vector2(0, 122), Vector2(200, 9), 6, COLOR_DIM, panel, HORIZONTAL_ALIGNMENT_CENTER)

	_build_pause_settings()


## M8：暂停时的内嵌设置子面板（音量 / 全屏 / 晃动 / 帧率），
## 复用主菜单相同的设置键（GameState.set_setting），F2 或 Esc 关闭。
func _build_pause_settings() -> void:
	_pause_settings = Control.new()
	_pause_settings.name = "PauseSettings"
	_pause_settings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_settings.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_settings.visible = false
	_pause_canvas.add_child(_pause_settings)

	var panel := _nine_patch("panel_9.png",
			Vector2(LOGICAL_SIZE.x * 0.5 - 120, LOGICAL_SIZE.y * 0.5 - 74),
			Vector2(240, 148), 6, _pause_settings)
	_label("设  置", Vector2(0, 10), Vector2(240, 14), 12, COLOR_TEXT, panel, HORIZONTAL_ALIGNMENT_CENTER)

	var row: float = 34.0
	row = _pause_volume_row(panel, "主音量", "master_volume", row)
	row = _pause_volume_row(panel, "音效", "sfx_volume", row)
	row = _pause_volume_row(panel, "音乐", "bgm_volume", row)
	_pause_toggle_row(panel, "全屏", "fullscreen", row)
	row += 24.0
	_pause_toggle_row(panel, "画面晃动", "screen_shake", row)
	row += 24.0
	_pause_toggle_row(panel, "显示帧率", "show_fps", row)
	row += 26.0
	_label("Esc 关闭", Vector2(0, row), Vector2(240, 10), 8, COLOR_DIM, panel, HORIZONTAL_ALIGNMENT_CENTER)


func _pause_volume_row(parent: Control, title: String, key: String, y: float) -> float:
	_label(title, Vector2(20, y + 3), Vector2(52, 12), 9, COLOR_TEXT, parent, HORIZONTAL_ALIGNMENT_LEFT)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(GameState.settings.get(key, 0.8))
	slider.position = Vector2(76, y + 1)
	slider.size = Vector2(108, 12)
	slider.custom_minimum_size = Vector2(108, 12)
	slider.focus_mode = Control.FOCUS_NONE
	parent.add_child(slider)
	var value_label := _label("%d%%" % int(round(slider.value * 100.0)), Vector2(192, y + 3),
			Vector2(34, 12), 9, COLOR_DIM, parent, HORIZONTAL_ALIGNMENT_LEFT)
	slider.value_changed.connect(func(value: float) -> void:
		GameState.set_setting(key, value)
		value_label.text = "%d%%" % int(round(value * 100.0))
	)
	return y + 24.0


func _pause_toggle_row(parent: Control, title: String, key: String, y: float) -> void:
	_label(title, Vector2(20, y + 3), Vector2(72, 12), 9, COLOR_TEXT, parent, HORIZONTAL_ALIGNMENT_LEFT)
	var check := CheckButton.new()
	check.button_pressed = bool(GameState.settings.get(key, false))
	check.position = Vector2(170, y)
	check.size = Vector2(44, 18)
	check.focus_mode = Control.FOCUS_NONE
	parent.add_child(check)
	check.toggled.connect(func(pressed: bool) -> void:
		GameState.set_setting(key, pressed)
		AudioMgr.play_sfx("ui_click", 0.0, -8.0)
	)


# ---------- 构建小工具 ----------

func _tex(relative_path: String) -> Texture2D:
	var path: String = UI_DIR + relative_path
	return load(path) if ResourceLoader.exists(path) else null


## 绝对 res:// 路径取图（天赋图标在 assets/pickups/ 下，不在 UI 目录里）
func _tex_abs(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _label(text: String, pos: Vector2, size: Vector2, font_size: int, color: Color,
		parent: Control, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = size
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.08, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _icon(relative_path: String, pos: Vector2, parent: Control, icon_scale: Vector2 = Vector2.ONE) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _tex(relative_path)
	icon.position = pos
	icon.size = Vector2(12, 12) * icon_scale
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon


func _nine_patch(relative_path: String, pos: Vector2, size: Vector2, margin: int, parent: Control = null) -> NinePatchRect:
	var host: Control = parent if parent != null else _ui
	var patch := NinePatchRect.new()
	patch.texture = _tex(relative_path)
	patch.position = pos
	patch.size = size
	patch.patch_margin_left = margin
	patch.patch_margin_top = margin
	patch.patch_margin_right = margin
	patch.patch_margin_bottom = margin
	patch.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	patch.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(patch)
	return patch


## Godot 4.7 的 TextureProgressBar 没有统一的 stretch_margin 属性，
## 只有 stretch_margin_left/top/right/bottom 四个独立整数属性。
func _set_stretch_margin(bar: TextureProgressBar, margin: int) -> void:
	bar.stretch_margin_left = margin
	bar.stretch_margin_top = margin
	bar.stretch_margin_right = margin
	bar.stretch_margin_bottom = margin


func _bar(fill_texture: String, pos: Vector2, size: Vector2, margin: int, parent: Control) -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.texture_under = _tex("bar_bg_9.png")
	bar.texture_progress = _tex(fill_texture)
	bar.nine_patch_stretch = true
	_set_stretch_margin(bar, margin)
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	bar.position = pos
	bar.size = size
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


func _radial(fill_texture: String, pos: Vector2, size: float, parent: Control) -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.texture_under = _tex("bar_bg_9.png")
	bar.texture_progress = _tex(fill_texture)
	bar.nine_patch_stretch = true
	_set_stretch_margin(bar, 3)
	bar.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	bar.position = pos
	bar.size = Vector2(size, size)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


# ==================== 每帧刷新 ====================

func _process(delta: float) -> void:
	_update_crosshair(delta)
	_update_toast(delta)
	_update_phase_banner(delta)
	_update_fps(delta)
	_update_talent_dock(delta)
	_update_bomb_counter()
	if is_paused:
		return
	if player == null or not is_instance_valid(player):
		return
	_update_resource_bars()
	_update_weapon_dock()
	_update_cooldowns()
	_update_low_hp(delta)


func _update_resource_bars() -> void:
	var max_health: float = maxf(player.max_health(), 1.0)
	var max_shield: float = player.max_shield()
	var max_energy: float = maxf(player.max_energy(), 1.0)
	_hp_bar.max_value = max_health
	_hp_bar.value = player.health()
	_shield_bar.max_value = maxf(max_shield, 1.0)
	_shield_bar.value = player.shield()
	_shield_bar.modulate.a = 1.0 if max_shield > 0.0 else 0.35
	_energy_bar.max_value = max_energy
	_energy_bar.value = player.energy()
	_hp_text.text = "%d / %d" % [int(ceil(player.health())), int(max_health)]
	_hp_text.add_theme_color_override("font_color", COLOR_WARN if player.health() / max_health <= LOW_HP_RATIO else COLOR_TEXT)
	_gold_label.text = str(GameState.gold)
	_floor_label.text = "第 %d 层" % GameState.floor_index


func _update_weapon_dock() -> void:
	var weapons: Array = player.weapons
	var current_index: int = player.weapon_index
	for i: int in range(_slots.size()):
		var icon: TextureRect = _slot_icons[i]
		var mark: NinePatchRect = _slot_marks[i]
		if i >= weapons.size():
			icon.texture = null
			icon.modulate.a = 0.0
			mark.modulate.a = 0.0
			continue
		var weapon: WeaponData = weapons[i]
		if weapon == null:
			continue
		icon.texture = weapon.icon_texture()
		var selected: bool = i == current_index
		icon.modulate = Color(1, 1, 1, 1.0) if selected else Color(1, 1, 1, 0.42)
		mark.texture = _tex("rarity_%d.png" % clampi(int(weapon.rarity), 0, 3))
		mark.modulate = Color(RARITY_COLORS[clampi(int(weapon.rarity), 0, 3)], 0.95 if selected else 0.0)
		_slots[i].modulate = Color(1, 1, 1, 1.0) if selected else Color(0.82, 0.84, 0.9, 0.72)

	var current: WeaponData = player.current_weapon()
	if current == null:
		_weapon_name.text = ""
		_weapon_desc.text = ""
		return
	_weapon_name.text = "%s · %s" % [current.display_name, current.rarity_name()]
	_weapon_name.add_theme_color_override("font_color", RARITY_COLORS[clampi(int(current.rarity), 0, 3)])
	_weapon_desc.text = "%s   伤害 %d / 射速 %.1f / 耗能 %d" % [
		current.description, int(round(current.damage)), current.fire_rate, int(round(current.energy_cost)),
	]


func _update_cooldowns() -> void:
	var dash_total: float = maxf(player.stat("dash_cooldown"), 0.01)
	_dash_cd.value = clampf(1.0 - player.dash_cooldown_timer / dash_total, 0.0, 1.0)
	_dash_cd.modulate = Color(1, 1, 1, 1) if player.dash_ready() else Color(1, 1, 1, 0.55)

	var skill_total: float = maxf(player.stat("skill_cooldown"), 0.01)
	var ratio: float = clampf(1.0 - player.skill_cooldown_timer / skill_total, 0.0, 1.0)
	_skill_cd.value = ratio
	var affordable: bool = player.energy() >= G.SKILL_ENERGY_COST
	_skill_cd.modulate = Color(1, 1, 1, 1) if (player.skill_ready() and affordable) else Color(1, 0.6, 0.55, 0.7)


## 天赋栏刷新：图标按帧轮换，时间条显示剩余 / 总时长
func _update_talent_dock(delta: float) -> void:
	if _talent_dock == null:
		return
	_talent_time += delta
	var list: Array = GameState.talents
	_talent_dock.visible = not list.is_empty()
	for i: int in range(_talent_slots.size()):
		var icon: TextureRect = _talent_slots[i]
		var bar: TextureProgressBar = _talent_bars[i]
		if i >= list.size():
			icon.visible = false
			bar.visible = false
			continue
		var entry: Dictionary = list[i]
		var tid: String = str(entry.get("id", ""))
		icon.visible = true
		bar.visible = true
		var frame: int = int(_talent_time * 7.0) % TALENT_DB.ICON_FRAMES
		var texture: Texture2D = _tex_abs(TALENT_DB.icon_path(tid, frame))
		if texture != null:
			icon.texture = texture
		var total: float = maxf(float(entry.get("duration", G.TALENT_DEFAULT_DURATION)), 0.01)
		var remain: float = clampf(float(entry.get("remain", 0.0)), 0.0, total)
		bar.max_value = total
		bar.value = remain
		# 快到期时转红，提示玩家增益要掉了
		bar.modulate = Color(1, 1, 1) if remain / total > 0.25 else Color(1.0, 0.55, 0.5)


## 炸弹计数：数量变化才改文字，避免每帧重建 Label 字符串
func _update_bomb_counter() -> void:
	if _bomb_label == null:
		return
	var count: int = GameState.bombs
	if count != _bomb_shown:
		_bomb_shown = count
		_bomb_label.text = str(count)
	_bomb_label.modulate.a = 1.0 if count > 0 else 0.45
	if _bomb_icon != null:
		_bomb_icon.modulate.a = 1.0 if count > 0 else 0.4


func _update_low_hp(delta: float) -> void:
	var max_health: float = maxf(player.max_health(), 1.0)
	var ratio: float = player.health() / max_health
	if player.dead:
		_vignette.modulate = Color(0.6, 0.04, 0.04, 0.72)
		return
	if ratio <= LOW_HP_RATIO:
		_low_hp_time += delta
		var pulse: float = 0.22 + 0.14 * sin(_low_hp_time * 6.0)
		_vignette.modulate = Color(1.0, 0.16, 0.14, pulse)
	else:
		_low_hp_time = 0.0
		_vignette.modulate.a = maxf(_vignette.modulate.a - delta * 1.6, 0.0)


func _update_crosshair(delta: float) -> void:
	if _crosshair == null:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	_crosshair.position = mouse - _crosshair.size * 0.5
	_crosshair.visible = not is_paused and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN
	if _crosshair_flash > 0.0:
		_crosshair_flash = maxf(_crosshair_flash - delta, 0.0)
		if _crosshair_flash <= 0.0:
			_crosshair.texture = _tex("crosshair_0.png")
			_crosshair.scale = Vector2.ONE


func _update_toast(delta: float) -> void:
	if _toast_timer <= 0.0:
		return
	_toast_timer = maxf(_toast_timer - delta, 0.0)
	_toast.modulate.a = clampf(_toast_timer / 0.5, 0.0, 1.0)


func _update_fps(delta: float) -> void:
	var show_fps: bool = bool(GameState.settings.get("show_fps", false))
	_fps_label.visible = show_fps
	if not show_fps:
		return
	_fps_timer -= delta
	if _fps_timer > 0.0:
		return
	_fps_timer = 0.4
	_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _refresh_all() -> void:
	_on_key_changed(GameState.has_floor_key)
	_bomb_shown = -1
	_update_bomb_counter()
	if player == null:
		return
	_update_resource_bars()
	_update_weapon_dock()
	_on_floor_changed(GameState.floor_index)


# ==================== 暂停 ====================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if is_paused and _pause_settings != null and _pause_settings.visible:
			_close_pause_settings()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if not is_paused:
		return
	if event.is_action_pressed("confirm"):
		if _pause_settings != null and _pause_settings.visible:
			_close_pause_settings()
		else:
			restart_run()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M or event.physical_keycode == KEY_M:
			if _pause_settings != null and _pause_settings.visible:
				_close_pause_settings()
			else:
				goto_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2 or event.physical_keycode == KEY_F2:
			_toggle_pause_settings()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F3 or event.physical_keycode == KEY_F3:
			GameState.set_setting("show_fps", not bool(GameState.settings.get("show_fps", false)))


func _toggle_pause_settings() -> void:
	if _pause_settings == null:
		return
	_pause_settings.visible = not _pause_settings.visible
	AudioMgr.play_sfx("ui_click", 0.0, -8.0)


func _close_pause_settings() -> void:
	if _pause_settings != null:
		_pause_settings.visible = false
	AudioMgr.play_sfx("ui_back", 0.0, -6.0)


func toggle_pause(force: bool = false) -> void:
	set_pause(force if force else not is_paused)


func set_pause(value: bool) -> void:
	if is_paused == value:
		return
	is_paused = value
	get_tree().paused = value
	_pause_overlay.visible = value
	if _pause_settings != null:
		_pause_settings.visible = false
	_update_mouse_mode()
	EventBus.pause_state_changed.emit(value)
	if value:
		AudioMgr.play_sfx("ui_click", 0.0, -6.0)


func restart_run() -> void:
	set_pause(false)
	var router: Node = get_tree().current_scene
	if router != null and router.has_method("restart_run"):
		router.call("restart_run")


func goto_menu() -> void:
	set_pause(false)
	var router: Node = get_tree().current_scene
	if router != null and router.has_method("goto_menu"):
		router.call("goto_menu")


func _update_mouse_mode() -> void:
	# 战斗中隐藏系统指针（画自绘准星），暂停时恢复以便点菜单
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_HIDDEN)


# ==================== 对外接口 ====================

func show_toast(text: String, life: float = TOAST_DEFAULT_LIFE) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast_timer = life
	_toast.modulate.a = 1.0


func set_prompt(text: String) -> void:
	if _prompt == null:
		return
	_prompt.text = text
	_prompt.visible = not text.is_empty()


# ---------- 信号回调 ----------

func _on_weapon_fired(_weapon: Resource, _is_crit: bool) -> void:
	if _crosshair == null:
		return
	_crosshair.texture = _tex("crosshair_1.png")
	_crosshair.scale = Vector2.ONE * 1.18
	_crosshair.pivot_offset = _crosshair.size * 0.5
	_crosshair_flash = 0.09


func _on_interactable_focused(prompt_text: String) -> void:
	set_prompt(prompt_text)


func _on_interactable_blurred() -> void:
	set_prompt("")


func _on_floor_changed(floor_index: int) -> void:
	if _floor_label != null:
		_floor_label.text = "第 %d 层" % floor_index


func _on_key_changed(has_key: bool) -> void:
	if _key_icon != null:
		_key_icon.visible = has_key


func _on_boss_spawned(boss: Node) -> void:
	if _boss_panel == null:
		return
	var boss_name: String = "Boss"
	if boss != null and "display_name" in boss:
		boss_name = str(boss.display_name)
	_boss_name.text = boss_name
	_boss_panel.visible = true
	if boss != null and "health" in boss and "max_health_value" in boss:
		_boss_bar.max_value = float(boss.max_health_value)
		_boss_bar.value = float(boss.health)


func _on_boss_health_changed(current: float, max_value: float) -> void:
	if _boss_bar == null:
		return
	_boss_bar.max_value = maxf(max_value, 1.0)
	_boss_bar.value = current


func _on_boss_died(_boss: Node) -> void:
	if _boss_panel != null:
		_boss_panel.visible = false


## Boss 转阶段弹横幅：显示阶段号后缓慢淡出
func _on_boss_phase_changed(_boss: Node, phase_index: int) -> void:
	if _phase_banner == null:
		return
	_phase_banner.text = "阶段 %d" % phase_index
	_phase_banner.modulate.a = 1.0
	_phase_timer = 1.6


## Boss 房小怪从有到无：提示玩家可以专心打 Boss 了
func _on_boss_minions_cleared(_boss: Node) -> void:
	show_toast("小怪已清空", 1.6)


func _update_phase_banner(delta: float) -> void:
	if _phase_banner == null or _phase_timer <= 0.0:
		return
	_phase_timer = maxf(_phase_timer - delta, 0.0)
	_phase_banner.modulate.a = clampf(_phase_timer / 0.45, 0.0, 1.0)
