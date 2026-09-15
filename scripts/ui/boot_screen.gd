extends Control
## BootScreen —— 工程骨架阶段的占位界面（M8 会被真正的主菜单替换）。
##
## 作用：让工程在只有骨架时也能启动到一个可见、可交互的画面，
## 并把"环境自检结果"直接显示出来，方便确认 Autoload / 输入映射 / 物理层是否正常。


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_background()
	_build_panel()


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.062, 0.098, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var grid := Control.new()
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.draw.connect(_on_grid_draw.bind(grid))
	add_child(grid)


func _on_grid_draw(canvas: Control) -> void:
	var size: Vector2 = canvas.size
	var step: float = 32.0
	var col := Color(0.24, 0.82, 0.79, 0.09)
	var x: float = 0.0
	while x <= size.x:
		canvas.draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
		x += step
	var y: float = 0.0
	while y <= size.y:
		canvas.draw_line(Vector2(0, y), Vector2(size.x, y), col, 1.0)
		y += step


func _build_panel() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	vbox.position = Vector2(size.x * 0.5 - 340.0, size.y * 0.5 - 210.0)
	vbox.size = Vector2(680, 420)
	add_child(vbox)

	var title := Label.new()
	title.text = "晶窟枪魂  ·  Crystal Cavern Gunner"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "工程骨架自检面板（M1）— Godot %s" % str(Engine.get_version_info().get("string", "?"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.63, 0.92, 0.9))
	vbox.add_child(subtitle)

	vbox.add_child(_separator())

	var report := RichTextLabel.new()
	report.bbcode_enabled = true
	report.fit_content = false
	report.scroll_active = true
	report.custom_minimum_size = Vector2(680, 250)
	report.text = _self_check_report()
	vbox.add_child(report)

	var hint := Label.new()
	hint.text = "M8 里程碑将在此处替换为正式主菜单（开始 / 继续 / 设置 / 退出）"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	vbox.add_child(hint)


func _separator() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.24, 0.82, 0.79, 0.35)
	c.custom_minimum_size = Vector2(680, 2)
	return c


func _self_check_report() -> String:
	var lines: Array[String] = []
	lines.append("[b]Autoload[/b]")
	for name: String in ["InputCfg", "EventBus", "SaveMgr", "GameState", "AudioMgr"]:
		var ok: bool = get_node_or_null("/root/" + name) != null
		lines.append("  %s %s" % ["[color=#7CFC9A]OK[/color]" if ok else "[color=#FF6B6B]缺失[/color]", name])

	lines.append("")
	lines.append("[b]输入映射[/b]")
	var missing: Array[String] = []
	for action: String in InputCfg.ALL_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(action)
	if missing.is_empty():
		lines.append("  [color=#7CFC9A]OK[/color] 全部 %d 个动作已注册" % InputCfg.ALL_ACTIONS.size())
	else:
		lines.append("  [color=#FF6B6B]缺失[/color] " + ", ".join(missing))
	for pair: Array in [["移动", "move_up"], ["射击", "shoot"], ["冲刺", "dash"], ["技能", "skill"], ["交互", "interact"], ["炸弹", "throw_bomb"], ["暂停", "pause"]]:
		lines.append("  %s: %s" % [pair[0], InputCfg.action_label(pair[1])])

	lines.append("")
	lines.append("[b]物理层[/b]")
	var G: GDScript = load("res://scripts/core/game_const.gd")
	lines.append("  world=%d player=%d enemy=%d p_bullet=%d e_bullet=%d pickup=%d interact=%d" % [
		G.LAYER_WORLD, G.LAYER_PLAYER, G.LAYER_ENEMY,
		G.LAYER_PLAYER_BULLET, G.LAYER_ENEMY_BULLET, G.LAYER_PICKUP, G.LAYER_INTERACT,
	])

	lines.append("")
	lines.append("[b]存档目录[/b]  " + ProjectSettings.globalize_path("user://"))
	lines.append("[b]视口[/b]  %d x %d" % [get_viewport_rect().size.x, get_viewport_rect().size.y])
	return "\n".join(lines)


func _process(_delta: float) -> void:
	if bool(GameState.settings.get("show_fps", false)):
		queue_redraw()


func _draw() -> void:
	if bool(GameState.settings.get("show_fps", false)):
		draw_string(ThemeDB.fallback_font, Vector2(12, 22), "FPS %d" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 1.0, 0.7))
