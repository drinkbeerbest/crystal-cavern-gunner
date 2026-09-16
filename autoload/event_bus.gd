extends Node
## EventBus —— 全局信号总线（Autoload）。
##
## 解耦"发生了一件事"与"谁关心这件事"：战斗、掉落、UI、音频都通过这里通信，
## 避免节点之间互相持有引用。新增全局事件时在这里加一行 signal 即可。

# ---------- 玩家 ----------
signal player_spawned(player: Node)
signal player_stats_changed(stats: Dictionary)
signal player_health_changed(current: float, max_value: float)
signal player_shield_changed(current: float, max_value: float)
signal player_energy_changed(current: float, max_value: float)
signal player_gold_changed(total: int)
signal player_hurt(amount: float, from_shield: bool)
signal player_healed(amount: float)
signal player_died
signal player_dashed
signal player_skill_used(skill_id: String)
signal player_invulnerable_changed(active: bool)

# ---------- 武器 ----------
signal weapon_equipped(weapon_data: Resource, slot_index: int)
signal weapon_list_changed(weapons: Array)
signal weapon_fired(weapon_data: Resource, is_crit: bool)
signal weapon_switched(slot_index: int)
signal weapon_dropped(weapon_data: Resource, at_position: Vector2)
signal ammo_or_energy_lacking

# ---------- 敌人 / 战斗 ----------
signal enemy_spawned(enemy: Node)
signal enemy_hurt(enemy: Node, amount: float, is_crit: bool)
signal enemy_died(enemy: Node, world_position: Vector2)
## 敌人死亡时摇出的掉落表（由世界层生成拾取物或直接结算金币）
signal enemy_dropped(enemy: Node, world_position: Vector2, drops: Array)
signal boss_spawned(boss: Node)
signal boss_phase_changed(boss: Node, phase_index: int)
signal boss_health_changed(current: float, max_value: float)
signal boss_died(boss: Node)
## Boss 房小怪从有到无（召唤物清零），HUD 用它弹出清空提示
signal boss_minions_cleared(boss: Node)
signal explosion_occurred(world_position: Vector2, radius: float)
signal damage_number_requested(world_position: Vector2, amount: float, is_crit: bool, is_player_damage: bool)

# ---------- 地牢 / 房间 ----------
signal floor_started(floor_index: int, floor_seed: int)
signal floor_cleared(floor_index: int)
signal room_entered(room: Node)
signal room_cleared(room: Node)
signal doors_state_changed(room: Node, opened: bool)
signal portal_activated(portal: Node)

# ---------- 掉落 / 天赋 ----------
signal pickup_spawned(pickup: Node)
signal pickup_collected(pickup_type: String, amount: float)
signal talent_gained(talent_id: String, duration: float)
signal talent_expired(talent_id: String)
signal talent_list_changed(talents: Array)

# ---------- 交互 ----------
signal interactable_focused(prompt_text: String)
signal interactable_blurred
signal interact_requested(target: Node)

# ---------- 流程 ----------
signal run_started(run_seed: int)
signal run_finished(victory: bool, floor_reached: int, gold_earned: int)
signal pause_state_changed(paused: bool)
signal request_screen_shake(strength: float, duration: float)
signal toast_message(text: String)
