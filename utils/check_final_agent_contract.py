from __future__ import annotations

import sys

from nesylink.env import make_env
from evaluate_policy import build_safe_info, call_policy, reset_policy, resolve_policies


TASKS = [f"mathematical_logic/task_{index}" for index in range(1, 6)]
POLICY_SPEC = "submissions/robust_new_agent.py"


def main() -> None:
    bindings = resolve_policies(
        default_policy_spec=None,
        task_policy_specs=[f"{task}={POLICY_SPEC}" for task in TASKS],
        task_ids=TASKS,
    )

    policy = bindings[TASKS[0]].policy
    assert all(binding.policy is policy for binding in bindings.values())
    assert all(binding.receives_task_id for binding in bindings.values())

    for task in TASKS:
        binding = bindings[task]

        # Dirty representative mutable fields, then verify the evaluator's
        # no-argument reset callback clears all cross-episode state.
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
    assert not imported_forbidden, f"unexpected final-policy imports: {imported_forbidden}"

    print("Final Agent contract check passed for task_1 through task_5.")
    print("- one shared robust_new_agent Policy object is bound to all five task-policy entries")
    print("- reset() clears representative cross-episode and cross-task state")
    print("- safe_info contains only last_reward, inventory, and task_id")
    print("- each task produces a valid action and activates its bound task_id")
    print("- QN/DQN and robust_improved_agent are not imported by the final entry")


if __name__ == "__main__":
    main()
