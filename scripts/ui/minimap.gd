class_name Minimap
extends Control
## Minimap —— 整层地牢小地图（补齐「HUD 常驻小地图 / Tab 地图」）。
##
## 为什么它重要：地牢的布局（哪间是精英房拿钥匙、哪间是商店、Boss 房在哪个方向）
## 在开局那一刻就已经全部确定了。如果玩家看不到这层图，探索就退化成"推门碰运气"，
## 路线规划、绕路取舍、专程去拿钥匙这些决策全都无从谈起。
##
## 表现规则（对齐同类作品的直觉）：
##   - 已进过的房：亮色 + 真实房型图标；
##   - 与已进过的房相邻（隔着门）的房：半亮 + 真实图标 —— 这是"下推一步"能到的地方；
##   - 更远的房：压暗的未知图标，只保留"这层大概有多大"的轮廓信息，不剧透内容；
##   - 当前房：加一层高亮描边，玩家永远知道自己站在哪；
##   - 玩家点：在当前房内按真实位置偏移，不是永远钉在房间中心。
##
## Tab 键在「角落小图」与「居中大图」之间切换（map 动作早已注册，此前无人使用）。

const G := preload("res://scripts/core/game_const.gd")

const UI_DIR: String = "res://assets/ui/"

## 房型 -> 图标文件名
const TILE_BY_KIND: Dictionary = {
	-1: "minimap_unknown.png",
	0: "minimap_start.png",    # START
	1: "minimap_normal.png",   # COMBAT
	2: "minimap_boss.png",     # ELITE（钥匙房，危险，用 Boss 图标强调）
	3: "minimap_treasure.png", # TREASURE
	4: "minimap_shop.png",     # SHOP
	5: "minimap_boss.png",     # BOSS
}

## 三种显示档位
enum Mode { CORNER, EXPANDED }

const TILE_SOURCE: int = 12      # assets 里图块是 12x12
const PLAYER_SOURCE: int = 6
## 屏幕像素尺寸（本控件挂在未缩放的 _root 上，所以直接用屏幕像素）
const CORNER_SIZE: Vector2 = Vector2(120, 120)
const EXPANDED_SIZE: Vector2 = Vector2(420, 420)
const CORNER_MARGIN: float = 12.0
## 顶部下移量：避开 HUD 右上角的「层数」指示器（它在逻辑画布 y=8~30 处，
## 换算到屏幕是 y=16~60）
const TOP_OFFSET: float = 66.0
const DOOR_COLOR: Color = Color(0.62, 0.70, 0.88, 0.75)
const BG_COLOR: Color = Color(0.05, 0.05, 0.09, 0.78)
const BORDER_COLOR: Color = Color(0.44, 0.50, 0.68, 0.75)
const CURRENT_RING: Color = Color(1.0, 0.95, 0.70, 0.95)
const ELITE_MARK: Color = Color(1.0, 0.72, 0.28, 1.0)

var world: Node = null
var mode: int = Mode.CORNER

var _tiles: Dictionary = {}
var _player_tex: Texture2D = null
var _tick: float = 0.0
## 当前是否为地牢模式（试验场没有布局图，直接隐藏）
var _usable: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_textures()
	visible = false


func setup(owner_world: Node) -> void:
	world = owner_world
	_usable = world != null and is_instance_valid(world) and bool(world.get("dungeon_mode"))
	visible = _usable
	_apply_layout()
	queue_redraw()


## 宿主尺寸变了（窗口缩放 / 分辨率切换）要重新贴边，否则小地图会停在旧位置。
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_layout()


func _ensure_textures() -> void:
	if not _tiles.is_empty():
		return
	for key: Variant in TILE_BY_KIND.keys():
		var file_name: String = str(TILE_BY_KIND[key])
		_tiles[key] = _tex(file_name)
	_player_tex = _tex("minimap_player.png")


static func _tex(file_name: String) -> Texture2D:
	var path: String = UI_DIR + file_name
	return load(path) if ResourceLoader.exists(path) else null


func toggle_mode() -> void:
	mode = Mode.EXPANDED if mode == Mode.CORNER else Mode.CORNER
	_apply_layout()
	queue_redraw()


## 按当前**宿主尺寸**排版。
##
## 注意：本控件挂在 HUD 的 _root 上，而 _root 是未缩放的（1280x720 屏幕坐标）——
## 和 HUD 里那个 640x360 再放大 2 倍的逻辑画布不是同一个坐标系。
## 早先版本误用 LOGICAL_SIZE 算位置，结果小地图被摆到了屏幕偏左中部的位置
## （640-96-8=536 直接当成屏幕 x 用），而不是右上角。
## 所以这里一律以宿主控件的实际尺寸为准。
func _apply_layout() -> void:
	var base: Vector2 = CORNER_SIZE if mode == Mode.CORNER else EXPANDED_SIZE
	var host_size: Vector2 = size if get_parent() == null else (get_parent() as Control).size
	if host_size.x <= 0.0 or host_size.y <= 0.0:
		host_size = Vector2(1280, 720)
	if mode == Mode.CORNER:
		# 右上角「层数」指示器正下方
		position = Vector2(host_size.x - base.x - CORNER_MARGIN, TOP_OFFSET)
	else:
		position = (host_size - base) * 0.5
	size = base
	queue_redraw()


## 换算当前档位下的图块边长（图集只有 7x7 的格数上限，按可用空间缩放）
func _tile_size(span: int) -> float:
	var available: float = (size.x - 10.0) / maxf(float(span), 1.0)
	var wanted: float = 34.0 if mode == Mode.EXPANDED else 12.0
	return clampf(minf(available, wanted), 8.0, 40.0)


func _process(delta: float) -> void:
	if not visible:
		return
	# 地图是低频信息，0.1 秒刷新一次足够，省掉每帧重建
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.1
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 1.0)
	if world == null or not is_instance_valid(world):
		return
	var layout: Variant = world.get("layout")
	if layout == null or not is_instance_valid(layout):
		return

	var rooms: Array = layout.rooms
	if rooms.is_empty():
		return
	var current: int = int(world.get("current_room_index"))
	var visited: Dictionary = _visited_set(rooms)
	_reveal_neighbors(rooms, visited)

	# 房间格子的包围盒
	var min_cell: Vector2i = rooms[0]["cell"]
	var max_cell: Vector2i = min_cell
	for entry: Dictionary in rooms:
		var cell: Vector2i = entry["cell"]
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	var span := maxi(max_cell.x - min_cell.x, max_cell.y - min_cell.y) + 1
	var tile: float = _tile_size(span)
	var origin: Vector2 = (size - Vector2(tile, tile) * float(span)) * 0.5
	var cell_origin := Vector2(min_cell.x, min_cell.y)

	_draw_doors(rooms, cell_origin, origin, tile, visited)
	_draw_rooms(rooms, cell_origin, origin, tile, visited, current)
	_draw_player(rooms, current, cell_origin, origin, tile)


## 已访问房间下标集合
func _visited_set(rooms: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in rooms:
		if bool(entry.get("visited", false)):
			out[int(entry["index"])] = true
	return out


## 把「与已访问房相邻」的房也标出来：玩家推门一步就能到，值得提前看见
func _reveal_neighbors(rooms: Array, visited: Dictionary) -> void:
	for index: Variant in visited.keys():
		for neighbor: Variant in (rooms[int(index)] as Dictionary).get("neighbors", []):
			visited[int(neighbor)] = true


func _cell_pos(cell: Vector2i, cell_origin: Vector2, origin: Vector2, tile: float) -> Vector2:
	return origin + (Vector2(cell) - cell_origin) * tile


## 门：在相邻房中心之间画一小段连接线，让图读起来是"路网"而不是散点
func _draw_doors(rooms: Array, cell_origin: Vector2, origin: Vector2, tile: float,
		visited: Dictionary) -> void:
	var half: float = tile * 0.5
	for entry: Dictionary in rooms:
		var index: int = int(entry["index"])
		if not visited.has(index):
			continue
		var center: Vector2 = _cell_pos(entry["cell"], cell_origin, origin, tile) + Vector2(half, half)
		for neighbor: Variant in (entry.get("neighbors", []) as Array):
			var other: int = int(neighbor)
			if other <= index or not visited.has(other):
				continue
			var other_cell: Vector2i = (rooms[other] as Dictionary)["cell"]
			var target: Vector2 = _cell_pos(other_cell, cell_origin, origin, tile) + Vector2(half, half)
			draw_line(center, target, DOOR_COLOR, maxf(tile * 0.12, 1.0))


func _draw_rooms(rooms: Array, cell_origin: Vector2, origin: Vector2, tile: float,
		visited: Dictionary, current: int) -> void:
	for entry: Dictionary in rooms:
		var index: int = int(entry["index"])
		var known: bool = visited.has(index)
		var kind: int = int(entry["kind"])
		var tile_key: int = kind if known else -1
		var tex: Texture2D = _tiles.get(tile_key, null) as Texture2D
		var pos: Vector2 = _cell_pos(entry["cell"], cell_origin, origin, tile)
		var rect := Rect2(pos, Vector2(tile, tile))
		var tint: Color = Color(1, 1, 1, 1.0) if known else Color(0.45, 0.45, 0.55, 0.55)
		if tex != null:
			draw_texture_rect(tex, rect, false, tint)
		else:
			draw_rect(rect, Color(0.3, 0.32, 0.42, 0.7 * (1.0 if known else 0.5)))
		# 精英房 = 钥匙房，右上角加一枚橙色角标，提示"下一把钥匙在这"
		if known and kind == G.RoomKind.ELITE:
			var m: float = maxf(tile * 0.26, 2.0)
			draw_rect(Rect2(pos + Vector2(tile - m, 0.0), Vector2(m, m)), ELITE_MARK)
		# 当前房描边
		if index == current:
			draw_rect(rect.grow(-0.5), CURRENT_RING, false, maxf(tile * 0.08, 1.0))


## 玩家点：在当前房内按真实位置偏移绘制
func _draw_player(rooms: Array, current: int, cell_origin: Vector2, origin: Vector2,
		tile: float) -> void:
	if current < 0 or current >= rooms.size():
		return
	var player: Node2D = world.get("player") as Node2D
	if player == null or not is_instance_valid(player):
		return
	# 房间总是建在原点（见 GameWorld._enter_room），所以玩家坐标就是房内相对坐标
	var room_size: Vector2i = (rooms[current] as Dictionary).get("size", Vector2i.ONE)
	var extent: Vector2 = Vector2(room_size) * float(G.TILE_SIZE)
	if extent.x <= 0.0 or extent.y <= 0.0:
		return
	var ratio: Vector2 = player.global_position / extent
	ratio = Vector2(clampf(ratio.x, 0.0, 1.0), clampf(ratio.y, 0.0, 1.0))
	var base: Vector2 = _cell_pos((rooms[current] as Dictionary)["cell"], cell_origin, origin, tile)
	var dot_center: Vector2 = base + ratio * tile
	var dot: float = maxf(tile * 0.42, 3.0)
	var rect := Rect2(dot_center - Vector2(dot, dot) * 0.5, Vector2(dot, dot))
	if _player_tex != null:
		draw_texture_rect(_player_tex, rect, false, Color(1, 1, 1, 1))
	else:
		draw_rect(rect, Color(1, 1, 1, 1))
