extends Node
## SaveMgr —— 存档读写（Autoload）。
##
## 三类存档，全部是 user:// 下的 JSON 文本，方便玩家备份与调试：
##   settings.cfg  -> 画面与音量设置
##   meta.cfg      -> 元进度（最佳层数、总局数、角色、天赋点）
##   run.cfg       -> 一局中途存档，供主菜单"继续"使用
##
## 本脚本不写任何密钥类信息。

const SAVE_DIR: String = "user://"
const SETTINGS_PATH: String = SAVE_DIR + "settings.cfg"
const META_PATH: String = SAVE_DIR + "meta.cfg"
const RUN_PATH: String = SAVE_DIR + "run.cfg"

## 无头自动化测试专用目录。
## 为什么需要：测试会调用 GameState.new_run()，而它内部会 _save_meta() ——
## 也就是说**每跑一次无头测试都会写进玩家真实的存档**。历史上真的发生过：
## 「反复跑测试后，存档里的累计局数变成 5577、出战角色被改成哨戒工程机」，
## 还会让「默认角色」这类断言在换机器后莫名其妙失败。
## 所以无头运行一律落到这个子目录，绝不碰真实存档。
const TEST_DIR: String = SAVE_DIR + "_test/"
const TEST_SETTINGS_PATH: String = TEST_DIR + "settings.cfg"
const TEST_META_PATH: String = TEST_DIR + "meta.cfg"
const TEST_RUN_PATH: String = TEST_DIR + "run.cfg"


## 是否切到测试存档：无头环境（自动化测试）一律隔离
static func _use_test_storage() -> bool:
	return OS.has_feature("headless") or DisplayServer.get_name() == "headless"


func settings_path() -> String:
	return TEST_SETTINGS_PATH if _use_test_storage() else SETTINGS_PATH


func meta_path() -> String:
	return TEST_META_PATH if _use_test_storage() else META_PATH


func run_path() -> String:
	return TEST_RUN_PATH if _use_test_storage() else RUN_PATH


func _ready() -> void:
	# 确保目录存在（user:// 一般已存在，这里做防御）
	for path: String in [settings_path(), meta_path(), run_path()]:
		var global_dir: String = ProjectSettings.globalize_path(path.get_base_dir())
		if not DirAccess.dir_exists_absolute(global_dir):
			DirAccess.make_dir_recursive_absolute(global_dir)


# ==================== 通用读写 ====================

func _write_json(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveMgr: 无法写入 %s (err=%d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	if text.strip_edges().is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("SaveMgr: %s 解析失败，已忽略" % path)
	return {}


# ==================== 设置 ====================

func save_settings(data: Dictionary) -> bool:
	return _write_json(settings_path(), data)


func load_settings() -> Dictionary:
	return _read_json(settings_path())


# ==================== 元进度 ====================
func save_meta(data: Dictionary) -> bool:
	return _write_json(meta_path(), data)


func load_meta() -> Dictionary:
	return _read_json(meta_path())


# ==================== 一局存档 ====================
func save_run(data: Dictionary) -> bool:
	data["saved_at"] = int(Time.get_unix_time_from_system())
	return _write_json(run_path(), data)


func load_run() -> Dictionary:
	return _read_json(run_path())


func has_run() -> bool:
	var data: Dictionary = load_run()
	return not data.is_empty() and bool(data.get("run_active", false))


func clear_run() -> void:
	var path: String = run_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 清空所有存档（设置里的"清除存档"）
func wipe_all() -> void:
	for p: String in [settings_path(), meta_path(), run_path()]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
