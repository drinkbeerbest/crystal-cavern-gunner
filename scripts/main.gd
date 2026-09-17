extends Node
## Main —— 场景路由器（主场景根节点）。
##
## 负责在"主菜单 / 游戏世界 / 结算"之间切换，并统一管理暂停状态。
## 采用脚本化构建界面（不依赖大量 .tscn），好处是无头测试可直接实例化任意界面。
##
## 后续里程碑替换点：
##   MENU_SCRIPT_PATH -> 主菜单（M8）
##   GAME_SCRIPT_PATH -> 游戏世界（M5）

const MENU_SCRIPT_PATH: String = "res://scripts/ui/main_menu.gd"
const GAME_SCRIPT_PATH: String = "res://scripts/game/game_world.gd"
const FALLBACK_SCREEN_PATH: String = "res://scripts/ui/boot_screen.gd"
const RESULT_SCREEN_PATH: String = "res://scripts/ui/result_screen.gd"
const G := preload("res://scripts/core/game_const.gd")

var current_screen: Node = null
var last_run_result: Dictionary = {}
## 调试开关：置 true 时游戏世界退回 M3/M4 的战斗试验场（自动化测试仍走那条路径）
var debug_force_arena: bool = false


func _ready() -> void:
	# 路由自身在暂停时仍要能响应（用于恢复游戏 / 返回主菜单）
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	# 自己接管窗口关闭请求，退出前先清掉静态纹理缓存
	get_tree().set_auto_accept_quit(false)
	EventBus.run_finished.connect(_on_run_finished)
	goto_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


## 统一退出入口：清理静态缓存后再退出。
## 主菜单「退出」按钮与窗口关闭都走这里，避免退出时残留资源报错。
func quit_game() -> void:
	Fx.clear_cache()
	RoomBuilder.clear_cache()
	AudioMgr.shutdown()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_fps"):
		GameState.set_setting("show_fps", not bool(GameState.settings.get("show_fps", false)))


# ==================== 界面切换 ====================

func goto_menu() -> void:
	get_tree().paused = false
	_swap_screen(_instantiate(MENU_SCRIPT_PATH, FALLBACK_SCREEN_PATH))
	AudioMgr.play_bgm("menu")


func start_new_run(seed_value: int = 0, start_floor: int = 1) -> void:
	GameState.new_run(seed_value, start_floor)
	AudioMgr.play_sfx("ui_click")
	_enter_game()


func continue_run() -> bool:
	var data: Dictionary = SaveMgr.load_run()
	if data.is_empty():
		return false
	if not GameState.restore_run(data):
		return false
	AudioMgr.play_sfx("ui_click")
	_enter_game()
	return true


func restart_run() -> void:
	start_new_run(0)


## 游戏结束后进入结算界面
func show_result(victory: bool) -> void:
	get_tree().paused = false
	var screen: Node = _instantiate(RESULT_SCREEN_PATH, FALLBACK_SCREEN_PATH)
	_swap_screen(screen)
	if screen.has_method("setup"):
		screen.setup(last_run_result)
	AudioMgr.play_bgm("victory" if victory else "gameover")


func _enter_game() -> void:
	get_tree().paused = false
	var screen: Node = _instantiate(GAME_SCRIPT_PATH, FALLBACK_SCREEN_PATH)
	if screen is GameWorld:
		# 真机默认走随机地牢；测试/调试可把 debug_force_arena 置 true 回到试验场
		(screen as GameWorld).dungeon_mode = not debug_force_arena
	_swap_screen(screen)
	AudioMgr.play_bgm("dungeon_%d" % clamp(GameState.floor_index, 1, G.TOTAL_FLOORS))


func _swap_screen(screen: Node) -> void:
	if screen == null:
		return
	if current_screen != null:
		current_screen.queue_free()
	current_screen = screen
	# 关键修复：Main 是 ALWAYS，若子界面不显式覆盖会继承 ALWAYS，
	# 导致 get_tree().paused 时游戏世界仍然全速运行（敌人/子弹继续攻击）。
	# 显式设回 PAUSABLE，让世界/敌人/子弹在暂停时冻结；HUD 自身 ALWAYS 保持响应。
	screen.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(screen)


## 按优先级加载界面脚本：目标存在则用目标，否则退回占位界面。
## 用 script.new() 而不是 Node.new()+set_script()，这样脚本继承 Control / Node2D
## 时也能创建出正确类型的实例。
func _instantiate(primary_path: String, fallback_path: String) -> Node:
	var path: String = primary_path if ResourceLoader.exists(primary_path) else fallback_path
	if not ResourceLoader.exists(path):
		push_error("Main: 找不到界面脚本 %s" % path)
		return null
	var script: GDScript = load(path)
	var instance: Variant = script.new()
	if instance is Node:
		return instance
	push_error("Main: %s 的根类型不是 Node" % path)
	return null


func _on_run_finished(victory: bool, floor_reached: int, gold_earned: int) -> void:
	last_run_result = {
		"victory": victory,
		"floor_reached": floor_reached,
		"gold": gold_earned,
		"best_floor": GameState.best_floor,
		"total_runs": GameState.total_runs,
		"account_added": GameState.last_account_added,
		"account_gold": GameState.account_gold,
	}
	show_result(victory)
