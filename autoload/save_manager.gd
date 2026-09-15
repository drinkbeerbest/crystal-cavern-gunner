extends Node
## SaveMgr —— 存档读写（Autoload）。
##
## 三类存档，全部是 user:// 下的 JSON 文本，方便玩家备份与调试：
##   settings.cfg  -> 画面与音量设置
##   meta.cfg      -> 元进度（最佳层数、总局数）
##   run.cfg       -> 一局中途存档，供主菜单"继续"使用
##
## 本脚本不写任何密钥类信息。

const SAVE_DIR: String = "user://"
const SETTINGS_PATH: String = SAVE_DIR + "settings.cfg"
const META_PATH: String = SAVE_DIR + "meta.cfg"
const RUN_PATH: String = SAVE_DIR + "run.cfg"


func _ready() -> void:
	# 确保目录存在（user:// 一般已存在，这里做防御）
	var global_dir: String = ProjectSettings.globalize_path(SAVE_DIR)
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
	return _write_json(SETTINGS_PATH, data)


func load_settings() -> Dictionary:
	return _read_json(SETTINGS_PATH)


# ==================== 元进度 ====================

func save_meta(data: Dictionary) -> bool:
	return _write_json(META_PATH, data)


func load_meta() -> Dictionary:
	return _read_json(META_PATH)


# ==================== 一局存档 ====================

func save_run(data: Dictionary) -> bool:
	data["saved_at"] = int(Time.get_unix_time_from_system())
	return _write_json(RUN_PATH, data)


func load_run() -> Dictionary:
	return _read_json(RUN_PATH)


func has_run() -> bool:
	var data: Dictionary = load_run()
	return not data.is_empty() and bool(data.get("run_active", false))


func clear_run() -> void:
	if FileAccess.file_exists(RUN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))


## 清空所有存档（设置里的"清除存档"）
func wipe_all() -> void:
	for p: String in [SETTINGS_PATH, META_PATH, RUN_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
