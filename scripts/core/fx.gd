class_name Fx
extends RefCounted
## Fx —— 一次性特效工厂（M3）。
##
## 把 assets/fx/ 下的帧序列（hit / spark / dust / smoke / slash / ring / heal /
## shield_pop / level_ring / muzzle / explode）包装成 FxSprite，播完自动释放。
## 全部特效都通过这里生成，方便统一调整帧率、缩放与层级。
##
## 用法：
##   Fx.play(fx_layer, "hit", pos)
##   Fx.play(fx_layer, "explode", pos, {"fps": 24.0, "scale": 1.4, "z_index": 20})
##   Fx.single(fx_layer, "dash_trail", pos, {"life": 0.25, "tint": Color(0.5,0.9,1,0.6)})

const FX_DIR: String = "res://assets/fx/"

## 帧序列 -> 帧数（与 tools/gen_fx.py 产出一致）
const FRAME_COUNTS: Dictionary = {
	"hit": 4, "spark": 4, "dust": 4, "smoke": 4, "slash": 4, "ring": 4,
	"heal": 4, "shield_pop": 4, "level_ring": 6, "muzzle": 3, "explode": 8,
}

## 帧序列 -> 默认帧率
const DEFAULT_FPS: Dictionary = {
	"hit": 24.0, "spark": 26.0, "dust": 14.0, "smoke": 12.0, "slash": 30.0,
	"ring": 18.0, "heal": 14.0, "shield_pop": 20.0, "level_ring": 16.0,
	"muzzle": 32.0, "explode": 22.0,
}

static var _cache: Dictionary = {}


## 取某帧序列的贴图数组（带缓存）
static func frames(anim_name: String) -> Array[Texture2D]:
	if _cache.has(anim_name):
		return _cache[anim_name]
	var list: Array[Texture2D] = []
	var count: int = int(FRAME_COUNTS.get(anim_name, 0))
	for i: int in range(count):
		var path: String = FX_DIR + "%s_%d.png" % [anim_name, i]
		if ResourceLoader.exists(path):
			list.append(load(path))
	_cache[anim_name] = list
	return list


static func texture(tex_name: String) -> Texture2D:
	var key: String = "single:" + tex_name
	if _cache.has(key):
		return _cache[key]
	var path: String = FX_DIR + tex_name + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[key] = tex
	return tex


## 释放静态缓存的贴图。退出游戏前调用，
## 否则 Godot 关闭时会报 "resources still in use at exit"。
static func clear_cache() -> void:
	_cache.clear()


## 播放一套帧动画特效，返回生成的精灵（可用于二次调整）
static func play(host: Node, anim_name: String, pos: Vector2, opts: Dictionary = {}) -> FxSprite:
	var list: Array[Texture2D] = frames(anim_name)
	if list.is_empty():
		return null
	var fps: float = float(opts.get("fps", float(DEFAULT_FPS.get(anim_name, 18.0))))
	return _spawn(host, list, fps, pos, opts)


## 单帧贴图特效（拖影、光晕、预警圈），life 秒后消失
static func single(host: Node, tex_name: String, pos: Vector2, opts: Dictionary = {}) -> FxSprite:
	var tex: Texture2D = texture(tex_name)
	if tex == null:
		return null
	var life: float = maxf(float(opts.get("life", 0.3)), 0.02)
	var merged: Dictionary = opts.duplicate()
	merged["fade"] = bool(opts.get("fade", true))
	return _spawn(host, [tex] as Array[Texture2D], 1.0 / life, pos, merged)


## 直接用贴图数组播放（子弹尾迹等）
static func play_frames(host: Node, list: Array[Texture2D], pos: Vector2, opts: Dictionary = {}) -> FxSprite:
	if list.is_empty():
		return null
	return _spawn(host, list, float(opts.get("fps", 18.0)), pos, opts)


static func _spawn(host: Node, list: Array[Texture2D], fps: float, pos: Vector2, opts: Dictionary) -> FxSprite:
	var parent: Node2D = _resolve_parent(host, opts)
	if parent == null:
		return null
	var sprite := FxSprite.new()
	sprite.setup(list, fps, bool(opts.get("loop", false)))
	sprite.fade = bool(opts.get("fade", true))
	sprite.position = pos + Vector2(opts.get("offset", Vector2.ZERO))
	sprite.rotation = float(opts.get("angle", 0.0))
	sprite.z_index = int(opts.get("z_index", 10))
	sprite.drift = Vector2(opts.get("drift", Vector2.ZERO))
	sprite.spin = float(opts.get("spin", 0.0))
	var tint: Variant = opts.get("tint", null)
	if tint != null:
		sprite.modulate = tint
	var scale_value: Variant = opts.get("scale", 1.0)
	if scale_value is Vector2:
		sprite.scale = scale_value
	else:
		sprite.scale = Vector2.ONE * float(scale_value)
	var jitter: float = float(opts.get("jitter", 0.0))
	if jitter > 0.0:
		sprite.position += Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter))
	parent.add_child(sprite)
	return sprite


## 生成位置随机散落的尘埃/火花（脚步、落地、撞击）
static func scatter(host: Node, anim_name: String, pos: Vector2, count: int, spread: float, opts: Dictionary = {}) -> void:
	for i: int in range(count):
		var angle: float = randf() * TAU
		var distance: float = randf() * spread
		var merged: Dictionary = opts.duplicate()
		merged["jitter"] = 0.0
		play(host, anim_name, pos + Vector2.from_angle(angle) * distance, merged)


static func _resolve_parent(host: Node, opts: Dictionary) -> Node2D:
	var override: Variant = opts.get("layer", null)
	if override is Node2D and is_instance_valid(override):
		return override
	if host is Node2D and is_instance_valid(host):
		return host
	if host != null and is_instance_valid(host) and host.get_tree() != null:
		var scene: Node = host.get_tree().current_scene
		if scene is Node2D:
			return scene
	return null
