class_name DamageNumber
extends Node2D
## DamageNumber —— 命中飘字（M3）+ 拾取文字飘字（M6）。
##
## 伤害飘字由 GameWorld 监听 EventBus.damage_number_requested 统一生成，
## 伤害来源（子弹 / 爆炸 / 近战）只负责发信号，不关心表现层。
## 拾取物（金币 / 血包 / 天赋…）走 setup_text()，复用同一套上浮与淡出，
## 只是把数字换成带颜色的短文字，保证画面风格一致。
## 用 _process 自己推进上浮与淡出，播完 queue_free。

const FONT: FontFile = preload("res://assets/fonts/pixel_ui.ttf")

const LIFE: float = 0.72
const RISE_SPEED: float = 40.0
const DRAG: float = 3.2

const COLOR_NORMAL: Color = Color(0.98, 0.97, 0.9)
const COLOR_CRIT: Color = Color(1.0, 0.74, 0.24)
const COLOR_PLAYER_HURT: Color = Color(1.0, 0.36, 0.34)
const COLOR_HEAL: Color = Color(0.55, 1.0, 0.66)
const COLOR_OUTLINE: Color = Color(0.06, 0.05, 0.1, 0.92)

## 文字飘字：非空时优先显示这段文字（而不是 amount）
const TEXT_BOX_WIDTH: float = 108.0
const NUMBER_BOX_WIDTH: float = 56.0

var amount: float = 0.0
var is_crit: bool = false
var is_player_damage: bool = false
var is_heal: bool = false
var custom_text: String = ""
var custom_color: Color = Color(1, 1, 1, 1)
var has_custom_color: bool = false

var _label: Label
var _time: float = 0.0
var _velocity: Vector2 = Vector2.ZERO


func setup(value: float, crit: bool = false, player_damage: bool = false, heal: bool = false) -> DamageNumber:
	amount = value
	is_crit = crit
	is_player_damage = player_damage
	is_heal = heal
	_build()
	return self


## 自定义文字飘字（拾取物用："+18 生命"、"天赋 · 疾风"）。big=true 时字号放大并带弹跳。
func setup_text(text: String, color: Color = Color(1, 1, 1, 1), big: bool = false) -> DamageNumber:
	custom_text = text
	custom_color = color
	has_custom_color = true
	is_crit = big
	_build()
	return self


func _build() -> void:
	z_index = 70
	_velocity = Vector2(randf_range(-16.0, 16.0), -RISE_SPEED)

	_label = Label.new()
	_label.text = _text()
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", _font_size())
	_label.add_theme_color_override("font_color", _color())
	_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	_label.add_theme_constant_override("outline_size", 3)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var box_width: float = TEXT_BOX_WIDTH if custom_text != "" else NUMBER_BOX_WIDTH
	_label.size = Vector2(box_width, 18)
	_label.position = Vector2(-box_width * 0.5, -14)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	if is_crit:
		scale = Vector2.ONE * 1.35


func _font_size() -> int:
	if is_crit:
		return 13
	return 11 if custom_text != "" else 10


func _text() -> String:
	if custom_text != "":
		return custom_text
	var value: int = int(roundf(amount))
	if is_heal:
		return "+%d" % value
	return "%d!" % value if is_crit else str(value)


func _color() -> Color:
	if has_custom_color:
		return custom_color
	if is_heal:
		return COLOR_HEAL
	if is_player_damage:
		return COLOR_PLAYER_HURT
	if is_crit:
		return COLOR_CRIT
	return COLOR_NORMAL


func _process(delta: float) -> void:
	_time += delta
	_velocity.y += RISE_SPEED * DRAG * delta * 0.55
	position += _velocity * delta

	var progress: float = clampf(_time / LIFE, 0.0, 1.0)
	modulate.a = 1.0 - progress * progress
	if is_crit and progress < 0.25:
		var pop: float = lerpf(1.35, 1.1, progress / 0.25)
		scale = Vector2.ONE * pop
	if progress >= 1.0:
		queue_free()
