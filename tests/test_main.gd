extends Node
## TestMain —— 无头自动化测试入口。
##
## 运行方式（在工程根目录）：
##   "D:/godot/Godot_v4.7.2-stable_win64.exe" --headless --path . res://tests/test_main.tscn
## 退出码：0 = 全部通过，1 = 存在失败。

## 套件用「路径 + 运行时 load」而不是 preload：
## preload 碰到解析错误会让 test_main.gd 自身加载失败，主场景起不来、进程也不退出（表现为一直挂住）；
## 运行时 load 只会拿到 null，可以记成一条失败后继续跑完其余套件，最后正常 quit。
const SUITE_PATHS: Array[String] = [
	"res://tests/suites/test_boot.gd",
	"res://tests/suites/test_assets.gd",
	"res://tests/suites/test_player.gd",
	"res://tests/suites/test_enemy.gd",
	"res://tests/suites/test_dungeon.gd",
	"res://tests/suites/test_dungeon_flow.gd",
	"res://tests/suites/test_pickup.gd",
	"res://tests/suites/test_boss.gd",
]

## 兜底看门狗：某个套件死循环时也要能退出并给出非零码，避免无头运行一直挂着
const WATCHDOG_SECONDS: float = 720.0

var passed: int = 0
var failed: int = 0
var failures: Array[String] = []
var current_suite: String = ""
var _reported: bool = false


func _ready() -> void:
	# 延迟一帧执行：此时 root 已完成子节点装配，测试里可以安全地 add_child。
	_run_all.call_deferred()
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)


func _run_all() -> void:
	print("====================================================")
	print(" 晶窟枪魂 · 无头自动化测试   Godot %s" % str(Engine.get_version_info().get("string", "?")))
	print("====================================================")
	for path: String in SUITE_PATHS:
		# 套件脚本若有解析错误，load() 返回 null（并打印解析错误）；
		# 这里把问题记成一条失败再继续跑后面的套件。
		var suite_script: GDScript = load(path) if ResourceLoader.exists(path) else null
		if suite_script == null or not suite_script.can_instantiate():
			current_suite = path.get_file()
			_record(false, "套件脚本无法加载（存在解析错误？）: %s" % path)
			continue
		var suite: TestSuite = suite_script.new()
		current_suite = suite.suite_name()
		print("\n--- [%s] ---" % current_suite)
		# 套件可能是协程（需要 await 物理帧等子弹飞行/计时器），统一 await 兼容同步与异步。
		await suite.run(self)
	_report_and_quit()


func _on_watchdog() -> void:
	if _reported:
		return
	var stuck_suite: String = current_suite
	current_suite = "watchdog"
	_record(false, "看门狗超时：%.0f 秒内没跑完，疑似死循环（卡在套件：%s）" % [WATCHDOG_SECONDS, stuck_suite])
	_report_and_quit()


# ==================== 断言 API ====================

func check(condition: bool, message: String) -> void:
	_record(condition, message)


func eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		_record(true, message)
	else:
		_record(false, "%s  <期望 %s | 实际 %s>" % [message, str(expected), str(actual)])


func neq(actual: Variant, unexpected: Variant, message: String) -> void:
	if actual != unexpected:
		_record(true, message)
	else:
		_record(false, "%s  <不应等于 %s>" % [message, str(unexpected)])


func near(actual: float, expected: float, epsilon: float, message: String) -> void:
	if absf(actual - expected) <= epsilon:
		_record(true, message)
	else:
		_record(false, "%s  <期望 %f±%f | 实际 %f>" % [message, expected, epsilon, actual])


func not_null(value: Variant, message: String) -> void:
	_record(value != null, message)


func gt(actual: float, threshold: float, message: String) -> void:
	if actual > threshold:
		_record(true, message)
	else:
		_record(false, "%s  <期望 > %f | 实际 %f>" % [message, threshold, actual])


func gte(actual: float, threshold: float, message: String) -> void:
	if actual >= threshold:
		_record(true, message)
	else:
		_record(false, "%s  <期望 >= %f | 实际 %f>" % [message, threshold, actual])


func lte(actual: float, threshold: float, message: String) -> void:
	if actual <= threshold:
		_record(true, message)
	else:
		_record(false, "%s  <期望 <= %f | 实际 %f>" % [message, threshold, actual])


# ==================== 内部 ====================

func _record(ok: bool, message: String) -> void:
	if ok:
		passed += 1
		print("  PASS | %s" % message)
	else:
		failed += 1
		failures.append("[%s] %s" % [current_suite, message])
		print("  FAIL | %s" % message)


func _report_and_quit() -> void:
	if _reported:
		return
	_reported = true
	print("\n====================================================")
	print(" 测试结果: %d 通过 / %d 失败 / 共 %d 项" % [passed, failed, passed + failed])
	if not failures.is_empty():
		print(" 失败明细:")
		for f: String in failures:
			print("   - " + f)
	var orphans: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	print(" 孤儿节点: %d" % orphans)
	print("====================================================")
	# boot 套件会实例化主场景（菜单界面随即播放 BGM）。退出前硬停所有播放器，
	# 否则 AudioServer 仍持有 playback 引用，进程结束会报 "resources still in use"。
	var audio: Node = get_node_or_null("/root/AudioMgr")
	if audio != null and audio.has_method("stop_all"):
		audio.call("stop_all")
	get_tree().quit(0 if failed == 0 else 1)
