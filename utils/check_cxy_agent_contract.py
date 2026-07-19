from __future__ import annotations

import argparse
import sys

from nesylink.env import make_env
from evaluate_policy import build_safe_info, call_policy, reset_policy, resolve_policies


TASKS = [f"mathematical_logic/task_{index}" for index in range(1, 6)]
DEFAULT_POLICY_SPEC = "submissions/robust_final_agent.py"


def main() -> None:
    parser = argparse.ArgumentParser(description="Check a CXY policy entry contract.")
    parser.add_argument("--policy", default=DEFAULT_POLICY_SPEC)
    args = parser.parse_args()
    policy_spec = args.policy
    bindings = resolve_policies(
        default_policy_spec=None,
        task_policy_specs=[f"{task}={policy_spec}" for task in TASKS],
        task_ids=TASKS,
    )

    policy = bindings[TASKS[0]].policy
    assert all(binding.policy is policy for binding in bindings.values())
    assert all(binding.receives_task_id for binding in bindings.values())

    for task in TASKS:
        binding = bindings[task]

        policy.task_id = "stale_task"
        policy.previous_player = (9, 7)
        policy.move_queue.append(4)
        policy.opened.add(("stale_room", (1, 1)))
        policy.visited_hints.add("stale_room")
        policy.rooms[("stale", "room")] = object()
        policy.current_room = ("stale", "room")
        policy.pending_exit = (("stale", "room"), "east")
        policy.blocked_exits[(("stale", "room"), "east")] = 1
        policy.stationary_steps = 99
        policy.task5_dispatch_decided = True
        policy.task5_use_legacy_topology = True
        policy.task5_use_detour_route = True
        policy.task5_route_entry_rows[(("stale", "room"), (1, 1))] = 4
        policy.cxy_legacy_policy.task_id = "stale_legacy"
        policy.team_snapshot_policy.task_id = "stale_snapshot"

        reset_policy(policy)
        assert policy.task_id == ""
        assert policy.previous_player == (0, 0)
        assert not policy.move_queue
        assert not policy.opened
        assert not policy.visited_hints
        assert not policy.rooms
        assert policy.current_room is None
        assert policy.pending_exit is None
        assert not policy.blocked_exits
        assert policy.stationary_steps == 0
        assert not policy.task5_dispatch_decided
        assert not policy.task5_use_legacy_topology
        assert not policy.task5_use_detour_route
        assert not policy.task5_route_entry_rows
        assert policy.cxy_legacy_policy.task_id == ""
        assert policy.team_snapshot_policy.task_id == ""

        env = make_env(
            task_id=task,
            api="gym",
            render_mode="rgb_array",
            auto_reset_on_step=True,
            observation_mode="pixels",
        )
        try:
            obs, raw_info = env.reset(seed=0)
            safe_info = build_safe_info(
                raw_info=raw_info,
                last_reward=0.0,
                task_id=task,
            )
            assert set(safe_info) == {"last_reward", "inventory", "task_id"}
            action = call_policy(binding.policy, obs, safe_info)
            assert 0 <= action <= 6
            assert policy.task_id == task
        finally:
            env.close()

    forbidden_modules = {
        "submissions.qn_agent",
        "submissions.dqn_agent",
        "submissions.robust_improved_agent",
    }
    imported_forbidden = sorted(forbidden_modules.intersection(sys.modules))
    assert not imported_forbidden, f"unexpected cxy-policy imports: {imported_forbidden}"

    print(f"CXY Agent contract check passed for {policy_spec}.")
    print("- one shared Policy object is bound to all five tasks")
    print("- reset() clears main, legacy, snapshot, and Task 5 dispatch state")
    print("- safe_info contains only last_reward, inventory, and task_id")
    print("- each task produces a valid action and activates its bound task_id")
    print("- QN/DQN and robust_improved_agent are not imported")


if __name__ == "__main__":
    main()
