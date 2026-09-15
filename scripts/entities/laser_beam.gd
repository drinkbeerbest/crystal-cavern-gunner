class_name LaserBeam
extends Node2D
## LaserBeam —— hitscan 激光束的视觉表现（M3）。
##
## 伤害由 Player 在发射瞬间用 CombatUtil.ray_damage() 结算完毕，
## 本节点只负责把「起点 -> 终点」这段光束画出来并在 life 秒内淡出。
## 贴图使用 assets/fx/beam_seg.png（可平铺的横段），按长度拉伸。

const TEX: Texture2D = preload("res://assets/fx/bullet_laser.png")

var beam_length: float = 160.0
var beam_width: float = 8.0
var beam_color: Color = Color(1.0, 0.35, 0.4)
var life: float = 0.14
## 命中点特效名（空 = 不放）
var end_fx: String = "hit"

var _sprite: Sprite2D
var _glow: Sprite2D
var _time: float = 0.0


func setup(length_px: float, width_px: float, color: Color, life_sec: float) -> LaserBeam:
	beam_length = maxf(length_px, 4.0)
	beam_width = maxf(width_px, 2.0)
	beam_color = color
	life = maxf(life_sec, 0.03)
	return self


func _ready() -> void:
	z_index = 12
	var tex_width: float = float(TEX.get_width())
	var tex_height: float = maxf(float(TEX.get_height()), 1.0)

	_glow = Sprite2D.new()
	_glow.texture = TEX
	_glow.centered = false
	_glow.scale = Vector2(beam_length / tex_width, (beam_width * 2.4) / tex_height)
	_glow.position = Vector2(0, -(beam_width * 1.2))
	_glow.modulate = Color(beam_color.r, beam_color.g, beam_color.b, 0.32)
	add_child(_glow)

	_sprite = Sprite2D.new()
	_sprite.texture = TEX
	_sprite.centered = false
	_sprite.scale = Vector2(beam_length / tex_width, beam_width / tex_height)
	_sprite.position = Vector2(0, -beam_width * 0.5)
	_sprite.modulate = beam_color
	add_child(_sprite)

	if end_fx != "":
		var end_position: Vector2 = Vector2.RIGHT.rotated(rotation) * beam_length
		Fx.play(self, end_fx, end_position, {"fps": 26.0, "z_index": 13})
		Fx.play(self, "spark", end_position, {"fps": 24.0, "scale": 0.8, "z_index": 13})


func _process(delta: float) -> void:
	_time += delta
	var progress: float = clampf(_time / life, 0.0, 1.0)
	modulate.a = 1.0 - progress * progress
	var shrink: float = lerpf(1.0, 0.35, progress)
	_sprite.scale = Vector2(beam_length / float(TEX.get_width()), beam_width * shrink / maxf(float(TEX.get_height()), 1.0))
	if progress >= 1.0:
		queue_free()
