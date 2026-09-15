class_name Altar
extends Node2D
## Altar —— 起始房的祈愿祭坛（M6）。
##
## 交互方式与商店垫一致：E 键买下"当前供品"，光标自动滚到下一件。
## 每座祭坛有使用次数上限（G.ALTAR_USE_LIMIT），用完后熄灭、不再响应交互。
## 供品两种：随机天赋（G.ALTAR_TALENT_PRICE 金）/ 炸弹 ×2（G.ALTAR_BOMB_PRICE 金）。
## 实际发货（写天赋、加炸弹）由世界层在 purchased 回调里完成，与商店共用一套结算路径。
##
## 素材：assets/props/altar_0..3.png（四帧烛光动画，由 tools/build_assets.py 程序化生成）。

const G := preload("res://scripts/core/game_const.gd")

const PROP_DIR: String = "res://assets/props/"
const FRAME_COUNT: int = 4
const FRAME_FPS: float = 6.0

signal purchased(altar: Altar, offer: Dictionary)
signal denied(altar: Altar, offer: Dictionary)
signal exhausted(altar: Altar)

var uses_left: int = G.ALTAR_USE_LIMIT
var cursor: int = 0
## 世界层注入（按房间种子），保证同一层的供品内容可复现
var rng := RandomNumberGenerator.new()

var _sprite: Sprite2D = null
var _frames: Array = []
var _frame_index: int = 0
var _frame_timer: float = 0.0
var _time: float = 0.0


## 供品表：id 决定世界层怎么发货，label 只用于提示文字。
## 用函数而非常量，避免 const 表达式里引用其它脚本常量的解析顺序问题。
static func offers() -> Array:
	return [
		{"id": "talent", "label": "随机天赋", "price": G.ALTAR_TALENT_PRICE, "amount": 1.0},
		{"id": "bomb", "label": "炸弹 ×2", "price": G.ALTAR_BOMB_PRICE, "amount": 2.0},
	]


func _ready() -> void:
	add_to_group(CombatUtil.GROUP_INTERACTABLE)
	_build_nodes()


func _build_nodes() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "AltarSprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = Vector2(0, -10)
	_sprite.z_index = 3
	add_child(_sprite)
	for i: int in range(FRAME_COUNT):
		var path: String = PROP_DIR + "altar_%d.png" % i
		if ResourceLoader.exists(path):
			_frames.append(load(path))
	if not _frames.is_empty():
		_sprite.texture = _frames[0]
	if uses_left <= 0:
		_apply_extinguished_look()


func _process(delta: float) -> void:
	_time += delta
	if _sprite == null:
		return
	if _frames.size() > 1:
		_frame_timer += delta
		var step: float = 1.0 / FRAME_FPS
		if _frame_timer >= step:
			_frame_timer = fmod(_frame_timer, step)
			_frame_index = (_frame_index + 1) % _frames.size()
			_sprite.texture = _frames[_frame_index]
	if uses_left > 0:
		# 烛光呼吸，提示这里可以交互
		_sprite.modulate = Color(1, 1, 1).lerp(Color(1.12, 1.06, 0.94), 0.5 + 0.5 * sin(_time * 2.6))


func current_offer() -> Dictionary:
	var list: Array = offers()
	if list.is_empty():
		return {}
	return list[clampi(cursor, 0, list.size() - 1)]


func can_interact(_player: Node2D) -> bool:
	return uses_left > 0


func interact_prompt() -> String:
	if uses_left <= 0:
		return "祭坛已经熄灭"
	var offer: Dictionary = current_offer()
	return "按 E 祈愿：%s（%d 金） · 还可祈愿 %d 次" % [
		str(offer.get("label", "")), int(offer.get("price", 0)), uses_left]


func interact(_player: Node2D) -> void:
	if uses_left <= 0:
		return
	var offer: Dictionary = current_offer()
	if offer.is_empty():
		return
	if not GameState.try_spend_gold(int(offer.get("price", 0))):
		AudioMgr.play_sfx("empty", 0.0, -8.0)
		denied.emit(self, offer)
		return
	uses_left -= 1
	AudioMgr.play_sfx("altar", 0.0, -6.0)
	Fx.play(get_parent() as Node2D, "level_ring", global_position + Vector2(0, -12),
			{"fps": 14.0, "scale": 0.8, "z_index": 13})
	var list: Array = offers()
	cursor = (cursor + 1) % maxi(list.size(), 1)
	purchased.emit(self, offer)
	if uses_left <= 0:
		_apply_extinguished_look()
		exhausted.emit(self)


## 用完后的熄灭外观：压暗 + 停帧
func _apply_extinguished_look() -> void:
	if _sprite == null:
		return
	_sprite.modulate = Color(0.62, 0.62, 0.7, 1.0)


## 剩余可用次数（测试 / HUD 用）
func remaining_uses() -> int:
	return uses_left
