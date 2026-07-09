import os
import torch
import random
import torch.nn as nn
import numpy as np

from submissions.robust_improved_agent import extract_scene, inventory_from_info, policy as expert_policy

original_select_target = expert_policy._select_target


def rl_guided_select_target(scene, inv):
    return getattr(expert_policy, 'current_rl_target', None)


expert_policy._select_target = rl_guided_select_target


class DQNModel(nn.Module):
    def __init__(self, state_dim, action_dim):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(state_dim, 128), nn.ReLU(),
            nn.Linear(128, 128), nn.ReLU(),
            nn.Linear(128, action_dim)
        )

    def forward(self, x):
        return self.net(x)


class Policy:
    def __init__(self):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.macro_actions = ["CHEST", "MONSTER", "EXIT_NORTH", "EXIT_EAST", "EXIT_SOUTH", "EXIT_WEST"]
        self.model = DQNModel(state_dim=10, action_dim=6).to(self.device)
        self.current_task = None

        self.previous_player = (0, 0)
        self.last_state_vec = None
        self.current_macro_act_idx = None

    def reset(self, seed=None, task_id=None):
        # 重置底层的专家系统状态
        expert_policy.reset(task_id=task_id)
        self.previous_player = (0, 0)
        self.last_state_vec = None
        self.current_macro_act_idx = None

        if not task_id: return
        task_name = task_id.split("/")[-1]
        if self.current_task == task_name: return

        possible_paths = [
            os.path.join(os.path.dirname(os.path.dirname(__file__)), "models", f"dqn_{task_name}.pth"),
            os.path.join(os.path.dirname(__file__), "models", f"dqn_{task_name}.pth"),
        ]

        loaded = False
        for model_path in possible_paths:
            if os.path.exists(model_path):
                self.model.load_state_dict(torch.load(model_path, map_location=self.device))
                self.model.eval()
                self.current_task = task_name
                loaded = True
                print(f"[DQN Agent] 成功加载结合了专家的 DQN 模型: {model_path}")
                break

        if not loaded:
            print(f"[DQN Agent] 警告: 未找到 dqn_{task_name}.pth，使用随机策略")

    def _get_macro_state_vector(self, scene, inv):
        px, py = scene.player
        keys = float(inv.get("keys", 0) or 0)

        m_dist = [(m[0] - px, m[1] - py) for m in scene.monsters]
        c_dist = [(chest[0] - px, chest[1] - py) for chest in scene.chests]
        near_m = min(m_dist, key=lambda x: abs(x[0]) + abs(x[1])) if m_dist else (0.0, 0.0)
        near_c = min(c_dist, key=lambda x: abs(x[0]) + abs(x[1])) if c_dist else (0.0, 0.0)

        m_dir_x = 1.0 if near_m[0] > 0 else (-1.0 if near_m[0] < 0 else 0.0)
        m_dir_y = 1.0 if near_m[1] > 0 else (-1.0 if near_m[1] < 0 else 0.0)
        c_dir_x = 1.0 if near_c[0] > 0 else (-1.0 if near_c[0] < 0 else 0.0)
        c_dir_y = 1.0 if near_c[1] > 0 else (-1.0 if near_c[1] < 0 else 0.0)

        ex_n = 1.0 if scene.exits.get("north") else 0.0
        ex_e = 1.0 if scene.exits.get("east") else 0.0
        ex_s = 1.0 if scene.exits.get("south") else 0.0
        ex_w = 1.0 if scene.exits.get("west") else 0.0

        # 🌟 修复核心：安全转换 room_hint 文本到数字，提供降级防御
        room_hint = 0.0
        if scene.room_hint is not None:
            try:
                room_hint = float(scene.room_hint)
            except ValueError:
                # 提取字符串中的数字（如 'task1' -> 1.0），如果完全没有数字则使用固定哈希特征
                digits = [c for c in str(scene.room_hint) if c.isdigit()]
                if digits:
                    room_hint = float("".join(digits))
                else:
                    room_hint = float(abs(hash(str(scene.room_hint))) % 100)

        return np.array([
            keys, room_hint,
            m_dir_x, m_dir_y,
            c_dir_x, c_dir_y,
            ex_n, ex_e, ex_s, ex_w
        ], dtype=np.float32)

    def act(self, obs, info):
        # 1. 调用专家系统的场景提取
        scene = extract_scene(obs, self.previous_player)
        self.previous_player = scene.player
        inv = inventory_from_info(info)

        # 2. 生成特征向量
        current_state_vec = self._get_macro_state_vector(scene, inv)

        # 3. 只有状态发生抽象变化时，DQN 才会切换新的高级意图
        if self.last_state_vec is None or not np.array_equal(current_state_vec,
                                                             self.last_state_vec) or self.current_macro_act_idx is None:
            if self.current_task is not None:  # 如果成功加载了权重
                state_tensor = torch.tensor(current_state_vec, dtype=torch.float32).unsqueeze(0).to(self.device)
                with torch.no_grad():
                    self.current_macro_act_idx = self.model(state_tensor).argmax().item()
            else:
                self.current_macro_act_idx = random.randint(0, len(self.macro_actions) - 1)
            self.last_state_vec = current_state_vec

        # 4. 把高级意图再次无缝转换给底层专家去寻路定位
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