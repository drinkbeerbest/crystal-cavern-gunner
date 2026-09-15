class_name Pickup
extends Area2D
## Pickup —— 掉落拾取物（M6）。
##
## 七类拾取物统一由本节点承载：金币 / 能量球 / 血包 / 护盾电池 / 随机武器 / 临时天赋 / 炸弹。
## "具体给什么"在生成时就确定下来（武器实例、天赋条目、金币数量都由世界层用房间 RNG 摇好），
## 拾取时只做结算——这样同一个掉落在不同玩家状态下表现一致，测试也能直接断言。
##
## 三段生命周期：
##   1. 撒开：出生带一点初速，避免一堆金币重叠在同一点；
##   2. 吸附：玩家进入吸附半径后被拉过去（满血的血包 / 满能的能量球 / 满盾的电池不吸附，留在地上）；
##   3. 消失：在场超过 PICKUP_LIFETIME 秒后闪烁并回收。
##
## 结算结果写在 `result` 字典里，同时通过 `collected` 信号交给世界层做统计、飘字与房间状态更新。

const G := preload("res://scripts/core/game_const.gd")
const TALENT_DB := preload("res://scripts/core/talent_db.gd")
const WEAPON_DB := preload("res://scripts/core/weapon_db.gd")

const PICKUP_DIR: String = "res://assets/pickups/"

## 拾取判定保护：掉落常常正好落在玩家脚下，留极短时间让撒开动画启动
const ARM_DELAY: float = 0.12

## 飘字颜色（与素材色调对应）
const COLOR_COIN: Color = Color(1.0, 0.85, 0.36)
const COLOR_ENERGY: Color = Color(0.6, 0.87, 1.0)
const COLOR_HEALTH: Color = Color(0.58, 1.0, 0.66)
const COLOR_SHIELD: Color = Color(0.6, 0.78, 1.0)
const COLOR_WEAPON: Color = Color(1.0, 0.74, 0.36)
const COLOR_TALENT: Color = Color(0.86, 0.68, 1.0)
const COLOR_BOMB: Color = Color(1.0, 0.62, 0.44)

## 收集完成：result 见 _settle()
signal collected(pickup: Pickup, result: Dictionary)
## 到期消失（世界层可用于统计）
signal expired(pickup: Pickup)

var kind: int = G.PickupKind.COIN
## 数量语义：COIN=金币数，ENERGY/HEALTH/SHIELD_CELL=回复量（<=0 用默认值），BOMB=枚数
var amount: float = 1.0
## kind == TALENT 时已摇好的天赋条目（TalentDB.create 的产物）
var talent: Dictionary = {}
## kind == WEAPON 时已摇好的武器实例
var weapon: WeaponData = null
## 归属房间索引（换房时世界层据此清理）
var source_room: int = -1
## 撒开时的活动范围（空 Rect2 表示不限制）
var bounds: Rect2 = Rect2()
## 特效宿主（世界层的 FxLayer）；为空时回退到父节点
var fx_layer: Node2D = null
## 目标玩家（世界层注入）；为空时按组查找
var target_player: Player = null
## 在场剩余时间
var lifetime: float = G.PICKUP_LIFETIME
## 吸附半径（可被天赋/道具改写）
var magnet_radius: float = 74.0

var is_collected: bool = false
var is_expired: bool = false
## 结算结果，测试可断言
var result: Dictionary = {}

var _sprite: Sprite2D = null
var _frames: Array = []
var _frame_index: int = 0
var _frame_timer: float = 0.0
var _frame_fps: float = 0.0
var _time: float = 0.0
var _arm_timer: float = ARM_DELAY
## 浮动相位由坐标派生（不调用全局 randf，保证掉落表现与 RNG 状态无关）
var _phase: float = 0.0
var _scatter_velocity: Vector2 = Vector2.ZERO
var _scatter_time: float = 0.0
var _sprite_offset: Vector2 = Vector2(0, -2)


## 统一构造入口。options 可含 talent / weapon / bounds / lifetime / magnet_radius /
## scatter_direction / scatter_speed / fx_layer / player。
func configure(pickup_kind: int, pickup_amount: float = 1.0, options: Dictionary = {}) -> Pickup:
	kind = pickup_kind
	amount = pickup_amount
	talent = (options.get("talent", {}) as Dictionary).duplicate(true)
	weapon = options.get("weapon", null)
	bounds = options.get("bounds", Rect2())
	fx_layer = options.get("fx_layer", null)
	target_player = options.get("player", null)
	lifetime = float(options.get("lifetime", G.PICKUP_LIFETIME))
	magnet_radius = maxf(float(options.get("magnet_radius", 74.0)), G.PICKUP_MAGNET_MIN)
	source_room = int(options.get("room", -1))
	name = "Pickup_%s" % kind_name(kind)
	collision_layer = 0
	collision_mask = G.MASK_PICKUP
	_build_nodes()
	scatter(options.get("scatter_direction", Vector2.ZERO), float(options.get("scatter_speed", G.PICKUP_SCATTER_SPEED)))
	return self


func _ready() -> void:
	if _sprite == null:
		collision_layer = 0
		collision_mask = G.MASK_PICKUP
		_build_nodes()
	# 掉落常在物理回调链里生成（敌人死亡瞬间），直接改 monitoring 会被引擎拦下
	set_deferred("monitoring", true)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	EventBus.pickup_spawned.emit(self)


func _build_nodes() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "PickupSprite"
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.z_index = 6
		_sprite.position = _sprite_offset
		add_child(_sprite)
	_frames = _load_frames()
	_frame_fps = float(texture_config(kind).get("fps", 0.0))
	if not _frames.is_empty():
		_sprite.texture = _frames[0]
		_phase = fmod(global_position.x * 0.7 + global_position.y * 0.31, TAU)

	if get_node_or_null("PickupCollision") == null:
		var shape := CollisionShape2D.new()
		shape.name = "PickupCollision"
		var circle := CircleShape2D.new()
		circle.radius = 5.0
		shape.shape = circle
		shape.position = _sprite_offset
		add_child(shape)


## 载入贴图帧。多帧素材用 base 的 %d 占位；天赋素材还要拼上天赋 id。
func _load_frames() -> Array:
	var cfg: Dictionary = texture_config(kind)
	var out: Array = []
	var frames: int = int(cfg.get("frames", 1))
	if frames <= 1:
		var single: String = PICKUP_DIR + str(cfg.get("path", "coin_0.png"))
		if ResourceLoader.exists(single):
			out.append(load(single))
		return out
	for i: int in range(frames):
		var path: String
		if bool(cfg.get("needs_id", false)):
			path = PICKUP_DIR + "talent_%s_%d.png" % [_talent_id(), i]
		else:
			path = PICKUP_DIR + (str(cfg.get("base", "coin_%d.png")) % i)
		if ResourceLoader.exists(path):
			out.append(load(path))
	if out.is_empty():
		var fallback: String = PICKUP_DIR + "coin_0.png"
		if ResourceLoader.exists(fallback):
			out.append(load(fallback))
	return out


## 贴图配置：单帧用 path，多帧用 base（含 %d）
static func texture_config(pickup_kind: int) -> Dictionary:
	match pickup_kind:
		G.PickupKind.COIN:
			return {"base": "coin_%d.png", "frames": 4, "fps": 9.0}
		G.PickupKind.ENERGY:
			return {"base": "energy_%d.png", "frames": 4, "fps": 10.0}
		G.PickupKind.HEALTH:
			return {"path": "heart.png", "frames": 1, "fps": 0.0}
		G.PickupKind.SHIELD_CELL:
			return {"path": "armor.png", "frames": 1, "fps": 0.0}
		G.PickupKind.WEAPON:
			return {"path": "weapon_box.png", "frames": 1, "fps": 0.0}
		G.PickupKind.TALENT:
			return {"frames": TALENT_DB.ICON_FRAMES, "fps": 7.0, "needs_id": true}
		G.PickupKind.BOMB:
			return {"base": "bomb_%d.png", "frames": 4, "fps": 8.0}
	return {"path": "coin_0.png", "frames": 1, "fps": 0.0}


## 供世界层在拾取前就换贴图用（例如血包升级成大血包）
func set_amount(value: float) -> void:
	amount = value
	if kind == G.PickupKind.HEALTH and _sprite != null:
		var big_path: String = PICKUP_DIR + ("heart_big.png" if _is_big_heal() else "heart.png")
		if ResourceLoader.exists(big_path):
			_sprite.texture = load(big_path)
			_frames = [load(big_path)]


func scatter(direction: Vector2, speed: float = G.PICKUP_SCATTER_SPEED) -> void:
	if direction.length_squared() < 0.001 or speed <= 0.0:
		return
	_scatter_velocity = direction.normalized() * speed
	_scatter_time = G.PICKUP_SCATTER_TIME


func _physics_process(delta: float) -> void:
	if is_collected or is_expired:
		return
	_time += delta
	if _arm_timer > 0.0:
		_arm_timer = maxf(0.0, _arm_timer - delta)
	_update_animation(delta)
	_update_bob()
	lifetime -= delta
	if lifetime <= 0.0:
		_expire()
		return
	_apply_scatter(delta)
	_apply_magnet(delta)
	if _arm_timer <= 0.0:
		_check_collect()


## 帧动画（单帧素材不动）
func _update_animation(delta: float) -> void:
	if _frames.size() < 2 or _frame_fps <= 0.0 or _sprite == null:
		return
	_frame_timer += delta
	var step: float = 1.0 / _frame_fps
	if _frame_timer < step:
		return
	_frame_timer = fmod(_frame_timer, step)
	_frame_index = (_frame_index + 1) % _frames.size()
	_sprite.texture = _frames[_frame_index]


## 上下浮动 + 到期前闪烁
func _update_bob() -> void:
	if _sprite == null:
		return
	_sprite.position = _sprite_offset + Vector2(0, sin(_time * G.PICKUP_BOB_SPEED + _phase) * G.PICKUP_BOB_HEIGHT)
	if lifetime > G.PICKUP_BLINK_TIME:
		modulate.a = 1.0
		return
	var ratio: float = clampf(lifetime / maxf(G.PICKUP_BLINK_TIME, 0.001), 0.0, 1.0)
	modulate.a = 0.35 + 0.65 * ratio * (0.6 + 0.4 * sin(_time * 14.0))


func _apply_scatter(delta: float) -> void:
	if _scatter_time <= 0.0:
		return
	_scatter_time = maxf(0.0, _scatter_time - delta)
	position += _scatter_velocity * delta
	var decay: float = G.PICKUP_SCATTER_SPEED / maxf(G.PICKUP_SCATTER_TIME, 0.01)
	_scatter_velocity = _scatter_velocity.move_toward(Vector2.ZERO, decay * delta)
	_clamp_to_bounds()
	if _scatter_time <= 0.0:
		_scatter_velocity = Vector2.ZERO


func _apply_magnet(delta: float) -> void:
	var target: Player = _player()
	if target == null or not can_collect():
		return
	var radius: float = maxf(magnet_radius, G.PICKUP_MAGNET_MIN)
	var to_player: Vector2 = target.global_position - global_position
	var distance: float = to_player.length()
	if distance > radius:
		return
	# 越近拉得越猛，形成"吸进来"的手感
	var pull: float = lerpf(0.5, 1.0, 1.0 - clampf(distance / radius, 0.0, 1.0))
	position += to_player.normalized() * G.PICKUP_MAGNET_SPEED * pull * delta


func _clamp_to_bounds() -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	position = Vector2(
		clampf(position.x, bounds.position.x, bounds.end.x),
		clampf(position.y, bounds.position.y, bounds.end.y))


func _check_collect() -> void:
	var target: Player = _player()
	if target == null:
		return
	var reach: float = G.PICKUP_COLLECT_RADIUS + Player.BODY_RADIUS
	if global_position.distance_to(target.global_position) <= reach:
		collect()


func _on_body_entered(body: Node2D) -> void:
	if is_collected or is_expired or _arm_timer > 0.0:
		return
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group(CombatUtil.GROUP_PLAYER):
		return
	collect()


## 当前玩家是否真的需要这个东西（满血不吃血包，避免浪费掉落）
func can_collect() -> bool:
	var target: Player = _player()
	if target == null:
		return false
	match kind:
		G.PickupKind.HEALTH:
			return target.health() < target.max_health() - 0.01
		G.PickupKind.ENERGY:
			return target.energy() < target.max_energy() - 0.01
		G.PickupKind.SHIELD_CELL:
			return target.shield() < target.max_shield() - 0.01
	return true


## 拾取结算。返回 result（同时写进 self.result），不满足条件时返回空字典。
func collect() -> Dictionary:
	if is_collected or is_expired:
		return {}
	var target: Player = _player()
	if target == null or target.dead or not can_collect():
		return {}
	is_collected = true
	result = _settle(target)
	# 可能正处在 body_entered 回调链里，改 monitoring 要推到空闲时段
	set_deferred("monitoring", false)
	visible = false
	if result.has("sfx") and str(result["sfx"]) != "":
		AudioMgr.play_sfx(str(result["sfx"]), 0.0, -7.0)
	var fx_name: String = str(result.get("fx", ""))
	if fx_name != "":
		Fx.play(_fx_host(), fx_name, global_position + Vector2(0, -4), {
			"fps": 18.0, "scale": float(result.get("fx_scale", 0.8)), "z_index": 13,
		})
	collected.emit(self, result)
	EventBus.pickup_collected.emit(kind_name(kind), float(result.get("amount", amount)))
	queue_free()
	return result


## 各类型的实际效果（写入玩家属性 / GameState）
func _settle(target: Player) -> Dictionary:
	match kind:
		G.PickupKind.COIN:
			var gold: int = maxi(1, int(roundf(amount)))
			GameState.add_gold(gold)
			return {
				"kind": kind, "amount": float(gold), "gold": gold,
				"text": "+%d 金" % gold, "color": COLOR_COIN,
				"sfx": "pickup_coin", "fx": "spark", "fx_scale": 0.65,
			}
		G.PickupKind.ENERGY:
			var gained: float = target.add_energy(_value_or(G.PICKUP_ENERGY))
			return {
				"kind": kind, "amount": gained,
				"text": "+%d 能量" % int(roundf(gained)), "color": COLOR_ENERGY,
				"sfx": "pickup_energy", "fx": "", "fx_scale": 0.6,
			}
		G.PickupKind.HEALTH:
			var healed: float = target.heal(_value_or(G.PICKUP_HEAL))
			return {
				"kind": kind, "amount": healed,
				"text": "+%d 生命" % int(roundf(healed)), "color": COLOR_HEALTH,
				"sfx": "pickup_heart", "fx": "heal", "fx_scale": 0.8,
			}
		G.PickupKind.SHIELD_CELL:
			var shielded: float = target.add_shield(_value_or(G.PICKUP_SHIELD))
			return {
				"kind": kind, "amount": shielded,
				"text": "+%d 护盾" % int(roundf(shielded)), "color": COLOR_SHIELD,
				# 没有专门的护盾拾取音效，复用回盾音（见 audio_manager.gd 的 sfx 清单）
				"sfx": "shield_regen", "fx": "shield_pop", "fx_scale": 0.8,
			}
		G.PickupKind.WEAPON:
			var item: WeaponData = weapon if weapon != null else WEAPON_DB.starter()
			if item != null:
				target.add_weapon(item)
			return {
				"kind": kind, "amount": 1.0,
				"text": "获得 %s" % (item.display_name if item != null else "武器"),
				"color": COLOR_WEAPON, "weapon_name": str(item.display_name if item != null else ""),
				"sfx": "pickup_weapon", "fx": "level_ring", "fx_scale": 0.7,
			}
		G.PickupKind.TALENT:
			return _settle_talent(target)
		G.PickupKind.BOMB:
			var added: int = GameState.add_bombs(maxi(1, int(roundf(amount))))
			return {
				"kind": kind, "amount": float(added),
				"text": "炸弹 +%d" % added, "color": COLOR_BOMB,
				"sfx": "pickup_weapon", "fx": "spark", "fx_scale": 0.7,
			}
	return {"kind": kind, "amount": 0.0, "text": "", "color": COLOR_COIN, "sfx": "", "fx": ""}


## 天赋：写入 GameState.talents（属性加成由 GameState._apply_talent_modifiers 生效），
## 并把 instant 的一次性回复也结算掉。
func _settle_talent(target: Player) -> Dictionary:
	var entry: Dictionary = talent.duplicate(true)
	if entry.is_empty() or str(entry.get("id", "")).is_empty():
		var ids: Array = TALENT_DB.ids()
		entry = TALENT_DB.create(str(ids[0])) if not ids.is_empty() else {}
	var tid: String = str(entry.get("id", ""))
	GameState.add_talent(entry)
	var instant: Dictionary = TALENT_DB.instant_effects(entry)
	var healed: float = target.heal(float(instant.get("health", 0.0))) if instant.has("health") else 0.0
	var shielded: float = target.add_shield(float(instant.get("shield", 0.0))) if instant.has("shield") else 0.0
	var energy: float = target.add_energy(float(instant.get("energy", 0.0))) if instant.has("energy") else 0.0
	if instant.has("bombs"):
		GameState.add_bombs(int(instant.get("bombs", 0)))
	var label: String = str(entry.get("display_name", TALENT_DB.display_name(tid)))
	return {
		"kind": kind, "amount": float(entry.get("duration", G.TALENT_DEFAULT_DURATION)),
		"talent_id": tid, "talent_name": label,
		"text": "天赋 · %s" % label, "color": COLOR_TALENT,
		"healed": healed, "shielded": shielded, "energy": energy,
		"sfx": "pickup_talent", "fx": "level_ring", "fx_scale": 0.85,
	}


func _expire() -> void:
	if is_collected or is_expired:
		return
	is_expired = true
	set_deferred("monitoring", false)
	expired.emit(self)
	queue_free()


func _value_or(default_value: float) -> float:
	return amount if amount > 0.0 else default_value


func _is_big_heal() -> bool:
	return amount >= G.PICKUP_HEAL_BIG * 0.9


func _talent_id() -> String:
	var tid: String = str(talent.get("id", ""))
	return tid if tid != "" else "speed"


func _player() -> Player:
	if target_player != null and is_instance_valid(target_player):
		return target_player
	if not is_inside_tree():
		return null
	var node: Node = get_tree().get_first_node_in_group(CombatUtil.GROUP_PLAYER)
	if node is Player:
		target_player = node
	return target_player


func _fx_host() -> Node2D:
	if fx_layer != null and is_instance_valid(fx_layer):
		return fx_layer
	var parent_node: Node = get_parent()
	return parent_node as Node2D


## 类型名（供 EventBus / 测试断言，与 kind_name 一一对应）
static func kind_name(pickup_kind: int) -> String:
	match pickup_kind:
		G.PickupKind.COIN:
			return "coin"
		G.PickupKind.ENERGY:
			return "energy"
		G.PickupKind.HEALTH:
			return "health"
		G.PickupKind.WEAPON:
			return "weapon"
		G.PickupKind.TALENT:
			return "talent"
		G.PickupKind.BOMB:
			return "bomb"
		G.PickupKind.SHIELD_CELL:
			return "shield_cell"
	return "unknown"


## 反查：名字 -> 类型（掉落表 / 测试用字符串时方便）
static func kind_from_name(text: String) -> int:
	match text:
		"coin":
			return G.PickupKind.COIN
		"energy":
			return G.PickupKind.ENERGY
		"health":
			return G.PickupKind.HEALTH
		"weapon":
			return G.PickupKind.WEAPON
		"talent":
			return G.PickupKind.TALENT
		"bomb":
			return G.PickupKind.BOMB
		"shield_cell":
			return G.PickupKind.SHIELD_CELL
	return G.PickupKind.COIN


## 默认回复量（世界层生成掉落时用来填 amount）
static func default_amount(pickup_kind: int) -> float:
	match pickup_kind:
		G.PickupKind.HEALTH:
			return G.PICKUP_HEAL
		G.PickupKind.ENERGY:
			return G.PICKUP_ENERGY
		G.PickupKind.SHIELD_CELL:
			return G.PICKUP_SHIELD
		G.PickupKind.COIN:
			return float(G.COIN_VALUE_MIN)
		G.PickupKind.BOMB:
			return 1.0
	return 1.0
