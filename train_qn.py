import os
import json
import random
from typing import Any
import numpy as np

from nesylink.env import make_env
from nesylink.core.constants import ACTION_A, ACTION_NOOP
from submissions.robust_improved_agent import extract_scene, inventory_from_info, policy as expert_policy

original_select_target = expert_policy._select_target


def rl_guided_select_target(scene, inv):
    return getattr(expert_policy, 'current_rl_target', None)


expert_policy._select_target = rl_guided_select_target


class QNLearner:
    def __init__(self, task_name: str):
        self.task_name = task_name
        self.previous_player = (0, 0)
        self.macro_actions = ["CHEST", "MONSTER", "EXIT_NORTH", "EXIT_EAST", "EXIT_SOUTH", "EXIT_WEST"]
        self.q_table = {}
        self.lr = 0.1
        self.gamma = 0.95
        self.weight_path = f"models/q_table_{task_name}.json"

    def _get_abstract_state(self, scene: Any, inv: dict[str, Any]) -> str:
        px, py = scene.player
        keys = int(inv.get("keys", 0) or 0)
        m_dist = [(m[0] - px, m[1] - py) for m in scene.monsters]
        c_dist = [(chest[0] - px, chest[1] - py) for chest in scene.chests]
        near_m = min(m_dist, key=lambda x: abs(x[0]) + abs(x[1])) if m_dist else (0, 0)
        near_c = min(c_dist, key=lambda x: abs(x[0]) + abs(x[1])) if c_dist else (0, 0)
        m_dir = (1 if near_m[0] > 0 else (-1 if near_m[0] < 0 else 0),
                 1 if near_m[1] > 0 else (-1 if near_m[1] < 0 else 0))
        c_dir = (1 if near_c[0] > 0 else (-1 if near_c[0] < 0 else 0),
                 1 if near_c[1] > 0 else (-1 if near_c[1] < 0 else 0))
        avail_exits = "".join([d[0] for d in ["north", "east", "south", "west"] if scene.exits.get(d)])
        return f"K_{keys}_H_{scene.room_hint}_M_{m_dir}_C_{c_dir}_EX_{avail_exits}"

    def get_q_values(self, state: str) -> list[float]:
        if state not in self.q_table:
            self.q_table[state] = [0.0] * len(self.macro_actions)
        return self.q_table[state]

    def learn(self, state: str, macro_act_idx: int, reward: float, next_state: str):
        q_vals = self.get_q_values(state)
        next_q_vals = self.get_q_values(next_state)
        q_vals[macro_act_idx] += self.lr * (reward + self.gamma * max(next_q_vals) - q_vals[macro_act_idx])

    def save(self):
        os.makedirs("models", exist_ok=True)
        with open(self.weight_path, "w") as f:
            json.dump(self.q_table, f)


def train_task(task_num: int, episodes: int = 300):
    task_name = f"task_{task_num}"
    env = make_env(task_id=f"mathematical_logic/{task_name}", observation_mode="pixels", max_steps=3000)
    learner = QNLearner(task_name)
    epsilon = 0.4

    print(f"\n开始训练 QN: {task_name}")
    for ep in range(episodes):
        obs, info = env.reset()
        expert_policy.reset(task_id=f"mathematical_logic/{task_name}")
        learner.previous_player = (0, 0)

        done = False
        total_reward = 0
        epsilon = max(0.05, epsilon * 0.992)

        last_state_str = None
        macro_act_idx = None
        macro_reward = 0.0

        while not done:
            scene_before = extract_scene(obs, learner.previous_player)
            inv_before = inventory_from_info(info)
            current_state_str = learner._get_abstract_state(scene_before, inv_before)

            # 状态发生改变时（一个宏观动作执行完毕），结算奖励并重新决策
            if current_state_str != last_state_str:
                if last_state_str is not None and macro_act_idx is not None:
                    learner.learn(last_state_str, macro_act_idx, macro_reward, current_state_str)
                macro_reward = 0.0

                # 新的决策
                q_vals = learner.get_q_values(current_state_str)
                macro_act_idx = random.randint(0, len(learner.macro_actions) - 1) if random.random() < epsilon else int(
                    np.argmax(q_vals))
                last_state_str = current_state_str

            chosen_intent = learner.macro_actions[macro_act_idx]
            target = None
            if chosen_intent == "CHEST":
                target = expert_policy._nearest_chest(scene_before)
            elif chosen_intent == "MONSTER" and scene_before.monsters:
                target = ("monster", expert_policy._nearest_reachable_interaction(scene_before, scene_before.monsters))
            elif chosen_intent.startswith("EXIT_"):
                d = chosen_intent.split("_")[1].lower()
                if scene_before.exits.get(d): target = ("exit", d)

            expert_policy.current_rl_target = target if target else original_select_target(scene_before, inv_before)

            action = expert_policy.act(obs, info)
            next_obs, reward, terminated, truncated, next_info = env.step(action)
            done = terminated or truncated
            total_reward += reward
            macro_reward += reward

            if terminated:
                final_reward = 1000.0 if next_info.get("terminal_reason") == "world_completed" else -50.0
                if last_state_str and macro_act_idx is not None:
                    learner.learn(last_state_str, macro_act_idx, macro_reward + final_reward, "TERMINAL")

            obs, info = next_obs, next_info
            learner.previous_player = scene_before.player
            reason = next_info.get("terminal_reason", "truncated")
            print(
                f"Episode {ep + 1}/{episodes} | 得分: {total_reward:.2f} | 探索率: {epsilon:.3f} | Q表大小: {len(learner.q_table)} | 结局: {reason}")

    learner.save()
    print(f"{task_name} 训练完成！权重已保存到 models/")
    env.close()


if __name__ == "__main__":
    train_task(task_num=3, episodes=50)
