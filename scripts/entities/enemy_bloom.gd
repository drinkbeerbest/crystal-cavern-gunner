class_name EnemyBloom
extends Enemy
## EnemyBloom —— 孢晶囊，自爆型（M4）。
##
## 行为链：左右摇摆着追向玩家 -> 进入 `fuse_trigger_range` 后停下蓄力，
##         贴图切到 `bloom_N_c1/c2/c3` 三档膨胀（配合脉动与越来越急的引信音）
##         -> 蓄力结束爆炸，对范围内玩家**与其它敌人**造成伤害（同族会被连锁引爆）。
## 被击杀时同样引爆，但伤害乘 `death_explosion_ratio`（远程秒掉更安全）。
## 蓄力**不可被击退打断**（覆写 `interrupt()`），只能用距离或掩体应对。

## 移动摆动的频率（弧度/秒）：EnemyData 只暴露幅度 `wobble`
const WOBBLE_FREQUENCY: float = 5.0
## 蓄力贴图档位数（对应 bloom_N_c1 ~ c3）
const MAX_CHARGE_LEVEL: int = 3
## 被同族爆炸点燃后的连锁引信时长：远短于正常蓄力，才能看到"一串炸开"的连锁反应
const CHAIN_FUSE_TIME: float = 0.08

var fusing: bool = false
var fuse_timer: float = 0.0
var charge_level: int = 0
var exploded: bool = false
var chain_count: int = 0

var _wobble_time: float = 0.0


func _think(delta: float) -> void:
	if fusing:
		_tick_fuse(delta)
		return
	_refresh_target()
	if target == null:
		super._think(delta)
		return
	var to_target: Vector2 = target.global_position - global_position
	var distance: float = to_target.length()
	if distance > 0.01:
		facing = to_target.normalized()
	_wobble_time += delta
	var lateral: Vector2 = Vector2(-facing.y, facing.x) * sin(_wobble_time * WOBBLE_FREQUENCY) * data.wobble
	move_velocity = facing * data.move_speed + lateral
	set_state(State.CHASE)
	if distance <= data.fuse_trigger_range:
		_begin_fuse()


func _begin_fuse() -> void:
	fusing = true
	fuse_timer = data.fuse_time
	charge_level = 1
	move_velocity = Vector2.ZERO
	set_state(State.ATTACK)
	AudioMgr.play_sfx(data.sfx_fuse, 0.04, -4.0)
	Fx.play(_fx_host(), "ring", global_position, {
		"fps": 10.0, "scale": 0.85, "z_index": 4, "tint": Color(1.0, 0.55, 0.32, 0.65),
	})
	_apply_charge_frames()


func _tick_fuse(delta: float) -> void:
	move_velocity = Vector2.ZERO
	fuse_timer -= delta
	var progress: float = 1.0 - clampf(fuse_timer / maxf(data.fuse_time, 0.01), 0.0, 1.0)
	var level: int = clampi(1 + int(progress * 3.0), 1, MAX_CHARGE_LEVEL)
	if level != charge_level:
		charge_level = level
		_apply_charge_frames()
		# 引信音一档比一档急、音调也更高，形成听觉倒计时
		AudioMgr.play_sfx(data.sfx_fuse, 0.05 + 0.02 * level, -8.0 + 2.0 * level)
	if _sprite != null:
		var pulse: float = 1.0 + 0.07 * level + 0.03 * sin(progress * 38.0)
		_sprite.scale = Vector2.ONE * pulse
		_sprite.modulate = Color(1.0 + 0.28 * progress, 1.0 - 0.22 * progress,
				1.0 - 0.28 * progress, 1.0)
	if fuse_timer <= 0.0:
		explode(data.explosion_damage)


func _apply_charge_frames() -> void:
	var frames: Array[Texture2D] = data.charge_frames(charge_level)
	if frames.is_empty():
		return
	_frames = frames
	_frame_index = 0
	if _sprite != null:
		_sprite.texture = _frames[0]


## 被同族的爆炸波及 -> 直接点燃引信（连锁反应）。
## 只靠伤害数值不足以引爆：临终引爆的伤害要乘 `death_explosion_ratio`，
## 再加上按距离衰减，往往打不死满血同族，连锁就断了。
## 因此这里显式识别"伤害来源是另一只孢晶囊"，给它一段极短的引信。
func take_hit(amount: float, is_crit: bool, knockback: Vector2, source: int) -> void:
	super.take_hit(amount, is_crit, knockback, source)
	if dead or exploded or fusing:
		return
	var origin: Object = instance_from_id(source) if source != 0 else null
	if origin is EnemyBloom and origin != self:
		_begin_fuse()
		fuse_timer = minf(data.fuse_time, CHAIN_FUSE_TIME)


## 引爆：范围伤害同时作用于玩家与其它敌人（自己除外），同族会被连锁引爆
func explode(damage: float) -> void:
	if exploded:
		return
	exploded = true
	explosions += 1
	attacks_made += 1
	var center: Vector2 = global_position + Vector2(0, -2)
	var radius: float = data.explosion_radius
	AudioMgr.play_sfx("explode_big" if radius >= 60.0 else "explode_small", 0.04)
	Fx.play(_fx_host(), "explode", center, {
		"fps": 22.0, "scale": maxf(radius / 28.0, 0.9), "z_index": 13,
	})
	Fx.play(_fx_host(), "ring", center, {"fps": 16.0, "scale": 1.15, "z_index": 12})
	var damaged: Array = CombatUtil.area_damage(self, center, radius, damage, false,
			data.explosion_knockback, get_instance_id(),
			G.LAYER_PLAYER | G.LAYER_ENEMY, [self])
	var hit_player: bool = false
	for node: Variant in damaged:
		if node is Enemy and node != self:
			# 波及到同族 -> 它们会被自己的临终引爆连锁点燃
			chain_count += 1
		elif node is Node and (node as Node).is_in_group(CombatUtil.GROUP_PLAYER):
			hit_player = true
	if hit_player:
		damage_dealt += damage
	EventBus.explosion_occurred.emit(center, radius)
	EventBus.request_screen_shake.emit(4.2, 0.3)
	# 自然蓄力走完 -> 自尽；若是被击杀时的临终引爆，dead 已为真，不再递归
	if not dead:
		die()


## 被击杀时的临终引爆（基类在结算掉落之前调用）
func _on_before_death() -> void:
	if data.explode_on_death and not exploded:
		explode(data.explosion_damage * data.death_explosion_ratio)


## 蓄力不可打断：只记录一次打断尝试，不进入眩晕、不清空引信
func interrupt() -> void:
	interrupts += 1


## 蓄力期间脚下光晕常亮（基类只给精英做脉动），其余表现交给基类
func _update_animation(delta: float) -> void:
	super._update_animation(delta)
	if fusing and not dead and _glow != null:
		_glow.modulate = Color(1.0, 0.5, 0.3, 0.24 + 0.12 * charge_level)
