from __future__ import annotations

import sys

from evaluate_policy import (
    apply_obs_variant,
    build_policy_info,
    load_policy,
    make_env,
    materialize_spatial_map_variant,
)


variant = sys.argv[1]
seed = int(sys.argv[2])
map_path = materialize_spatial_map_variant("mathematical_logic/task_5", variant, seed=seed)
env = make_env(
    task_id="mathematical_logic/task_5",
    map_path=map_path,
    observation_mode="pixels",
    render_mode=None,
)
policy = load_policy("submissions/robust_final_agent.py")
policy.reset()
raw_obs, raw_info = env.reset(seed=seed)
obs = apply_obs_variant(raw_obs, "default", info=raw_info, env=env)
info = build_policy_info(
    info_mode="safe",
    raw_info=raw_info,
    last_reward=0.0,
    task_id="mathematical_logic/task_5",
)
module = sys.modules[policy.__class__.__module__]

for step in range(1200):
    scene = module.extract_scene(obs, policy.previous_player)
    action = policy.act(obs, info)
    if step % 100 == 0 or (step >= 380 and step % 10 == 0):
        print(
            step,
            env.engine.runtime.room.room_id,
            tuple(round(value, 1) for value in env.engine.runtime.player.position_px),
            scene.player,
            scene.room_hint,
            sorted(scene.monsters),
            sorted(scene.active_monsters),
            sorted(scene.npcs),
            sorted(scene.chests),
            policy._task5_topology_target(scene, 0),
            action,
            flush=True,
        )
    raw_obs, reward, terminated, truncated, raw_info = env.step(action)
    names = [record.get("name") for record in raw_info.get("events", {}).get("records", [])]
    watched = {
        "agent_damaged",
        "shield_block",
        "monster_damaged",
        "monster_killed",
        "chest_opened",
        "room_changed",
        "agent_healed",
        "world_completed",
    }
    if watched.intersection(names):
        print(
            "EVENT",
            step + 1,
            env.engine.runtime.room.room_id,
            tuple(round(value, 1) for value in env.engine.runtime.player.position_px),
            names,
            flush=True,
        )
    obs = apply_obs_variant(raw_obs, "default", info=raw_info, env=env)
    info = build_policy_info(
        info_mode="safe",
        raw_info=raw_info,
        last_reward=float(reward),
        task_id="mathematical_logic/task_5",
    )
    if terminated or truncated:
        print("TERMINAL", step + 1, raw_info.get("terminal_reason"), flush=True)
        break

env.close()
