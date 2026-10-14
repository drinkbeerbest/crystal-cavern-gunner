class_name Telegraph
extends Node2D
## Telegraph —— Boss 技能地面预警贴花（M9 新增）。
##
## 原先 Boss 预警只有一圈一次性扩散的 ring 特效：它从中心放大后消失，
## 玩家只能靠"圈已经变大了"倒推时间，而且完全看不出**这一招会打到哪里**
## （冲撞是线、扇形是扇、砸地是圆，全长得一样）。
##
## Telegraph 把它换成"贴在地板上、随读条填满"的危险区：
##   - 形状精确对应招式实际判定（圆 / 扇 / 环 / 直线）；
##   - 内部从 0% 填到 100% 的进度条就是剩余时间，填满 = 立刻开火；
##   - 读条最后 25% 会闪烁，给玩家"现在必须动"的最后提醒。
##
## 它挂在世界层的 decal 层（地板之上、角色之下），
## 所以既能看清范围，又不会挡住玩家对自己角色的判断。

enum Shape { CIRCLE, CONE, RING, LINE }

## 读条进入最后这段比例时开始闪烁
const FLASH_RATIO: float = 0.75
## 闪烁频率（Hz）
const FLASH_FPS: float = 9.0

## 区域中心（本地坐标）
var radius: float = 64.0
## 扇形 / 直线的朝向与张角
var facing: Vector2 = Vector2.RIGHT
var half_angle_deg: float = 45.0
## 直线长度与半宽
var length: float = 300.0
var half_width: float = 26.0
## 危险区颜色（按招式类型区分：红=近战压迫、橙=弹幕、紫=螺旋、绿=召唤）
var tint: Color = Color(1.0, 0.35, 0.3, 0.8)
## 总读条时长（秒）
var duration: float = 0.5
## 贴花自身 z_index（在 decal 层上用相对值保证盖住地板、被角色遮住）
var z_offset: int = 0

var _elapsed: float = 0.0
var _shape: int = Shape.CIRCLE
var _finished: bool = false


func _ready() -> void:
	# 不参与 Y 排序：它是地面标记，永远压在所有角色下面
	y_sort_enabled = false
	z_as_relative = true
	z_index = z_offset


## 圆形危险区（砸地 / 落点 AoE）
static func circle(host: Node, at_position: Vector2, circle_radius: float, life: float,
		color: Color) -> Telegraph:
	return _spawn(host, at_position, Shape.CIRCLE, life, color, {"radius": circle_radius})


## 扇形危险区（扇形弹幕：锁定方向的一串弹丸）
static func cone(host: Node, at_position: Vector2, direction: Vector2, circle_radius: float,
		angle_deg: float, life: float, color: Color) -> Telegraph:
	return _spawn(host, at_position, Shape.CONE, life, color, {
		"radius": circle_radius, "facing": direction, "half_angle_deg": angle_deg,
	})


## 环状危险区（环形弹幕：Boss 自身周围一圈，玩家要往里或往外躲）
static func ring(host: Node, at_position: Vector2, circle_radius: float, life: float,
		color: Color) -> Telegraph:
	return _spawn(host, at_position, Shape.RING, life, color, {"radius": circle_radius})


## 直线危险区（冲撞：一条从 Boss 延伸到远处的走廊）
static func line(host: Node, at_position: Vector2, direction: Vector2, line_length: float,
		line_width: float, life: float, color: Color) -> Telegraph:
	return _spawn(host, at_position, Shape.LINE, life, color, {
		"facing": direction, "length": line_length, "half_width": line_width,
	})


static func _spawn(host: Node, at_position: Vector2, shape: int, life: float, color: Color,
		props: Dictionary) -> Telegraph:
	var parent: Node2D = host as Node2D
	if parent == null and host != null and is_instance_valid(host):
		parent = host.get_parent() as Node2D
	if parent == null:
		return null
	var node := Telegraph.new()
	node.position = at_position
	node._shape = shape
	node.duration = maxf(life, 0.05)
	node.tint = color
	for key: String in props.keys():
		node.set(key, props[key])
	parent.add_child(node)
	return node


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		_finish()
		return
	queue_redraw()


## 读条进度 0~1
func progress() -> float:
	return clampf(_elapsed / maxf(duration, 0.001), 0.0, 1.0)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	queue_free()


func _draw() -> void:
	var ratio: float = progress()
	# 最后阶段闪烁：让"已经要打了"这件事无法被忽略
	var flash: bool = ratio >= FLASH_RATIO and fmod(_elapsed * FLASH_FPS, 2.0) < 1.0
	var alpha: float = tint.a * (0.45 + 0.55 * ratio)
	var edge: Color = Color(tint.r, tint.g, tint.b, minf(alpha + 0.35, 0.95))
	# 1) 危险区底色：始终画满——玩家看到的浅色区域就是**真正会挨打**的范围，
	#    不会因为读条推进而"越读越小"造成误判。
	_fill_shape(Color(tint.r, tint.g, tint.b, alpha * 0.30))
	# 2) 进度：从中心向外／沿走廊向外推进的亮色，代表"还剩多久"
	_fill_shape(Color(tint.r, tint.g, tint.b, alpha * 0.38), ratio)
	# 3) 边界：始终是完整范围，闪烁提醒
	if flash:
		_outline_shape(Color(1, 1, 1, 0.85), 2.5)
		return
	_outline_shape(edge, 1.5)


func _fill_shape(color: Color, ratio: float = 1.0) -> void:
	match _shape:
		Shape.CIRCLE:
			draw_circle(Vector2.ZERO, maxf(radius * ratio, 0.5), color)
		Shape.RING:
			# 环没有"向外"的概念，用描边宽度表达进度即可
			draw_arc(Vector2.ZERO, maxf(radius, 0.5), 0.0, TAU, 48, color, maxf(2.0 + 6.0 * ratio, 2.0))
		Shape.CONE:
			draw_colored_polygon(_cone_points(radius * ratio), color)
		Shape.LINE:
			draw_colored_polygon(_line_points(ratio), color)


func _outline_shape(color: Color, width: float) -> void:
	match _shape:
		Shape.CIRCLE:
			draw_arc(Vector2.ZERO, maxf(radius, 0.5), 0.0, TAU, 48, color, width)
		Shape.RING:
			draw_arc(Vector2.ZERO, maxf(radius, 0.5), 0.0, TAU, 48, color, width)
		Shape.CONE:
			var points: PackedVector2Array = _cone_points(radius)
			points.append(points[0])
			draw_polyline(points, color, width)
		Shape.LINE:
			var line_points: PackedVector2Array = _line_points(1.0)
			line_points.append(line_points[0])
			draw_polyline(line_points, color, width)


func _cone_points(reach: float) -> PackedVector2Array:
	var dir: Vector2 = facing.normalized() if facing.length() > 0.01 else Vector2.RIGHT
	var half: float = deg_to_rad(clampf(half_angle_deg, 1.0, 179.0))
	var points: PackedVector2Array = PackedVector2Array()
	# 扇形的边线数量随张角自适应，弧线才够圆滑
	var steps: int = maxi(int(half * 12.0), 4)
	for i: int in range(steps + 1):
		var angle: float = -half + 2.0 * half * float(i) / float(steps)
		points.append(dir.rotated(angle) * reach)
	points.append(Vector2.ZERO)
	return points


func _line_points(reach_ratio: float) -> PackedVector2Array:
	var dir: Vector2 = facing.normalized() if facing.length() > 0.01 else Vector2.RIGHT
	var side: Vector2 = Vector2(-dir.y, dir.x) * half_width
	var far: Vector2 = dir * maxf(length * reach_ratio, 0.5)
	return PackedVector2Array([-side, far - side, far + side, side])
