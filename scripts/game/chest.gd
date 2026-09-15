class_name Chest
extends Node2D
## Chest —— 宝箱房的宝箱（M5）。
##
## 走玩家的交互契约（GROUP_INTERACTABLE + can_interact / interact / interact_prompt），
## 开箱只负责表现与广播，具体奖励由世界层 roll 好塞进 `reward` 再发放，
## 这样 M6 的掉落表接管后，宝箱不用改一行。

const G := preload("res://scripts/core/game_const.gd")

const PROP_DIR: String = "res://assets/props/"

signal opened(chest: Chest)

## 世界层预先 roll 好的奖励（{kind, amount, label}）
var reward: Dictionary = {}
var is_opened: bool = false

var _sprite: Sprite2D = null


func _ready() -> void:
	add_to_group(CombatUtil.GROUP_INTERACTABLE)
	_build_nodes()


func _build_nodes() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "ChestSprite"
	_sprite.texture = _tex("chest_closed")
	_sprite.position = Vector2(0, -6)
	_sprite.z_index = 3
	add_child(_sprite)

	# 箱子本体挡路（比贴图小一圈，免得卡住门口）
	var body := StaticBody2D.new()
	body.collision_layer = G.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18, 12)
	shape.shape = rect
	shape.position = Vector2(0, 2)
	body.add_child(shape)
	add_child(body)


static func _tex(tex_name: String) -> Texture2D:
	var path: String = PROP_DIR + tex_name + ".png"
	return load(path) if ResourceLoader.exists(path) else null


func can_interact(_player: Node2D) -> bool:
	return not is_opened


func interact_prompt() -> String:
	return "按 E 打开宝箱"


func interact(_player: Node2D) -> void:
	if is_opened:
		return
	is_opened = true
	if _sprite != null:
		_sprite.texture = _tex("chest_open")
	AudioMgr.play_sfx("chest_open", 0.0, -5.0)
	Fx.play(get_parent(), "spark", global_position + Vector2(0, -8), {"fps": 20.0, "z_index": 13})
	opened.emit(self)
