extends TestSuite
## test_bullet_tunneling —— 子弹穿透回归套件。
##
## 背景：玩家子弹每帧用 intersect_ray 做一次射线检测。当
##   1) 单帧位移超过小怪碰撞体直径（低帧率 / 高速弹），或
##   2) 弹道起点落入敌人碰撞体内部（旧版 hit_from_inside=false 直接忽略该碰撞体），
## 子弹会"穿过"小怪不造成伤害；而 Boss 碰撞体大（radius 16~17，直径 32~34px）
## 很难被单帧跳变跳过，所以几乎不受影响。
##
## 修复：bullet.gd 的 _scan() 改为按 8px 步长分段射线 + 全程 hit_from_inside=true。
## 本套件用四类关键场景（高速贴线 / 起点在兜体内 / 高速打 Boss / 标准弹速远距离贴线）
## 约束修复后的行为：都必须命中。
##
## 说明：敌人不 activate()，保持 DORMANT（原地不动），避免移动干扰命中判定。

func suite_name() -> String:
	return "子弹隧穿回归"


func run(t: Node) -> void:
	await _test_high_speed_grazing(t)
	await _test_spawn_inside_collider(t)
	await _test_fast_bullet_on_boss(t)
	await _test_normal_speed_long_range(t)


## 高速 + 贴线：单帧位移（2000px/s -> 33px）远超 husk 碰撞直径（14px），
## 且弹道在碰撞圆切线上方 1px 处经过 —— 旧版单条射线在此类路径上极易整段错过。
func _test_high_speed_grazing(t: Node) -> void:
	var host := Node2D.new()
	t.add_child(host)
	var enemy: Enemy = EnemyDB.create("husk")
	host.add_child(enemy)
	enemy.global_position = Vector2(600, 6.0)
	var bullet: Bullet = _spawn_player_bullet(host, Vector2.ZERO, Vector2.RIGHT * 2000.0, 10.0)
	await _wait_for_hit(t, bullet, enemy, "高速贴线子弹命中小怪（分段射线防隧穿）")
	_free_all(host, t)


## 起点在碰撞体内：子弹出生在敌人碰撞圆内部。旧版 hit_from_inside=false 会
## 直接忽略该碰撞体导致漏伤；修复后必须命中。
func _test_spawn_inside_collider(t: Node) -> void:
	var host := Node2D.new()
	t.add_child(host)
	var enemy: Enemy = EnemyDB.create("husk")
	host.add_child(enemy)
	enemy.global_position = Vector2(120, 40)
	var bullet: Bullet = _spawn_player_bullet(host,
			enemy.global_position + Vector2(3, 2), Vector2.RIGHT * 80.0, 10.0)
	await _wait_for_hit(t, bullet, enemy, "起点在敌人碰撞体内也必命中（hit_from_inside）")
	_free_all(host, t)


## 高速打 Boss：Boss 碰撞体大（warden radius 17），修复不得破坏 Boss 受击链路。
func _test_fast_bullet_on_boss(t: Node) -> void:
	var host := Node2D.new()
	t.add_child(host)
	var boss: Enemy = EnemyDB.create("warden")
	host.add_child(boss)
	boss.global_position = Vector2(500, 0)
	var bullet: Bullet = _spawn_player_bullet(host, Vector2.ZERO, Vector2.RIGHT * 2000.0, 10.0)
	await _wait_for_hit(t, bullet, boss, "高速子弹命中大碰撞体 Boss（Boss 逻辑不受影响）")
	_free_all(host, t)


## 标准弹速 430 + 远距离贴线：贴近用户实测场景（半屏外、切着碰撞圆边打）。
func _test_normal_speed_long_range(t: Node) -> void:
	var host := Node2D.new()
	t.add_child(host)
	var enemy: Enemy = EnemyDB.create("husk")
	host.add_child(enemy)
	enemy.global_position = Vector2(560, 6.5)
	var bullet: Bullet = _spawn_player_bullet(host, Vector2.ZERO, Vector2.RIGHT * 430.0, 10.0)
	await _wait_for_hit(t, bullet, enemy, "手枪标准弹速 430 远距离贴线命中")
	_free_all(host, t)


# ==================== 内部 ====================

func _spawn_player_bullet(host: Node2D, pos: Vector2, vel: Vector2, dmg: float) -> Bullet:
	var bullet := Bullet.new()
	bullet.from_player = true
	bullet.damage = dmg
	bullet.fly_velocity = vel
	bullet.life = 4.0
	host.add_child(bullet)
	bullet.global_position = pos
	return bullet


## 等待子弹命中：敌人受击计数 > 0 或子弹消失/超时（240 帧）
func _wait_for_hit(t: Node, bullet: Bullet, enemy: Enemy, message: String) -> void:
	# 给物理空间 2 帧注册两个新碰撞体
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	var frames: int = 0
	while enemy.hit_count == 0 and is_instance_valid(bullet) \
			and not bullet.dead and frames < 240:
		await t.get_tree().physics_frame
		frames += 1
	t.gte(float(enemy.hit_count), 1.0, message)
	if bullet != null and is_instance_valid(bullet) and not bullet.dead:
		bullet.queue_free()


func _free_all(host: Node2D, t: Node) -> void:
	if host != null and is_instance_valid(host):
		host.queue_free()
		await t.get_tree().process_frame