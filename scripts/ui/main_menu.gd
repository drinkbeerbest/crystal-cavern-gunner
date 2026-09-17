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

const G = preload("res://scripts/core/game_const.gd")

const COLOR_BG: Color = Color(0.045, 0.045, 0.075, 1.0)
const COLOR_TITLE: Color = Color(1.0, 0.84, 0.42, 1.0)
const COLOR_TEXT: Color = Color(0.88, 0.9, 0.96, 1.0)
const COLOR_DIM: Color = Color(0.56, 0.6, 0.7, 1.0)

var router: Node = null

var _canvas: Control
var _menu_root: Control
var _floor_select_root: Control
var _settings_root: Control
var _armory_root: Control
var _armory_wallet_label: Label
var _armory_kit_slots: Array = []   ## 上方 3 槽位字典 {weapon_id, card, bg, icon, name_label, stat_label}
var _armory_cards: Array = []       ## 下方 12 武器卡片字典 {weapon_id, card, price_label}
var _selected_slot: int = -1        ## 当前选中的槽位下标（-1=未选）
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
	_build_floor_select()
	_build_settings()
	_build_armory()
	_floor_select_root.visible = false
	_settings_root.visible = false
	_armory_root.visible = false
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
	box.position = Vector2((LOGICAL_SIZE.x - 160.0) * 0.5, 140)
	box.size = Vector2(160, 170)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(box)

	_start_button = _menu_button("开始游戏", box, _on_start_pressed)
	_continue_button = _menu_button("继续上次", box, _on_continue_pressed)
	_menu_button("武器图鉴", box, _on_armory_pressed)
	_menu_button("设  置", box, _on_settings_pressed)
	_menu_button("退出游戏", box, _on_quit_pressed)

	var meta_text: String = "账户金币 %d · 最高层数 %d · 累计 %d 局 · v%s" % [
		int(GameState.account_gold), int(GameState.best_floor), int(GameState.total_runs),
		str(ProjectSettings.get_setting("application/config/version", "0.1.0")),
	]
	_label(meta_text, Vector2(0, 324), Vector2(LOGICAL_SIZE.x, 10), 9, COLOR_DIM,
			_menu_root, HORIZONTAL_ALIGNMENT_CENTER)

	_hint_label = _label("Enter 开始 · Esc 退出设置", Vector2(0, 338), Vector2(LOGICAL_SIZE.x, 10),
			9, Color(0.42, 0.46, 0.56, 1.0), _menu_root, HORIZONTAL_ALIGNMENT_CENTER)


func _build_floor_select() -> void:
	_floor_select_root = Control.new()
	_floor_select_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_floor_select_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.add_child(_floor_select_root)

	var panel := _nine_patch("panel_9.png", Vector2(LOGICAL_SIZE.x * 0.5 - 130, 44),
			Vector2(260, 268), 6, _floor_select_root)
	_label("选择关卡", Vector2(0, 12), Vector2(260, 14), 12, COLOR_TITLE, panel, HORIZONTAL_ALIGNMENT_CENTER)

	var unlocked: int = GameState.unlocked_floor
	var total: int = G.TOTAL_FLOORS
	var row: float = 42.0
	for i: int in range(1, total + 1):
		var btn := _pixel_button("第 %d 层" % i)
		btn.custom_minimum_size = Vector2(120, 22)
		btn.position = Vector2((260 - 120) * 0.5, row)
		btn.size = Vector2(120, 22)
		if i > unlocked:
			btn.disabled = true
			btn.text += "（未解锁）"
			btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55, 1.0))
		else:
			var start_floor: int = i
			btn.pressed.connect(func() -> void:
				AudioMgr.play_sfx("ui_click")
				if router != null and router.has_method("start_new_run"):
					router.call("start_new_run", 0, start_floor)
			)
		panel.add_child(btn)
		row += 28.0

	var back := _pixel_button("返  回")
	back.position = Vector2((260 - 96) * 0.5, 232)
	back.size = Vector2(96, 22)
	panel.add_child(back)
	back.pressed.connect(_on_floor_select_back)


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


func _build_armory() -> void:
	_armory_root = Control.new()
	_armory_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_armory_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.add_child(_armory_root)

	var panel := _nine_patch("panel_9.png", Vector2(10, 14), Vector2(620, 330), 6, _armory_root)
	_label("武 器 图 鉴", Vector2(0, 10), Vector2(620, 16), 12, COLOR_TITLE, panel, HORIZONTAL_ALIGNMENT_CENTER)

	_armory_wallet_label = _label("", Vector2(16, 28), Vector2(300, 12), 10,
			Color(1.0, 0.84, 0.42, 1.0), panel, HORIZONTAL_ALIGNMENT_LEFT)

	# ----- 上方：当前开局 3 槽位（可点选）-----
	_label("当前开局武器（点击槽位选择，再在下方购买武器替换）",
			Vector2(16, 42), Vector2(588, 11), 8, COLOR_DIM, panel, HORIZONTAL_ALIGNMENT_LEFT)

	var slot_w: float = 186.0
	var slot_h: float = 52.0
	var slot_gap: float = 8.0
	var slot_y: float = 58.0
	for i: int in range(3):
		var slot_pos := Vector2(16.0 + i * (slot_w + slot_gap), slot_y)
		_armory_kit_slots.append(_armory_kit_slot(panel, i, slot_pos, Vector2(slot_w, slot_h)))

	# ----- 分隔线 -----
	var divider := ColorRect.new()
	divider.color = Color(0.3, 0.3, 0.45, 0.6)
	divider.position = Vector2(16, slot_y + slot_h + 6)
	divider.size = Vector2(588, 1)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider)

	# ----- 下方：全部武器列表（12 把）-----
	var card_w: float = 186.0
	var card_h: float = 48.0
	var gap_x: float = 8.0
	var gap_y: float = 6.0
	var start_x: float = 16.0
	var start_y: float = slot_y + slot_h + 16.0

	var index: int = 0
	for weapon_id: Variant in WeaponDB.ids():
		var col: int = index % 3
		var row: int = index / 3
		var card_pos := Vector2(start_x + col * (card_w + gap_x), start_y + row * (card_h + gap_y))
		_armory_cards.append(_armory_card(panel, str(weapon_id), card_pos, Vector2(card_w, card_h)))
		index += 1

	var back := _pixel_button("返  回")
	back.position = Vector2((620 - 96) * 0.5, 300)
	back.size = Vector2(96, 22)
	panel.add_child(back)
	back.pressed.connect(_on_armory_back)


## 单个开局槽位卡片（上方 3 个），可点击选中
func _armory_kit_slot(parent: Control, index: int, pos: Vector2, card_size: Vector2) -> Dictionary:
	var weapon_id: String = GameState.starter_kit_ids[index] if index < GameState.starter_kit_ids.size() else WeaponDB.STARTER_ID
	var weapon: WeaponData = WeaponDB.create(weapon_id)
	if weapon == null:
		weapon = WeaponDB.create(WeaponDB.STARTER_ID)

	var card := Control.new()
	card.position = pos
	card.size = card_size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(card)

	var bg := _nine_patch("panel_9.png", Vector2.ZERO, card_size, 4, card)
	# 默认边框较暗，选中后高亮
	bg.modulate = Color(0.7, 0.7, 0.85, 1.0)

	var icon := TextureRect.new()
	icon.texture = weapon.icon_texture()
	icon.position = Vector2(6, 6)
	icon.size = Vector2(18, 18)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)

	var rarity_color: Color = _rarity_color(int(weapon.rarity))
	var name_label := _label(weapon.display_name, Vector2(30, 4), Vector2(148, 13), 10,
			rarity_color, card, HORIZONTAL_ALIGNMENT_LEFT)
	var stat_label := _label("伤害 %d · 耗能 %d" % [int(weapon.damage), int(weapon.energy_cost)],
			Vector2(30, 19), Vector2(148, 11), 8, COLOR_DIM, card, HORIZONTAL_ALIGNMENT_LEFT)
	var slot_label := _label("槽位 %d" % (index + 1), Vector2(30, 33), Vector2(148, 11), 8,
			Color(0.68, 0.86, 1.0, 1.0), card, HORIZONTAL_ALIGNMENT_LEFT)

	var click := Button.new()
	click.text = ""
	click.position = Vector2.ZERO
	click.size = card_size
	click.flat = true
	click.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_child(click)
	click.pressed.connect(_on_armory_slot_pressed.bind(index))

	return {"index": index, "weapon_id": weapon_id, "card": card, "bg": bg,
			"icon": icon, "name_label": name_label, "stat_label": stat_label, "slot_label": slot_label}


## 单张武器卡片（下方列表）：图标 + 名称（稀有度色）+ 伤害/耗能 + 价格，点击购买并替换已选槽位
func _armory_card(parent: Control, weapon_id: String, pos: Vector2, card_size: Vector2) -> Dictionary:
	var weapon: WeaponData = WeaponDB.create(weapon_id)
	if weapon == null:
		return {}
	var card := Control.new()
	card.position = pos
	card.size = card_size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(card)

	var bg := _nine_patch("panel_9.png", Vector2.ZERO, card_size, 4, card)

	var icon := TextureRect.new()
	icon.texture = weapon.icon_texture()
	icon.position = Vector2(6, 6)
	icon.size = Vector2(18, 18)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)

	var rarity_color: Color = _rarity_color(int(weapon.rarity))
	var name_label := _label(weapon.display_name, Vector2(30, 4), Vector2(148, 13), 10,
			rarity_color, card, HORIZONTAL_ALIGNMENT_LEFT)
	var stat_label := _label("伤害 %d · 耗能 %d" % [int(weapon.damage), int(weapon.energy_cost)],
			Vector2(30, 19), Vector2(148, 11), 8, COLOR_DIM, card, HORIZONTAL_ALIGNMENT_LEFT)
	var price_label := _label("", Vector2(30, 33), Vector2(148, 11), 9,
			Color(0.68, 0.86, 1.0, 1.0), card, HORIZONTAL_ALIGNMENT_LEFT)

	var click := Button.new()
	click.text = ""
	click.position = Vector2.ZERO
	click.size = card_size
	click.flat = true
	click.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_child(click)
	click.pressed.connect(_on_armory_weapon_pressed.bind(weapon_id))

	var price: int = int(WeaponDB.TABLE[weapon_id].get("price", 0))
	var in_kit: bool = GameState.starter_kit_ids.has(weapon_id)
	if in_kit:
		price_label.text = "已装备"
		price_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42, 1.0))
	elif price == 0:
		price_label.text = "免费"
	else:
		price_label.text = "价格 %d" % price
	return {"weapon_id": weapon_id, "card": card, "price_label": price_label}


## 刷新图鉴面板：钱包 + 槽位状态 + 卡片状态
func _refresh_armory() -> void:
	if _armory_root == null:
		return
	_armory_wallet_label.text = "账户金币：%d" % int(GameState.account_gold)

	# 刷新上方 3 槽位
	for i: int in range(_armory_kit_slots.size()):
		var entry: Dictionary = _armory_kit_slots[i]
		var weapon_id: String = GameState.starter_kit_ids[i] if i < GameState.starter_kit_ids.size() else WeaponDB.STARTER_ID
		var weapon: WeaponData = WeaponDB.create(weapon_id)
		if weapon == null:
			weapon = WeaponDB.create(WeaponDB.STARTER_ID)
		entry["weapon_id"] = weapon_id
		entry["icon"].texture = weapon.icon_texture()
		entry["name_label"].text = weapon.display_name
		entry["name_label"].add_theme_color_override("font_color", _rarity_color(int(weapon.rarity)))
		entry["stat_label"].text = "伤害 %d · 耗能 %d" % [int(weapon.damage), int(weapon.energy_cost)]
		# 高亮选中槽位
		if i == _selected_slot:
			entry["bg"].modulate = Color(1.0, 0.92, 0.7, 1.0)
		else:
			entry["bg"].modulate = Color(0.7, 0.7, 0.85, 1.0)

	# 刷新下方卡片价格状态
	for entry: Dictionary in _armory_cards:
		var wid: String = str(entry.get("weapon_id", ""))
		if wid.is_empty():
			continue
		var price_label: Label = entry.get("price_label")
		if price_label == null:
			continue
		var price: int = int(WeaponDB.TABLE[wid].get("price", 0))
		var in_kit: bool = GameState.starter_kit_ids.has(wid)
		if in_kit:
			price_label.text = "已装备"
			price_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42, 1.0))
		elif price == 0:
			price_label.text = "免费"
			price_label.add_theme_color_override("font_color", Color(0.68, 0.86, 1.0, 1.0))
		else:
			price_label.text = "价格 %d" % price
			price_label.add_theme_color_override("font_color", Color(0.68, 0.86, 1.0, 1.0))


static func _rarity_color(rarity: int) -> Color:
	match rarity:
		WeaponData.Rarity.UNCOMMON:
			return Color(0.55, 0.9, 0.58, 1.0)
		WeaponData.Rarity.RARE:
			return Color(0.45, 0.68, 1.0, 1.0)
		WeaponData.Rarity.LEGENDARY:
			return Color(1.0, 0.78, 0.36, 1.0)
	return Color(0.83, 0.86, 0.92, 1.0)


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
		if _floor_select_root.visible:
			_on_floor_select_back()
			get_viewport().set_input_as_handled()
			return
		if _armory_root.visible:
			_on_armory_back()
			get_viewport().set_input_as_handled()
			return
		if _settings_root.visible:
			_close_settings()
			get_viewport().set_input_as_handled()


func _on_start_pressed() -> void:
	AudioMgr.play_sfx("ui_click")
	_menu_root.visible = false
	_floor_select_root.visible = true
	_set_hint("选择已解锁的起始关卡 · Esc 返回")


func _on_floor_select_back() -> void:
	AudioMgr.play_sfx("ui_back", 0.0, -6.0)
	_floor_select_root.visible = false
	_menu_root.visible = true
	_set_hint("Enter 开始 · Esc 退出设置")
	if _start_button != null:
		_start_button.grab_focus()


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


func _on_armory_pressed() -> void:
	AudioMgr.play_sfx("ui_click")
	_selected_slot = -1
	_refresh_armory()
	_menu_root.visible = false
	_armory_root.visible = true
	_set_hint("先点击上方槽位选中，再点击下方武器购买替换 · Esc 返回")


func _on_armory_back() -> void:
	AudioMgr.play_sfx("ui_back", 0.0, -6.0)
	_armory_root.visible = false
	_menu_root.visible = true
	_refresh_continue()
	_set_hint("Enter 开始 · Esc 退出设置")
	if _start_button != null:
		_start_button.grab_focus()


## 点击上方槽位：选中该槽位，高亮显示
func _on_armory_slot_pressed(index: int) -> void:
	AudioMgr.play_sfx("ui_click")
	_selected_slot = index
	_refresh_armory()
	var weapon_id: String = GameState.starter_kit_ids[index] if index < GameState.starter_kit_ids.size() else WeaponDB.STARTER_ID
	var weapon: WeaponData = WeaponDB.create(weapon_id)
	var name: String = weapon.display_name if weapon != null else ""
	_set_hint("已选槽位 %d：%s · 点击下方武器购买替换" % [index + 1, name])


## 点击下方武器卡片：若已选槽位，则购买并替换该槽位
func _on_armory_weapon_pressed(weapon_id: String) -> void:
	if _selected_slot < 0:
		AudioMgr.play_sfx("ui_back", 0.0, -6.0)
		_set_hint("请先点击上方槽位选择要替换的武器")
		return
	var current_id: String = GameState.starter_kit_ids[_selected_slot] if _selected_slot < GameState.starter_kit_ids.size() else ""
	if current_id == weapon_id:
		_set_hint("该槽位已经是这把武器了")
		return
	if GameState.buy_kit_weapon(weapon_id, _selected_slot):
		AudioMgr.play_sfx("ui_click")
		_refresh_armory()
		var weapon: WeaponData = WeaponDB.create(weapon_id)
		var name: String = weapon.display_name if weapon != null else ""
		_set_hint("槽位 %d 已替换为：%s" % [_selected_slot + 1, name])
	else:
		AudioMgr.play_sfx("ui_back", 0.0, -6.0)
		_set_hint("账户金币不足，先打通最后一层攒钱吧")


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
