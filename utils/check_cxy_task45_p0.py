from __future__ import annotations

import argparse

from evaluate_policy import load_policy, run_episode


CASES = (
    ("mathematical_logic/task_4", "spatial_c", "default", 2),
    ("mathematical_logic/task_4", "default", "grayscale", 0),
    ("mathematical_logic/task_5", "spatial_a", "default", 0),
    ("mathematical_logic/task_5", "spatial_b", "default", 1),
    ("mathematical_logic/task_5", "spatial_c", "default", 2),
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run CXY Task 4/5 P0 regressions.")
    parser.add_argument("--policy", default="submissions/robust_final_agent.py")
    args = parser.parse_args()
    policy = load_policy(args.policy)
    failures: list[str] = []

    for task_id, map_variant, obs_variant, seed in CASES:
        result = run_episode(
            policy=policy,
            task_id=task_id,
            eval_stage="cxy_p0_regression",
            seed=seed,
            max_steps=None,
            render_mode=None,
            obs_variant=obs_variant,
            action_repeat=None,
            map_variant=map_variant,
            info_mode="safe",
            policy_task_id=task_id,
        )
        label = f"{task_id} {map_variant} {obs_variant}"
        print(
            f"{label}: success={result.success} steps={result.steps} "
            f"reward={result.total_reward:.3f} terminal={result.terminal_reason}",
            flush=True,
        )
        if not result.success:
            failures.append(label)

    if failures:
        raise SystemExit("CXY P0 regression failures: " + ", ".join(failures))

    print(f"CXY Task 4/5 P0 regression check passed for {args.policy}.")


if __name__ == "__main__":
    main()
