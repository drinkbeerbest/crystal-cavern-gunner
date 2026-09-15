class_name RoomFloor
extends Node2D
## RoomFloor —— 房间地板/墙体的单节点绘制层（M3）。
##
## 为什么不用「每个瓦片一个 Sprite2D」：一个 27x17 的房间就是 459 个 CanvasItem，
## 每帧都要参与变换与剔除；这里改成单个 Node2D 用 _draw() 一次性画出全部瓦片，
## 一个房间只占 1 个绘制项，性能与内存都更好，也便于整层重绘。
##
## 用法（见 room_builder.gd）：
##   var floor := RoomFloor.new()
##   floor.setup(cells, Vector2i(w, h), G.TILE_SIZE)
##   host.add_child(floor)

var cells: Array = []          ## 长度 = grid.x * grid.y，元素为 Texture2D 或 null
var grid: Vector2i = Vector2i.ZERO
var tile_size: int = 32
var origin_offset: Vector2 = Vector2.ZERO


func setup(cell_list: Array, grid_size: Vector2i, size: int = 32, offset: Vector2 = Vector2.ZERO) -> RoomFloor:
	cells = cell_list
	grid = grid_size
	tile_size = size
	origin_offset = offset
	return self


func set_cell(x: int, y: int, texture: Texture2D) -> void:
	if x < 0 or y < 0 or x >= grid.x or y >= grid.y:
		return
	cells[y * grid.x + x] = texture
	queue_redraw()


func cell_at(x: int, y: int) -> Texture2D:
	if x < 0 or y < 0 or x >= grid.x or y >= grid.y:
		return null
	return cells[y * grid.x + x]


func _draw() -> void:
	if cells.is_empty() or grid.x <= 0 or grid.y <= 0:
		return
	var size_f: float = float(tile_size)
	for y: int in range(grid.y):
		var row_base: int = y * grid.x
		for x: int in range(grid.x):
			var tex: Texture2D = cells[row_base + x]
			if tex == null:
				continue
			var rect := Rect2(origin_offset + Vector2(float(x) * size_f, float(y) * size_f),
					Vector2(size_f, size_f))
			# 墙面贴图比瓦片高（32x40），底边对齐格子底边，视觉上像立起来的墙
			if tex.get_height() > tile_size:
				rect.position.y -= float(tex.get_height() - tile_size)
				rect.size.y = float(tex.get_height())
			draw_texture_rect(tex, rect, false)
