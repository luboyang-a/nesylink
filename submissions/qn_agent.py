import os
import json
import random
import numpy as np
from submissions.robust_improved_agent import extract_scene, inventory_from_info, policy as expert_policy

original_select_target = expert_policy._select_target


def rl_guided_select_target(scene, inv):
    return getattr(expert_policy, 'current_rl_target', None)


expert_policy._select_target = rl_guided_select_target


class Policy:
    def __init__(self):
        self.macro_actions = ["CHEST", "MONSTER", "EXIT_NORTH", "EXIT_EAST", "EXIT_SOUTH", "EXIT_WEST"]
        self.q_table = {}
        self.current_task = None
        self.previous_player = (0, 0)
        self.last_state_str = None
        self.current_macro_act_idx = None
        self.task_id = ""

    def _extract_task_id_from_info(self, info):
        if isinstance(info, dict):
            task_id = info.get("task_id")
            if isinstance(task_id, str) and task_id:
                return task_id
        return None

    def _ensure_task_loaded(self, task_id):
        """Load task-specific Q table when task_id is received from safe info.

        New evaluate_policy.py may pass task_id through act(obs, info), not reset().
        This function keeps the old behavior but makes it work with the new API.
        """
        if not task_id:
            return

        self.task_id = task_id

        # Also make sure the wrapped expert policy knows the task.
        # This is important because expert_policy._select_target / act may depend on self.task_id.
        try:
            expert_policy.task_id = task_id
        except Exception:
            pass

        task_name = task_id.split("/")[-1]

        # If the correct Q table is already loaded, do not reload it every step.
        if self.current_task == task_name:
            return

        possible_paths = [
            os.path.join(
                os.path.dirname(os.path.dirname(__file__)),
                "models",
                f"q_table_{task_name}.json",
            ),
        ]

        loaded = False
        for weight_path in possible_paths:
            if os.path.exists(weight_path):
                with open(weight_path, "r") as f:
                    self.q_table = json.load(f)
                self.current_task = task_name
                loaded = True
                print(f"[QN Agent] 成功加载 Q 表: {weight_path}")
                break

        if not loaded:
            self.q_table = {}
            self.current_task = task_name
            print(f"[QN Agent] 警告: 未找到 q_table_{task_name}.json，使用随机策略")

    def reset(self, seed=None, task_id=None):
        expert_policy.reset(task_id=task_id)
        self.previous_player = (0, 0)
        self.last_state_str = None
        self.current_macro_act_idx = None

        # Old evaluator path: task_id may still be passed through reset().
        if task_id:
            self._ensure_task_loaded(task_id)

    def _get_abstract_state(self, scene, inv):
        px, py = scene.player
        keys = int(inv.get("keys", 0) or 0)
        m_dist = [(m[0] - px, m[1] - py) for m in scene.monsters]
        c_dist = [(c[0] - px, c[1] - py) for c in scene.chests]
        near_m = min(m_dist, key=lambda x: abs(x[0]) + abs(x[1])) if m_dist else (0, 0)
        near_c = min(c_dist, key=lambda x: abs(x[0]) + abs(x[1])) if c_dist else (0, 0)
        m_dir = (1 if near_m[0] > 0 else (-1 if near_m[0] < 0 else 0),
                 1 if near_m[1] > 0 else (-1 if near_m[1] < 0 else 0))
        c_dir = (1 if near_c[0] > 0 else (-1 if near_c[0] < 0 else 0),
                 1 if near_c[1] > 0 else (-1 if near_c[1] < 0 else 0))
        avail_exits = "".join([d[0] for d in ["north", "east", "south", "west"] if scene.exits.get(d)])
        return f"K_{keys}_H_{scene.room_hint}_M_{m_dir}_C_{c_dir}_EX_{avail_exits}"

    def act(self, obs, info=None):
        # New evaluator path: task_id is passed through info.
        task_id_from_info = self._extract_task_id_from_info(info)
        if task_id_from_info:
            self._ensure_task_loaded(task_id_from_info)

        scene = extract_scene(obs, self.previous_player)
        self.previous_player = scene.player
        inv = inventory_from_info(info)
        current_state_str = self._get_abstract_state(scene, inv)

        if current_state_str != self.last_state_str or self.current_macro_act_idx is None:
            if current_state_str in self.q_table:
                self.current_macro_act_idx = int(np.argmax(self.q_table[current_state_str]))
            else:
                self.current_macro_act_idx = random.randint(0, len(self.macro_actions) - 1)
            self.last_state_str = current_state_str

        chosen_intent = self.macro_actions[self.current_macro_act_idx]
        target = None
        if chosen_intent == "CHEST":
            target = expert_policy._nearest_chest(scene)
        elif chosen_intent == "MONSTER" and scene.monsters:
            target = ("monster", expert_policy._nearest_reachable_interaction(scene, scene.monsters))
        elif chosen_intent.startswith("EXIT_"):
            d = chosen_intent.split("_")[1].lower()
            if scene.exits.get(d):
                target = ("exit", d)

        expert_policy.current_rl_target = target if target else original_select_target(scene, inv)
        return expert_policy.act(obs, info)


def make_policy():
    return Policy()


policy = Policy()


def act(obs, info=None):
    return policy.act(obs, info)


def reset(seed=None, task_id=None):
    policy.reset(seed=seed, task_id=task_id)