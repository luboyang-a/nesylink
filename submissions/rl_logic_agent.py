from __future__ import annotations
import os
import json
import random
from typing import Any
import numpy as np
from submissions.logic_agent_liudj import (
    extract_scene, inventory_from_info, MOVE_ACTIONS, policy as expert_policy
)
from nesylink.core.constants import ACTION_A, ACTION_NOOP

original_select_target = expert_policy._select_target
def rl_guided_select_target(scene, inv):
    return getattr(expert_policy, 'current_rl_target', None)
expert_policy._select_target = rl_guided_select_target

class Policy:
    def __init__(self) -> None:
        self.task_id = ""
        self.previous_player = (0, 0)
        self.macro_actions = ["CHEST", "MONSTER", "EXIT_NORTH", "EXIT_EAST", "EXIT_SOUTH", "EXIT_WEST"]
        self.q_table: dict[str, list[float]] = {}
        self.last_state_str = None
        self.current_macro_act_idx = None
        self.last_macro_act_idx = None
        self.lr = 0.1
        self.gamma = 0.95
        self.epsilon = 0.4
        self.weight_path = "weights/q_table.json"
        self.load_weights()

    def reset(self, seed: int | None = None, task_id: str | None = None) -> None:
        del seed
        self.task_id = task_id or ""
        self.previous_player = (0, 0)
        self.last_state_str = None
        self.current_macro_act_idx = None
        self.last_macro_act_idx = None
        expert_policy.reset(task_id=task_id)

    def _get_abstract_state(self, scene: Any, inv: dict[str, Any]) -> str:
        px, py = scene.player
        keys = int(inv.get("keys", 0) or 0)
        m_dist = [(m[0]-px, m[1]-py) for m in scene.monsters]
        c_dist = [(chest[0]-px, chest[1]-py) for chest in scene.chests]
        near_m = min(m_dist, key=lambda x: abs(x[0])+abs(x[1])) if m_dist else (0, 0)
        near_c = min(c_dist, key=lambda x: abs(x[0])+abs(x[1])) if c_dist else (0, 0)
        m_dir = (1 if near_m[0] > 0 else (-1 if near_m[0] < 0 else 0), 1 if near_m[1] > 0 else (-1 if near_m[1] < 0 else 0))
        c_dir = (1 if near_c[0] > 0 else (-1 if near_c[0] < 0 else 0), 1 if near_c[1] > 0 else (-1 if near_c[1] < 0 else 0))
        avail_exits = "".join([d[0] for d in ["north", "east", "south", "west"] if scene.exits.get(d)])
        return f"K_{keys}_H_{scene.room_hint}_M_{m_dir}_C_{c_dir}_EX_{avail_exits}"

    def _get_q_values(self, state: str) -> list[float]:
        if state not in self.q_table:
            self.q_table[state] = [0.0] * len(self.macro_actions)
        return self.q_table[state]

    def act(self, obs: np.ndarray, info: dict[str, Any] | None = None) -> int:
        scene = extract_scene(obs, self.previous_player)
        self.previous_player = scene.player
        inv = inventory_from_info(info)
        current_state_str = self._get_abstract_state(scene, inv)
        if current_state_str != self.last_state_str or self.current_macro_act_idx is None:
            q_vals = self._get_q_values(current_state_str)
            if random.random() < self.epsilon:
                macro_act_idx = random.randint(0, len(self.macro_actions) - 1)
            else:
                macro_act_idx = int(np.argmax(q_vals))
            self.current_macro_act_idx = macro_act_idx
            self.last_macro_act_idx = macro_act_idx
            self.last_state_str = current_state_str
        chosen_intent = self.macro_actions[self.current_macro_act_idx]
        target = None
        if chosen_intent == "CHEST":
            target = expert_policy._nearest_chest(scene)
        elif chosen_intent == "MONSTER" and scene.monsters:
            target = ("monster", expert_policy._nearest_reachable_interaction(scene, scene.monsters))
        elif chosen_intent.startswith("EXIT_"):
            direction = chosen_intent.split("_")[1].lower()
            if scene.exits.get(direction):
                target = ("exit", direction)
        if target is None:
            target = original_select_target(scene, inv)
        expert_policy.current_rl_target = target
        return expert_policy.act(obs, info)

    def learn(self, state: str, macro_act_idx: int, reward: float, next_state: str):
        q_vals = self._get_q_values(state)
        next_q_vals = self._get_q_values(next_state)
        q_vals[macro_act_idx] += self.lr * (reward + self.gamma * max(next_q_vals) - q_vals[macro_act_idx])

    def save_weights(self):
        os.makedirs(os.path.dirname(self.weight_path), exist_ok=True)
        with open(self.weight_path, "w") as f:
            json.dump(self.q_table, f)

    def load_weights(self):
        if os.path.exists(self.weight_path):
            with open(self.weight_path, "r") as f:
                self.q_table = json.load(f)
            self.epsilon = 0.0

policy = Policy()
def make_policy():
    return Policy()
def reset(seed=None, task_id=None):
    policy.reset(seed=seed, task_id=task_id)
def act(obs, info=None):
    return policy.act(obs, info)