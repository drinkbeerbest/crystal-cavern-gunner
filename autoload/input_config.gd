extends Node
## InputCfg —— 输入映射注册器（Autoload，必须排在 [autoload] 首位）。
##
## 所有输入动作在运行时通过 InputMap 注册，好处：
##   1. 单一事实来源，避免 project.godot 里冗长且易错的 Object(...) 序列化；
##   2. 设置面板可以直接改写动作绑定（重绑键位）而不需要动配置文件；
##   3. 无头测试里可以断言"动作是否齐全"。
##
## 扩展方式：在 _KEY_BINDINGS / _MOUSE_BINDINGS 里加一行即可，
## 全局任何脚本用 Input.is_action_pressed("xxx") 读取。

## 键位绑定表：动作名 -> 物理按键列表
const _KEY_BINDINGS: Dictionary = {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"dash": [KEY_SHIFT],
	"skill": [KEY_SPACE],
	"interact": [KEY_E],
	"throw_bomb": [KEY_F],
	"pause": [KEY_ESCAPE],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"weapon_3": [KEY_3],
	"weapon_next": [KEY_Q],
	"weapon_prev": [KEY_R],
	"map": [KEY_TAB],
	"confirm": [KEY_ENTER],
	"cancel": [KEY_ESCAPE],
	"debug_fps": [KEY_F3],
}

## 鼠标绑定表：动作名 -> 鼠标键
const _MOUSE_BINDINGS: Dictionary = {
	"shoot": MOUSE_BUTTON_LEFT,
	"aim_secondary": MOUSE_BUTTON_RIGHT,
}

## 需要在项目里存在的全部动作（供测试断言）
const ALL_ACTIONS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right",
	"shoot", "aim_secondary", "dash", "skill", "interact", "throw_bomb", "pause",
	"weapon_1", "weapon_2", "weapon_3", "weapon_next", "weapon_prev",
	"map", "confirm", "cancel", "debug_fps",
]

const ACTION_DEADZONE: float = 0.2


func _ready() -> void:
	register_defaults()


## 注册（或重建）全部默认绑定。设置里"恢复默认键位"也调用它。
func register_defaults() -> void:
	for action: String in _KEY_BINDINGS.keys():
		_ensure_action(action)
		InputMap.action_erase_events(action)
		for keycode: int in _KEY_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)

	for action: String in _MOUSE_BINDINGS.keys():
		_ensure_action(action)
		InputMap.action_erase_events(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = _MOUSE_BINDINGS[action]
		InputMap.action_add_event(action, mb)


## 重新绑定某个动作到单个按键（设置面板用）
func rebind_key(action: String, keycode: int) -> void:
	_ensure_action(action)
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


## 取某动作当前绑定的可读文本，例如 "W / ↑"
func action_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var parts: Array[String] = []
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k: InputEventKey = ev
			var code: int = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			if code != KEY_NONE:
				parts.append(OS.get_keycode_string(code))
		elif ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev
			match mb.button_index:
				MOUSE_BUTTON_LEFT: parts.append("鼠标左键")
				MOUSE_BUTTON_RIGHT: parts.append("鼠标右键")
				MOUSE_BUTTON_MIDDLE: parts.append("鼠标中键")
				MOUSE_BUTTON_WHEEL_UP: parts.append("滚轮上")
				MOUSE_BUTTON_WHEEL_DOWN: parts.append("滚轮下")
				_: parts.append("鼠标键%d" % mb.button_index)
	return " / ".join(parts) if not parts.is_empty() else "?"


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, ACTION_DEADZONE)
