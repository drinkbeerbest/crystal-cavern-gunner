class_name MainMenu
extends Control
## MainMenu —— 主菜单（开始 / 继续 / 设置 / 退出）。
##
## 排版策略与 HUD 一致：在 640x360 的"逻辑画布"上摆放 1:1 像素素材，
## 再整体放大 UI_SCALE 倍。这样像素边缘保持锐利，也不用为每个控件算大尺寸坐标。
##
## 路由：所有跳转都交给 Main（scenes/main.tscn 根脚本），本界面不直接实例化游戏世界。

const UI_SCALE: int = 2
const LOGICAL_SIZE: Vector2 = Vector2(640, 360)
const UI_DIR: String = "res://assets/ui/"

const COLOR_BG: Color = Color(0.045, 0.045, 0.075, 1.0)
const COLOR_TITLE: Color = Color(1.0, 0.84, 0.42, 1.0)
const COLOR_TEXT: Color = Color(0.88, 0.9, 0.96, 1.0)
const COLOR_DIM: Color = Color(0.56, 0.6, 0.7, 1.0)

var router: Node = null

var _canvas: Control
var _menu_root: Control
var _settings_root: Control
var _start_button: Button
var _continue_button: Button
var _hint_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	router = _find_router()

	_build_background()
	_build_menu()
	_build_settings()
	_settings_root.visible = false
	_refresh_continue()

	if _start_button != null:
		_start_button.grab_focus()


# ==================== 构建 ====================

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 暗角，让中心菜单更聚焦
	var vignette := TextureRect.new()
	vignette.texture = _texture("vignette.png")
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.modulate = Color(1, 1, 1, 0.75)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	_canvas = Control.new()
	_canvas.name = "MenuCanvas"
	_canvas.size = LOGICAL_SIZE
	_canvas.scale = Vector2(UI_SCALE, UI_SCALE)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)


func _build_menu() -> void:
	_menu_root = Control.new()
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_menu_root)

	var logo := TextureRect.new()
	logo.texture = _texture("logo.png")
	logo.size = Vector2(176, 72)
	logo.position = Vector2((LOGICAL_SIZE.x - 176.0) * 0.5, 26)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(logo)

	_label("晶窟枪魂", Vector2(0, 104), Vector2(LOGICAL_SIZE.x, 18), 18, COLOR_TITLE,
			_menu_root, HORIZONTAL_ALIGNMENT_CENTER)
	_label("CRYSTAL CAVERN GUNNER", Vector2(0, 124), Vector2(LOGICAL_SIZE.x, 10), 9, COLOR_DIM,
			_menu_root, HORIZONTAL_ALIGNMENT_CENTER)

	var box := VBoxContainer.new()
	box.position = Vector2((LOGICAL_SIZE.x - 160.0) * 0.5, 148)
	box.size = Vector2(160, 120)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(box)

	_start_button = _menu_button("开始游戏", box, _on_start_pressed)
	_continue_button = _menu_button("继续上次", box, _on_continue_pressed)
	_menu_button("设  置", box, _on_settings_pressed)
	_menu_button("退出游戏", box, _on_quit_pressed)

	var meta_text: String = "最高层数 %d · 累计 %d 局 · v%s" % [
		int(GameState.best_floor), int(GameState.total_runs),
		str(ProjectSettings.get_setting("application/config/version", "0.1.0")),
	]
	_label(meta_text, Vector2(0, 322), Vector2(LOGICAL_SIZE.x, 10), 9, COLOR_DIM,
			_menu_root, HORIZONTAL_ALIGNMENT_CENTER)

	_hint_label = _label("Enter 开始 · Esc 退出设置", Vector2(0, 336), Vector2(LOGICAL_SIZE.x, 10),
			9, Color(0.42, 0.46, 0.56, 1.0), _menu_root, HORIZONTAL_ALIGNMENT_CENTER)


func _build_settings() -> void:
	_settings_root = Control.new()
	_settings_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.add_child(_settings_root)

	var panel := _nine_patch("panel_9.png", Vector2(LOGICAL_SIZE.x * 0.5 - 130, 44),
			Vector2(260, 268), 6, _settings_root)
	_label("设  置", Vector2(0, 12), Vector2(260, 14), 12, COLOR_TITLE, panel, HORIZONTAL_ALIGNMENT_CENTER)

	var row: float = 42.0
	row = _volume_row(panel, "主音量", "master_volume", row)
	row = _volume_row(panel, "音效", "sfx_volume", row)
	row = _volume_row(panel, "音乐", "bgm_volume", row)

	_toggle_row(panel, "全屏显示", "fullscreen", row)
	row += 26.0
	_toggle_row(panel, "画面晃动", "screen_shake", row)
	row += 26.0
	_toggle_row(panel, "显示帧率", "show_fps", row)
	row += 30.0

	_label("按键：WASD 移动 · 鼠标瞄准 · 左键射击 · Shift 冲刺", Vector2(16, row),
			Vector2(228, 10), 8, COLOR_DIM, panel, HORIZONTAL_ALIGNMENT_LEFT)
	_label("Space 技能 · E 交互 · 1-3 切枪 · Esc 暂停", Vector2(16, row + 12),
			Vector2(228, 10), 8, COLOR_DIM, panel, HORIZONTAL_ALIGNMENT_LEFT)

	var back := _pixel_button("返  回")
	back.position = Vector2((260 - 96) * 0.5, 232)
	back.size = Vector2(96, 22)
	panel.add_child(back)
	back.pressed.connect(_on_settings_back)


func _volume_row(parent: Control, title: String, key: String, y: float) -> float:
	_label(title, Vector2(18, y + 3), Vector2(56, 12), 10, COLOR_TEXT, parent, HORIZONTAL_ALIGNMENT_LEFT)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(GameState.settings.get(key, 0.8))
	slider.position = Vector2(78, y + 2)
	slider.size = Vector2(120, 12)
	slider.custom_minimum_size = Vector2(120, 12)
	slider.focus_mode = Control.FOCUS_NONE
	parent.add_child(slider)

	var value_label := _label("%d%%" % int(round(slider.value * 100.0)), Vector2(204, y + 3),
			Vector2(40, 12), 10, COLOR_DIM, parent, HORIZONTAL_ALIGNMENT_LEFT)
	slider.value_changed.connect(func(value: float) -> void:
		GameState.set_setting(key, value)
		value_label.text = "%d%%" % int(round(value * 100.0))
	)
	return y + 26.0


func _toggle_row(parent: Control, title: String, key: String, y: float) -> void:
	_label(title, Vector2(18, y + 4), Vector2(80, 12), 10, COLOR_TEXT, parent, HORIZONTAL_ALIGNMENT_LEFT)
	var check := CheckButton.new()
	check.button_pressed = bool(GameState.settings.get(key, false))
	check.position = Vector2(196, y)
	check.size = Vector2(48, 20)
	check.focus_mode = Control.FOCUS_NONE
	parent.add_child(check)
	check.toggled.connect(func(pressed: bool) -> void:
		GameState.set_setting(key, pressed)
		AudioMgr.play_sfx("ui_click", 0.0, -8.0)
	)


func _menu_button(text: String, parent: Control, callback: Callable) -> Button:
	var button := _pixel_button(text)
	button.custom_minimum_size = Vector2(160, 22)
	parent.add_child(button)
	button.pressed.connect(callback)
	button.focus_entered.connect(func() -> void: AudioMgr.play_sfx("ui_hover", 0.0, -14.0))
	return button


func _pixel_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.7, 0.95, 1.0, 1.0))
	button.add_theme_color_override("font_focus_color", COLOR_TITLE)
	button.add_theme_stylebox_override("normal", _stylebox("btn_9_normal.png"))
	button.add_theme_stylebox_override("hover", _stylebox("btn_9_hover.png"))
	button.add_theme_stylebox_override("pressed", _stylebox("btn_9_pressed.png"))
	button.add_theme_stylebox_override("disabled", _stylebox("btn_9_disabled.png"))
	button.add_theme_stylebox_override("focus", _stylebox("btn_9_hover.png"))
	return button


func _stylebox(relative_path: String) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _texture(relative_path)
	box.texture_margin_left = 4.0
	box.texture_margin_top = 4.0
	box.texture_margin_right = 4.0
	box.texture_margin_bottom = 4.0
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box


func _nine_patch(relative_path: String, pos: Vector2, box_size: Vector2, margin: int, parent: Control) -> NinePatchRect:
	var patch := NinePatchRect.new()
	patch.texture = _texture(relative_path)
	patch.position = pos
	patch.size = box_size
	patch.patch_margin_left = margin
	patch.patch_margin_top = margin
	patch.patch_margin_right = margin
	patch.patch_margin_bottom = margin
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(patch)
	return patch


func _label(text: String, pos: Vector2, box_size: Vector2, font_size: int, color: Color,
		parent: Control, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = box_size
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


static func _texture(relative_path: String) -> Texture2D:
	var path: String = UI_DIR + relative_path
	return load(path) if ResourceLoader.exists(path) else null


# ==================== 交互 ====================

func _refresh_continue() -> void:
	if _continue_button == null:
		return
	var has_save: bool = GameState.has_saved_run()
	_continue_button.disabled = not has_save
	_continue_button.tooltip_text = "读取上次未结束的一局" if has_save else "暂无存档"


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
		if _settings_root.visible:
			_close_settings()
			get_viewport().set_input_as_handled()


func _on_start_pressed() -> void:
	AudioMgr.play_sfx("ui_click")
	if router != null and router.has_method("start_new_run"):
		router.call("start_new_run", 0)


func _on_continue_pressed() -> void:
	if not GameState.has_saved_run():
		AudioMgr.play_sfx("ui_back", 0.0, -6.0)
		return
	AudioMgr.play_sfx("ui_click")
	if router != null and router.has_method("continue_run"):
		if not bool(router.call("continue_run")):
			_set_hint("存档读取失败，已为你开新局")
			if router.has_method("start_new_run"):
				router.call("start_new_run", 0)


func _on_settings_pressed() -> void:
	AudioMgr.play_sfx("ui_click")
	_menu_root.visible = false
	_settings_root.visible = true
	_set_hint("Esc 返回主菜单")


func _on_settings_back() -> void:
	_close_settings()


func _close_settings() -> void:
	AudioMgr.play_sfx("ui_back", 0.0, -6.0)
	_settings_root.visible = false
	_menu_root.visible = true
	_refresh_continue()
	_set_hint("Enter 开始 · Esc 退出设置")
	if _start_button != null:
		_start_button.grab_focus()


func _on_quit_pressed() -> void:
	AudioMgr.play_sfx("ui_back")
	# 优先走 Main 的统一退出入口（会清理静态纹理缓存）
	var router: Node = get_tree().current_scene
	if router != null and router.has_method("quit_game"):
		router.quit_game()
	else:
		get_tree().quit()


func _set_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text


## 向上找到场景路由器（Main）。测试环境里可能没有 Main，返回 null 即可。
func _find_router() -> Node:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("start_new_run"):
			return node
		node = node.get_parent()
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene != null and scene.has_method("start_new_run"):
		return scene
	return null
