class_name FxSprite
extends Sprite2D
## FxSprite —— 一次性帧动画精灵（命中火花、爆炸、 dust、刀光等）。
##
## 用 `_process` 自己推帧而不是 AnimationPlayer/Tween：
##   1. 无头测试里逐帧推进可控；
##   2. 播完自动 queue_free，不留孤儿节点。
## 由 `Fx.play()` 创建，一般不直接 new。

var frames: Array[Texture2D] = []
var fps: float = 18.0
var loop: bool = false
var drift: Vector2 = Vector2.ZERO
var spin: float = 0.0
var fade: bool = true

var _elapsed: float = 0.0
var _index: int = 0


func setup(frame_list: Array[Texture2D], frames_per_second: float, loop_anim: bool = false) -> FxSprite:
	frames = frame_list
	fps = maxf(frames_per_second, 1.0)
	loop = loop_anim
	if not frames.is_empty():
		texture = frames[0]
		_index = 0
	centered = true
	return self


func total_duration() -> float:
	if frames.is_empty() or fps <= 0.0:
		return 0.0
	return float(frames.size()) / fps


func _process(delta: float) -> void:
	_elapsed += delta
	if drift != Vector2.ZERO:
		position += drift * delta
	if spin != 0.0:
		rotation += spin * delta

	var duration: float = total_duration()
	if frames.is_empty():
		queue_free()
		return

	var frame_index: int = int(_elapsed * fps)
	if frame_index >= frames.size():
		if loop:
			frame_index = frame_index % frames.size()
			_elapsed = float(frame_index) / fps
		else:
			queue_free()
			return
	if frame_index != _index:
		_index = frame_index
		texture = frames[_index]

	if fade and not loop and duration > 0.0:
		# 后半段开始淡出，命中反馈更干净
		var remain: float = clampf((duration - _elapsed) / maxf(duration * 0.5, 0.001), 0.0, 1.0)
		modulate.a = remain
