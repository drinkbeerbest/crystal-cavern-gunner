class_name Door
extends Area2D
## Door —— 房间之间的门（M5）。
##
## 一扇门同时承担三件事：
##   1. 视觉：门洞上叠一张门贴图（横门 door_h_* / 竖门 door_v_*，Boss 门用 boss 贴图）；
##   2. 阻挡：关着的时候用 StaticBody2D 把门洞堵住，清怪后才放行；
##   3. 触发：开着的时候玩家走进去 -> `door_used`，世界层据此换房间；
##      Boss 门没钥匙时玩家撞门 -> `door_blocked`，世界层弹提示。
##
## 门洞的墙体缺口由 RoomBuilder 的 `doors` 选项负责挖，本节点只管"堵与放"。

const G := preload("res://scripts/core/game_const.gd")

const TILE_DIR: String = "res://assets/tiles/"
## 门刚开启/刚进房时的武装延迟：避免玩家还站在门口就被立刻传送回去
const ARM_DELAY: float = 0.28

## 触发区在门洞厚度方向上单侧外扩的像素
const TRIGGER_PADDING: float = 22.0

signal door_used(door: Door)
signal door_blocked(door: Door)

## 本门所在房间 / 通往的房间
var room_index: int = -1
var target_index: int = -1
## 方向（DungeonLayout.Dir：0 北 1 南 2 西 3 东）
var dir: int = 0
var is_boss_door: bool = false
var is_open: bool = false
## 还需要钥匙（Boss 门专用）
var needs_key: bool = false

var _sprite: Sprite2D = null
var _blocker: StaticBody2D = null
var _block_shape: CollisionShape2D = null
var _trigger_shape: CollisionShape2D = null
var _arm_timer: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = G.LAYER_PLAYER
	set_deferred("monitoring", false)
	_build_nodes()
	_refresh()


## 创建后、add_child 前调用
func configure(p_dir: int, p_room_index: int, p_target_index: int, room_size: Vector2i,
		p_is_boss: bool = false, p_open: bool = false) -> void:
	dir = p_dir
	room_index = p_room_index
	target_index = p_target_index
	is_boss_door = p_is_boss
	needs_key = p_is_boss
	is_open = p_open
	position = RoomBuilder.door_anchor(room_size, p_dir)
	name = "Door_%d" % p_dir


func _build_nodes() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "DoorSprite"
	_sprite.z_index = 5
	add_child(_sprite)

	_blocker = StaticBody2D.new()
	_blocker.name = "DoorBlocker"
	_blocker.collision_layer = G.LAYER_WORLD
	_blocker.collision_mask = 0
	_block_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _gap_size()
	_block_shape.shape = rect
	_blocker.add_child(_block_shape)
	add_child(_blocker)

	# Area2D 自己的触发形状：必须挂在门上（不是挂在 blocker 里），否则永远检不到重叠。
	# 比门洞更厚一些，玩家被关着的门挡住时也能触发"锁着"的反馈。
	_trigger_shape = CollisionShape2D.new()
	_trigger_shape.name = "DoorTrigger"
	var trigger_rect := RectangleShape2D.new()
	trigger_rect.size = _trigger_size()
	_trigger_shape.shape = trigger_rect
	add_child(_trigger_shape)

	body_entered.connect(_on_body_entered)


## 门洞的碰撞尺寸（横门堵 2 格宽、1 格厚）
func _gap_size() -> Vector2:
	var tile: float = float(G.TILE_SIZE)
	if is_horizontal():
		return Vector2(tile * float(RoomBuilder.DOOR_GAP_TILES), tile)
	return Vector2(tile, tile * float(RoomBuilder.DOOR_GAP_TILES))


## 触发区尺寸：门洞 + 两侧各外扩 TRIGGER_PADDING，保证贴着门站也算"撞门"
func _trigger_size() -> Vector2:
	var gap: Vector2 = _gap_size()
	if is_horizontal():
		return Vector2(gap.x, gap.y + TRIGGER_PADDING * 2.0)
	return Vector2(gap.x + TRIGGER_PADDING * 2.0, gap.y)


func is_horizontal() -> bool:
	return dir == 0 or dir == 1


func set_open(value: bool) -> void:
	is_open = value
	if value:
		needs_key = false
	_refresh()


func open_with_key() -> void:
	needs_key = false
	set_open(true)


func is_locked() -> bool:
	return needs_key and not is_open


func _refresh() -> void:
	if _sprite == null:
		return
	var axis: String = "h" if is_horizontal() else "v"
	var state: String = "open"
	if not is_open:
		state = "boss" if needs_key else "closed"
	var path: String = TILE_DIR + "door_%s_%s.png" % [axis, state]
	if ResourceLoader.exists(path):
		_sprite.texture = load(path)
	if _block_shape != null:
		_block_shape.disabled = is_open
	# 只有"能通行"或"要钥匙的 Boss 门"才监听玩家：普通关着的门不需要反馈。
	# 用 set_deferred：开门可能发生在 body_entered 回调链里，直接改 monitoring 会被引擎拦下。
	var should_monitor: bool = is_open or needs_key
	set_deferred("monitoring", should_monitor)
	if should_monitor:
		_arm_timer = ARM_DELAY


func _physics_process(delta: float) -> void:
	if _arm_timer > 0.0:
		_arm_timer = maxf(0.0, _arm_timer - delta)
		return
	if not monitoring:
		return
	# 轮询重叠：门在清怪瞬间开启时玩家可能已经站在门洞里，
	# body_entered 不会再发第二次，这里持续检测才不会"卡门口过不去"。
	for body: Node2D in get_overlapping_bodies():
		if body != null and is_instance_valid(body) and body.is_in_group(CombatUtil.GROUP_PLAYER):
			_try_use()
			return


func _try_use() -> void:
	if _arm_timer > 0.0:
		return
	# 两个分支都上冷却：开门要等换房，撞锁门也不该每帧刷一次提示音
	_arm_timer = ARM_DELAY
	if is_open:
		door_used.emit(self)
	elif needs_key:
		door_blocked.emit(self)


func _on_body_entered(body: Node2D) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group(CombatUtil.GROUP_PLAYER):
		return
	_try_use()
