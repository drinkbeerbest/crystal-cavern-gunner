class_name ShopPad
extends Node2D
## ShopPad —— 商店房的售货台（M5 基础版，M6 的掉落/天赋系统会扩充商品）。
##
## 交互方式：E 键买下"当前商品"，光标自动滚到下一件；一次性商品买完即下架。
## 金币结算直接走 GameState.try_spend_gold，买不起时发 `denied` 让世界层提示。

const G := preload("res://scripts/core/game_const.gd")

const PROP_DIR: String = "res://assets/props/"

signal purchased(pad: ShopPad, offer: Dictionary)
signal denied(pad: ShopPad, offer: Dictionary)
## 库存变化（买掉一次性商品后发出），世界层用它把库存写回房间数据
signal stock_changed(pad: ShopPad, stock: Array)

## 商品表：id 决定世界层怎么发货，label 只用于提示文字
const OFFERS: Array = [
	{"id": "heal", "label": "治疗 45 点", "price": 25, "repeat": true},
	{"id": "shield", "label": "护盾充满", "price": 15, "repeat": true},
	{"id": "energy", "label": "能量充满", "price": 12, "repeat": true},
	{"id": "bomb", "label": "炸弹 ×2", "price": 20, "amount": 2, "repeat": true},
	{"id": "weapon", "label": "随机武器", "price": 60, "repeat": false},
	{"id": "talent", "label": "随机天赋", "price": 55, "repeat": false},
]

var stock: Array = []
var cursor: int = 0

var _sprite: Sprite2D = null


func _ready() -> void:
	add_to_group(CombatUtil.GROUP_INTERACTABLE)
	if stock.is_empty():
		stock = OFFERS.duplicate(true)
	_build_nodes()


func _build_nodes() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "PadSprite"
	var path: String = PROP_DIR + "shop_pad.png"
	_sprite.texture = load(path) if ResourceLoader.exists(path) else null
	_sprite.position = Vector2(0, -4)
	_sprite.z_index = 3
	add_child(_sprite)


func current_offer() -> Dictionary:
	if stock.is_empty():
		return {}
	return stock[clampi(cursor, 0, stock.size() - 1)]


func can_interact(_player: Node2D) -> bool:
	return not stock.is_empty()


func interact_prompt() -> String:
	var offer: Dictionary = current_offer()
	if offer.is_empty():
		return "已售罄"
	return "按 E 购买：%s（%d 金）" % [str(offer.get("label", "")), int(offer.get("price", 0))]


func interact(_player: Node2D) -> void:
	var offer: Dictionary = current_offer()
	if offer.is_empty():
		return
	if not GameState.try_spend_gold(int(offer.get("price", 0))):
		AudioMgr.play_sfx("empty", 0.0, -8.0)
		denied.emit(self, offer)
		return
	AudioMgr.play_sfx("buy", 0.0, -6.0)
	if not bool(offer.get("repeat", false)):
		stock.remove_at(clampi(cursor, 0, stock.size() - 1))
	if cursor >= stock.size():
		cursor = 0
	purchased.emit(self, offer)
	stock_changed.emit(self, stock)
