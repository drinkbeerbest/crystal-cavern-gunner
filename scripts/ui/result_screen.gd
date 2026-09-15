class_name ResultScreen
extends Control
## ResultScreen —— 一局结束后的结算界面（胜利 / 失败）。
##
## 由 Main 在 `EventBus.run_finished` 后实例化，并调用 `setup(result)` 注入成绩：
##   { "victory": bool, "floor_reached": int, "gold": int, "best_floor": int, "total_runs": int }
##
## 排版沿用 640x360 逻辑画布 + UI_SCALE 放大，和主菜单 / HUD 一致。

const UI_SCALE: int = 2
const LOGICAL_SIZE: Vector2 = Vector2(640, 360)
const UI_DIR: String = "res://assets/ui/"

const COLOR_VICTORY: Color = Color(1.0, 0.86, 0.42, 1.0)
const COLOR_DEFEAT: Color = Color(0.95, 0.42, 0.42, 1.0)
const COLOR_TEXT: Color = Color(0.88, 0.9, 0.96, 1.0)
const COLOR_DIM: Color = Color(0.58, 0.62, 0.72, 1.0)

var result: Dictionary = {}
var router: Node = null

var _canvas: Control
var _title_label: Label
var _subtitle_label: Label
var _rows_root: Control
var _again_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	router = _find_router()
	_build_background()
	_build_panel()


## Main 会在加入场景树后调用；也允许测试直接调用
func setup(data: Dictionary) -> void:
	result = data if data != null else {}
	_refresh()


func _refresh() -> void:
	if _title_label == null:
		return
	var victory: bool = bool(result.get("victory", false))
	_title_label.text = "通 关 胜 利" if victory else "本 局 失 败"
	_title_label.add_theme_color_override("font_color", COLOR_VICTORY if victory else COLOR_DEFEAT)
	_subtitle_label.text = "你击穿了晶窟最深处的守卫" if victory else "晶窟吞没了探险者，但枪声仍在回响"

	for child: Node in _rows_root.get_children():
		child.queue_free()

	var row: float = 0.0
	row = _stat_row("到达层数", "%d" % int(result.get("floor_reached", 0)), row)
	row = _stat_row("本局金币", "%d" % int(result.get("gold", 0)), row)
	row = _stat_row("最高层数", "%d" % int(result.get("best_floor", GameState.best_floor)), row)
	_stat_row("累计局数", "%d" % int(result.get("total_runs", GameState.total_runs)), row)

	if _again_button != null:
		_again_button.grab_focus()


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.07, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vignette := TextureRect.new()
	vignette.texture = _texture("vignette.png")
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.modulate = Color(1, 1, 1, 0.8)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	_canvas = Control.new()
	_canvas.name = "ResultCanvas"
	_canvas.size = LOGICAL_SIZE
	_canvas.scale = Vector2(UI_SCALE, UI_SCALE)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)


func _build_panel() -> void:
	var panel := _nine_patch("panel_9.png", Vector2(LOGICAL_SIZE.x * 0.5 - 132, 34),
			Vector2(264, 292), 6, _canvas)

	_title_label = _label("本 局 失 败", Vector2(0, 18), Vector2(264, 20), 18, COLOR_DEFEAT,
			panel, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle_label = _label("", Vector2(16, 44), Vector2(232, 24), 9, COLOR_DIM,
			panel, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var divider := ColorRect.new()
	divider.color = Color(0.3, 0.62, 0.66, 0.45)
	divider.position = Vector2(24, 74)
	divider.size = Vector2(216, 1)
	panel.add_child(divider)

	_rows_root = Control.new()
	_rows_root.position = Vector2(24, 86)
	_rows_root.size = Vector2(216, 120)
	_rows_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_rows_root)

	var box := HBoxContainer.new()
	box.position = Vector2((264 - 208) * 0.5, 236)
	box.size = Vector2(208, 26)
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	_again_button = _pixel_button("再来一局")
	_again_button.custom_minimum_size = Vector2(98, 24)
	box.add_child(_again_button)
	_again_button.pressed.connect(_on_again_pressed)

	var menu_button := _pixel_button("返回主菜单")
	menu_button.custom_minimum_size = Vector2(98, 24)
	box.add_child(menu_button)
	menu_button.pressed.connect(_on_menu_pressed)

	_label("Enter 再来一局 · Esc 返回主菜单", Vector2(0, 270), Vector2(264, 10), 8,
			Color(0.44, 0.48, 0.58, 1.0), panel, HORIZONTAL_ALIGNMENT_CENTER)


func _stat_row(title: String, value: String, y: float) -> float:
	_label(title, Vector2(8, y), Vector2(90, 14), 10, COLOR_DIM, _rows_root, HORIZONTAL_ALIGNMENT_LEFT)
	_label(value, Vector2(110, y), Vector2(96, 14), 11, COLOR_TEXT, _rows_root, HORIZONTAL_ALIGNMENT_RIGHT)
	return y + 20.0


func _pixel_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.7, 0.95, 1.0, 1.0))
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var file_name: String = "btn_9_%s.png" % ("normal" if state in ["normal", "focus"] else state)
		button.add_theme_stylebox_override(state, _stylebox(file_name))
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

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("cancel"):
		_on_menu_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm"):
		_on_again_pressed()
		get_viewport().set_input_as_handled()


func _on_again_pressed() -> void:
	AudioMgr.play_sfx("ui_click")
	if router != null and router.has_method("start_new_run"):
		router.call("start_new_run", 0)
	elif get_tree() != null:
		get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	AudioMgr.play_sfx("ui_back")
	if router != null and router.has_method("goto_menu"):
		router.call("goto_menu")


func _find_router() -> Node:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("start_new_run"):
			return node
		node = node.get_parent()
	return null
