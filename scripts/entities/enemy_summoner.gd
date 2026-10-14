class_name EnemySummoner
extends Enemy
## EnemySummoner —— 母巢，**召唤**型远程（M9 新增原型）。
##
## 它自己几乎没有攻击力，威胁来自「源源不断的小怪」。
## 玩家面对它要做的是一个真正的战术选择：
##   追进它的召唤圈里清小怪（但会被小怪夹击）
##   还是冒着弹幕直扑本体（但要吃掉好几波召唤）
##
## 平衡设计：召唤物是**有寿命的**（`summon_life`，到点自毁），
## 所以「放着不管」不是一个稳定解——你迟早要处理它。
## 另外召唤物被清空后，母巢会进入一段**禁召期**（和 Boss 同一个思路）：
## 给玩家一个「刚清完，喘口气」的真实窗口，而不是无解的无限刷。

## 召唤物寿命结束后的提示（便于测试与 HUD 提示）
const SUMMON_LIFETIME_FADE: float = 0.6

var summon_cooldown_timer: float = 0.0
## 小怪被清空后的禁召倒计时
var summon_lockout: float = 0.0
var _had_summons: bool = false

# 观测（测试用）
var summons_done: int = 0
var summons_blocked: int = 0
var _minions: Array = []


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if dead:
		return
	summon_cooldown_timer = maxf(summon_cooldown_timer - delta, 0.0)
	if summon_lockout > 0.0:
		summon_lockout = maxf(summon_lockout - delta, 0.0)
	_track_summons()


func _think(_delta: float) -> void:
	_refresh_target()
	if target == null or not is_instance_valid(target) or _target_is_dead():
		super._think(_delta)
		return

	var to_target: Vector2 = target.global_position - global_position
	var distance: float = to_target.length()
	if distance > 0.01:
		facing = to_target.normalized()

	# 保持中距离：太近就跑，太远就靠过去
	if distance < data.keep_distance_min:
		move_velocity = -facing * data.move_speed
	elif distance > data.preferred_range:
		move_velocity = facing * data.move_speed
	else:
		move_velocity = Vector2.ZERO
	set_state(State.CHASE)

	# 条件满足就召唤；不满足时继续走位，玩家永远拿不到一个"站着不动硬吃"的靶子
	if summon_cooldown_timer <= 0.0 and summon_lockout <= 0.0 and _minions_alive() < data.summon_cap:
		_do_summon()


func _do_summon() -> void:
	if world_node == null or not is_instance_valid(world_node):
		return
	var alive: int = _minions_alive()
	if alive >= data.summon_cap:
		summons_blocked += 1
		summon_cooldown_timer = data.summon_cooldown
		return
	var to_spawn: int = mini(data.summon_count, data.summon_cap - alive)
	for i: int in range(to_spawn):
		var minion_id: String = str((data.summon_ids as Array)[i % maxi(data.summon_ids.size(), 1)]) \
				if not data.summon_ids.is_empty() else "husk"
		# 召唤点围着自己散开，不要叠在一起
		var angle: float = TAU * float(i) / float(maxi(to_spawn, 1))
		var at: Vector2 = global_position + Vector2.from_angle(angle) * data.summon_ring
		var minion: Enemy = world_node.spawn_enemy(minion_id, at)
		if minion == null:
			continue
		# 召唤物有寿命：放着不管不是稳定解
		minion.life_timer = maxf(data.summon_life, 0.5)
		minion.set_target(target)
		_minions.append(minion)
	summons_done += 1
	summon_cooldown_timer = data.summon_cooldown
	AudioMgr.play_sfx(data.sfx_shoot, 0.0, -8.0)
	Fx.play(_fx_host(), "ring", global_position, {
		"fps": 14.0, "scale": data.summon_ring / 34.0, "z_index": 6,
		"tint": Color(0.65, 1.0, 0.7, 0.8),
	})


## 召唤物从有到无：开启禁召期（与 Boss 同样的思路）
func _track_summons() -> void:
	if _minions.is_empty():
		return
	var alive: int = _minions_alive()
	if _had_summons and alive == 0:
		_had_summons = false
		_minions.clear()
		summon_lockout = maxf(data.summon_clear_delay, 0.0)
	elif alive > 0:
		_had_summons = true


func _minions_alive() -> int:
	var count: int = 0
	for entry: Variant in _minions:
		if is_instance_valid(entry) and (entry as Enemy) is Enemy and not (entry as Enemy).dead:
			count += 1
	return count


func minions_alive() -> int:
	return _minions_alive()


func summon_locked() -> bool:
	return summon_lockout > 0.0


## 死亡时带走召唤物（避免留下孤儿）
func die() -> void:
	if dead:
		return
	for entry: Variant in _minions:
		if is_instance_valid(entry) and (entry as Enemy) is Enemy and not (entry as Enemy).dead:
			(entry as Enemy).die()
	_minions.clear()
	super.die()
