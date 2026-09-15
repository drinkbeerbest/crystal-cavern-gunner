class_name RoomBuilder
extends RefCounted
## RoomBuilder —— 房间搭建器（M3 起用，M5 的地牢生成会复用它）。
##
## 输入「瓦片尺寸 + 起点 + 随机数发生器 + 选项」，输出一个可直接 add_child 的房间：
##   - 地板层（RoomFloor，单节点绘制，含随机地砖变化）
##   - 墙体层（RoomFloor，画 wall_face / wall_pillar，z_index 高于角色）
##   - 碰撞体（StaticBody2D，四边矩形，层 = world）
##   - 可选障碍物（木箱/石柱：贴图 + 碰撞）
##   - 可站立点列表（用于刷怪 / 掉落 / 出生点）
##
## 约定：房间外圈一整圈瓦片是墙，内部 (w-2) x (h-2) 是可活动区域。

const G := preload("res://scripts/core/game_const.gd")

const TILE_DIR: String = "res://assets/tiles/"
const PROP_DIR: String = "res://assets/props/"

## 地板变化权重（普通地砖为主，少量装饰）
const FLOOR_WEIGHTS: Dictionary = {
	"floor_a_0": 46.0, "floor_a_1": 22.0, "floor_a_2": 14.0,
	"floor_b_0": 9.0, "floor_b_1": 5.0,
	"floor_crack": 2.4, "floor_moss": 1.6,
}

## 墙体变化
const WALL_WEIGHTS: Dictionary = {"wall_face_0": 78.0, "wall_face_1": 22.0}

## 地毯（起始房 / Boss 房中央铺设）
const CARPET_WEIGHTS: Dictionary = {"carpet_0": 70.0, "carpet_1": 30.0}

static var _tex_cache: Dictionary = {}


## 释放静态纹理缓存。退出游戏前调用，
## 否则 Godot 关闭时会报 "resources still in use at exit"。
static func clear_cache() -> void:
	_tex_cache.clear()


## 搭建一个房间。返回字典：
## {floor, walls, body, size, origin, interior_rect, center, walk_points}
static func build(host: Node2D, opts: Dictionary) -> Dictionary:
	var size: Vector2i = opts.get("size", Vector2i(21, 15))
	var origin: Vector2 = opts.get("origin", Vector2.ZERO)
	var rng: RandomNumberGenerator = opts.get("rng", _fallback_rng())
	var with_walls: bool = bool(opts.get("walls", true))
	var carpet_center: bool = bool(opts.get("carpet", false))
	var tile: int = G.TILE_SIZE

	var floor_cells: Array = []
	floor_cells.resize(size.x * size.y)
	var wall_cells: Array = []
	wall_cells.resize(size.x * size.y)

	# 门洞：这些墙格不画墙、不留碰撞，改铺地砖当通道（门贴图由 Door 节点叠在上面）
	var gaps: Dictionary = door_gap_cells(size, opts.get("doors", []))

	for y: int in range(size.y):
		for x: int in range(size.x):
			var index: int = y * size.x + x
			var is_edge: bool = x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1
			if is_edge:
				if gaps.has(Vector2i(x, y)):
					floor_cells[index] = _floor_texture(x, y, size, rng, false)
				elif with_walls:
					wall_cells[index] = _wall_texture(x, y, size, rng)
				continue
			floor_cells[index] = _floor_texture(x, y, size, rng, carpet_center)

	var floor_layer := RoomFloor.new()
	floor_layer.setup(floor_cells, size, tile, origin)
	floor_layer.z_index = -2
	floor_layer.name = "Floor"
	host.add_child(floor_layer)

	var wall_layer := RoomFloor.new()
	wall_layer.setup(wall_cells, size, tile, origin)
	wall_layer.z_index = 4
	wall_layer.name = "Walls"
	host.add_child(wall_layer)

	var interior_rect := Rect2(origin + Vector2(tile, tile), Vector2((size.x - 2) * tile, (size.y - 2) * tile))
	var body: StaticBody2D = _build_wall_body(host, origin, size, tile, with_walls, gaps)

	for obstacle: Variant in opts.get("obstacles", []):
		if obstacle is Dictionary:
			add_obstacle(host, obstacle, rng)

	return {
		"floor": floor_layer,
		"walls": wall_layer,
		"body": body,
		"size": size,
		"origin": origin,
		"interior_rect": interior_rect,
		"center": interior_rect.get_center(),
		"walk_points": walk_points(interior_rect, tile),
		"door_gaps": gaps,
	}


## 房间内可站立点（避开边缘一圈，供刷怪/掉落使用）
static func walk_points(interior_rect: Rect2, tile: int = 0) -> Array:
	var step: int = tile if tile > 0 else G.TILE_SIZE
	var points: Array = []
	var inset: float = float(step) * 0.75
	var rect := Rect2(interior_rect.position + Vector2(inset, inset),
			interior_rect.size - Vector2(inset, inset) * 2.0)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return [interior_rect.get_center()]
	var columns: int = maxi(int(rect.size.x / float(step)), 1)
	var rows: int = maxi(int(rect.size.y / float(step)), 1)
	for y: int in range(rows):
		for x: int in range(columns):
			points.append(rect.position + Vector2((float(x) + 0.5) * float(step), (float(y) + 0.5) * float(step)))
	return points


## 在房间内取一个不贴边的随机点
static func random_interior_point(interior_rect: Rect2, margin: float = 24.0, rng: RandomNumberGenerator = null) -> Vector2:
	var r: RandomNumberGenerator = rng if rng != null else _fallback_rng()
	var rect := Rect2(interior_rect.position + Vector2(margin, margin),
			interior_rect.size - Vector2(margin, margin) * 2.0)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return interior_rect.get_center()
	return Vector2(r.randf_range(rect.position.x, rect.end.x), r.randf_range(rect.position.y, rect.end.y))


## 障碍物：贴图 + 矩形碰撞（木箱、石柱、岩石）
static func add_obstacle(host: Node2D, opts: Dictionary, rng: RandomNumberGenerator = null) -> Node2D:
	var texture_name: String = str(opts.get("texture", "crate"))
	var position: Vector2 = opts.get("position", Vector2.ZERO)
	var size: Vector2 = opts.get("size", Vector2(24, 24))
	var node := Node2D.new()
	node.position = position
	node.name = "Obstacle_%s" % texture_name
	host.add_child(node)

	var tex: Texture2D = texture(PROP_DIR + texture_name + ".png")
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.position = Vector2(0, -size.y * 0.15)
	node.add_child(sprite)

	var body := StaticBody2D.new()
	body.collision_layer = G.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	node.add_child(body)
	return node


## 装饰物（火把 / 火盆 / 水晶）：只有贴图，不带碰撞。
## animated=true 时用 FxSprite 循环播放 frame_0..frame_N。
static func add_decoration(host: Node2D, texture_prefix: String, position: Vector2, frame_count: int = 4, fps: float = 8.0) -> Node2D:
	var dir: String = PROP_DIR
	var frames: Array[Texture2D] = []
	for i: int in range(frame_count):
		var tex: Texture2D = texture(dir + "%s_%d.png" % [texture_prefix, i])
		if tex != null:
			frames.append(tex)
	var node := Node2D.new()
	node.position = position
	node.z_index = 3
	host.add_child(node)
	if frames.is_empty():
		return node
	if frames.size() == 1 or fps <= 0.0:
		var sprite := Sprite2D.new()
		sprite.texture = frames[0]
		node.add_child(sprite)
		return node
	var anim := FxSprite.new()
	anim.setup(frames, fps, true)
	anim.fade = false
	node.add_child(anim)
	return node


# ==================== 内部 ====================

static func _wall_texture(x: int, y: int, size: Vector2i, rng: RandomNumberGenerator) -> Texture2D:
	var is_corner: bool = (x == 0 or x == size.x - 1) and (y == 0 or y == size.y - 1)
	if is_corner:
		var pillar: Texture2D = texture(TILE_DIR + "wall_pillar.png")
		if pillar != null:
			return pillar
	return _weighted_texture(WALL_WEIGHTS, rng)


static func _floor_texture(x: int, y: int, size: Vector2i, rng: RandomNumberGenerator, carpet_center: bool) -> Texture2D:
	if carpet_center:
		var center: Vector2i = size / 2
		var distance: int = absi(x - center.x) + absi(y - center.y)
		if distance <= 3:
			var carpet: Texture2D = _weighted_texture(CARPET_WEIGHTS, rng)
			if carpet != null:
				return carpet
	return _weighted_texture(FLOOR_WEIGHTS, rng)


static func _weighted_texture(weights: Dictionary, rng: RandomNumberGenerator) -> Texture2D:
	var key: Variant = G.weighted_pick(weights, rng)
	if key == null:
		return null
	return texture(TILE_DIR + str(key) + ".png")


static func texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if tex == null:
		push_warning("RoomBuilder: 缺少贴图 %s" % path)
	_tex_cache[path] = tex
	return tex


static func _build_wall_body(host: Node2D, origin: Vector2, size: Vector2i, tile: int, with_walls: bool,
		gaps: Dictionary = {}) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "RoomWalls"
	body.collision_layer = G.LAYER_WORLD
	body.collision_mask = 0
	host.add_child(body)
	if not with_walls:
		return body

	# 上/下边：沿 x 扫描，门洞处断开
	for y: int in [0, size.y - 1]:
		var x: int = 0
		while x < size.x:
			if gaps.has(Vector2i(x, y)):
				x += 1
				continue
			var first: int = x
			while x < size.x and not gaps.has(Vector2i(x, y)):
				x += 1
			_add_wall_rect(body, tile, Vector2i(first, y), x - first, true)
	# 左/右边：沿 y 扫描
	for x: int in [0, size.x - 1]:
		var y: int = 0
		while y < size.y:
			if gaps.has(Vector2i(x, y)):
				y += 1
				continue
			var first: int = y
			while y < size.y and not gaps.has(Vector2i(x, y)):
				y += 1
			_add_wall_rect(body, tile, Vector2i(x, first), y - first, false)
	body.position = origin
	return body


## 一段墙碰撞。from_cell 是起始格，count 是连续格数，horizontal 表示这段墙是横着走的。
static func _add_wall_rect(body: StaticBody2D, tile: int, from_cell: Vector2i, count: int, horizontal: bool) -> void:
	if count <= 0:
		return
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	if horizontal:
		rect.size = Vector2(float(count * tile), float(tile))
		shape_node.position = Vector2((float(from_cell.x) + float(count) * 0.5) * float(tile),
				(float(from_cell.y) + 0.5) * float(tile))
	else:
		rect.size = Vector2(float(tile), float(count * tile))
		shape_node.position = Vector2((float(from_cell.x) + 0.5) * float(tile),
				(float(from_cell.y) + float(count) * 0.5) * float(tile))
	shape_node.shape = rect
	body.add_child(shape_node)


# ==================== 门洞 ====================

## 门洞宽度（瓦片）。门贴图 door_h 是 64x24、door_v 是 24x64，正好两格宽。
const DOOR_GAP_TILES: int = 2

## 方向编号与 DungeonLayout.Dir 一致：0 北 / 1 南 / 2 西 / 3 东
const DIR_NORTH: int = 0
const DIR_SOUTH: int = 1
const DIR_WEST: int = 2
const DIR_EAST: int = 3


## 算出某面墙要留出的门洞格子集合 {Vector2i: true}
static func door_gap_cells(size: Vector2i, doors: Variant) -> Dictionary:
	var gaps: Dictionary = {}
	var cx: int = size.x / 2
	var cy: int = size.y / 2
	var low_x: int = cx - DOOR_GAP_TILES / 2
	var low_y: int = cy - DOOR_GAP_TILES / 2
	for entry: Variant in (doors as Array if doors is Array else []):
		match int(entry):
			DIR_NORTH:
				for i: int in range(DOOR_GAP_TILES):
					gaps[Vector2i(clampi(low_x + i, 1, size.x - 2), 0)] = true
			DIR_SOUTH:
				for i: int in range(DOOR_GAP_TILES):
					gaps[Vector2i(clampi(low_x + i, 1, size.x - 2), size.y - 1)] = true
			DIR_WEST:
				for i: int in range(DOOR_GAP_TILES):
					gaps[Vector2i(0, clampi(low_y + i, 1, size.y - 2))] = true
			DIR_EAST:
				for i: int in range(DOOR_GAP_TILES):
					gaps[Vector2i(size.x - 1, clampi(low_y + i, 1, size.y - 2))] = true
	return gaps


## 门节点该放的位置（门洞正中央，压在墙线上）
static func door_anchor(size: Vector2i, dir: int, origin: Vector2 = Vector2.ZERO) -> Vector2:
	var tile: float = float(G.TILE_SIZE)
	# 与 door_gap_cells 使用同样的整数中心，避免奇数尺寸房间出现半格偏差
	var cx: float = float(int(size.x / 2)) * tile
	var cy: float = float(int(size.y / 2)) * tile
	match dir:
		DIR_NORTH:
			return origin + Vector2(cx, tile * 0.5)
		DIR_SOUTH:
			return origin + Vector2(cx, (float(size.y) - 0.5) * tile)
		DIR_WEST:
			return origin + Vector2(tile * 0.5, cy)
	return origin + Vector2((float(size.x) - 0.5) * tile, cy)


## 门内侧的落脚点：从门往房间里走 inset 瓦片（换房时把玩家放这里，避免立刻又踩回门）
static func door_entry_point(size: Vector2i, dir: int, origin: Vector2 = Vector2.ZERO, inset: float = 1.6) -> Vector2:
	var tile: float = float(G.TILE_SIZE)
	var anchor: Vector2 = door_anchor(size, dir, origin)
	match dir:
		DIR_NORTH:
			return anchor + Vector2(0, inset * tile)
		DIR_SOUTH:
			return anchor - Vector2(0, inset * tile)
		DIR_WEST:
			return anchor + Vector2(inset * tile, 0)
	return anchor - Vector2(inset * tile, 0)


static func _fallback_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng
