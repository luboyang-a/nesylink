import os
import random
from collections import deque
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from nesylink.env import make_env

from submissions.robust_improved_agent import extract_scene, inventory_from_info, policy as expert_policy

original_select_target = expert_policy._select_target
def rl_guided_select_target(scene, inv):
    return getattr(expert_policy, 'current_rl_target', None)
expert_policy._select_target = rl_guided_select_target


class DQNModel(nn.Module):
    def __init__(self, state_dim, action_dim):
        super().__init__()
        # 此时输入是高层抽象特征向量，直接用全连接网络（MLP）训练即可，收敛极快！
        self.net = nn.Sequential(
            nn.Linear(state_dim, 128), nn.ReLU(),
            nn.Linear(128, 128), nn.ReLU(),
            nn.Linear(128, action_dim)
        )
    def forward(self, x):
        return self.net(x)


def get_macro_state_vector(obs, info, previous_player):
    """ 🌟 利用你的专家系统提取高层高度鲁棒的特征向量 """
    scene = extract_scene(obs, previous_player)
    inv = inventory_from_info(info)

    px, py = scene.player
    keys = float(inv.get("keys", 0) or 0)

    # 提取怪物和宝箱的相对方向向量 (无视绝对坐标扰动)
    m_dist = [(m[0] - px, m[1] - py) for m in scene.monsters]
    c_dist = [(chest[0] - px, chest[1] - py) for chest in scene.chests]
    near_m = min(m_dist, key=lambda x: abs(x[0]) + abs(x[1])) if m_dist else (0.0, 0.0)
    near_c = min(c_dist, key=lambda x: abs(x[0]) + abs(x[1])) if c_dist else (0.0, 0.0)

    m_dir_x = 1.0 if near_m[0] > 0 else (-1.0 if near_m[0] < 0 else 0.0)
    m_dir_y = 1.0 if near_m[1] > 0 else (-1.0 if near_m[1] < 0 else 0.0)
    c_dir_x = 1.0 if near_c[0] > 0 else (-1.0 if near_c[0] < 0 else 0.0)
    c_dir_y = 1.0 if near_c[1] > 0 else (-1.0 if near_c[1] < 0 else 0.0)

    # 出口可用性编码
    ex_n = 1.0 if scene.exits.get("north") else 0.0
    ex_e = 1.0 if scene.exits.get("east") else 0.0
    ex_s = 1.0 if scene.exits.get("south") else 0.0
    ex_w = 1.0 if scene.exits.get("west") else 0.0

    try:
        room_hint = float(scene.room_hint) if scene.room_hint is not None else 0.0
    except (ValueError, TypeError):
        room_hint = 0.0  # 如果无法转换为浮点数，默认为0

    # 组装成 10 维的核心状态向量
    state_vec = np.array([
        keys, room_hint,
        m_dir_x, m_dir_y,
        c_dir_x, c_dir_y,
        ex_n, ex_e, ex_s, ex_w
    ], dtype=np.float32)

    return state_vec, scene, inv


def train_dqn(task_num=1, episodes=500):
    task_name = f"task_{task_num}"
    env = make_env(task_id=f"mathematical_logic/{task_name}", observation_mode="pixels", max_steps=1000)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    # 定义 6 个高层宏观动作
    macro_actions = ["CHEST", "MONSTER", "EXIT_NORTH", "EXIT_EAST", "EXIT_SOUTH", "EXIT_WEST"]
    state_dim = 10
    action_dim = len(macro_actions)

    model = DQNModel(state_dim, action_dim).to(device)
    target_model = DQNModel(state_dim, action_dim).to(device)
    target_model.load_state_dict(model.state_dict())

    optimizer = optim.Adam(model.parameters(), lr=1e-3)
    buffer = deque(maxlen=20000)

    batch_size, gamma = 64, 0.99
    epsilon, epsilon_decay = 1.0, 0.992

    os.makedirs("models", exist_ok=True)
    model_path = f"models/dqn_{task_name}.pth"

    print(f"\n开始训练 DQN: {task_name} (Using device: {device})")

    for ep in range(episodes):
        obs, info = env.reset()
        expert_policy.reset(task_id=f"mathematical_logic/{task_name}")
        previous_player = (0, 0)

        state_vec, scene_before, inv_before = get_macro_state_vector(obs, info, previous_player)
        state_tensor = torch.tensor(state_vec, dtype=torch.float32).unsqueeze(0).to(device)

        total_reward, done = 0, False
        last_state_vec = state_vec.copy()
        macro_action_idx = None
        macro_reward = 0.0

        while not done:
            # 状态发生质变（走完一个格子或收集了物品）时，让 DQN 重新决策高层意图
            if macro_action_idx is None or not np.array_equal(state_vec, last_state_vec):

                # 如果上一段宏观动作执行过，把它存入 DQN 的 Replay Buffer
                if macro_action_idx is not None:
                    next_tensor = torch.tensor(state_vec, dtype=torch.float32).unsqueeze(0)
                    buffer.append((
                        torch.tensor(last_state_vec, dtype=torch.float32).unsqueeze(0),
                        macro_action_idx, macro_reward, next_tensor, done
                    ))

                macro_reward = 0.0
                last_state_vec = state_vec.copy()

                # DQN 选取高级意图
                if random.random() < epsilon:
                    macro_action_idx = random.randint(0, action_dim - 1)
                else:
                    with torch.no_grad():
                        macro_action_idx = model(state_tensor).argmax().item()

            # 将 DQN 选出的高级意图，映射成底层专家能够识别的 rl_target
            chosen_intent = macro_actions[macro_action_idx]
            target = None
            if chosen_intent == "CHEST":
                target = expert_policy._nearest_chest(scene_before)
            elif chosen_intent == "MONSTER" and scene_before.monsters:
                target = ("monster", expert_policy._nearest_reachable_interaction(scene_before, scene_before.monsters))
            elif chosen_intent.startswith("EXIT_"):
                d = chosen_intent.split("_")[1].lower()
                if scene_before.exits.get(d):
                    target = ("exit", d)

            # 把目标灌给底层专家系统
            expert_policy.current_rl_target = target if target else original_select_target(scene_before, inv_before)

            # 调用你完美的底层专家脚本来执行最精准的底层像素动作（走格/对齐）
            action = expert_policy.act(obs, info)
            next_obs, reward, terminated, truncated, next_info = env.step(action)

            done = terminated or truncated
            total_reward += reward
            macro_reward += reward

            # 为下一次循环迭代准备状态
            previous_player = scene_before.player
            next_vec, next_scene, next_inv = get_macro_state_vector(next_obs, next_info, previous_player)
            next_tensor = torch.tensor(next_vec, dtype=torch.float32).unsqueeze(0).to(device)

            obs, info, scene_before, inv_before, state_vec, state_tensor = next_obs, next_info, next_scene, next_inv, next_vec, next_tensor

            # DQN 神经网络反向传播优化
            if len(buffer) >= batch_size:
                batch = random.sample(buffer, batch_size)
                b_s, b_a, b_r, b_ns, b_d = zip(*batch)

                b_s = torch.cat(b_s).to(device)
                b_a = torch.tensor(b_a, dtype=torch.int64).unsqueeze(1).to(device)
                b_r = torch.tensor(b_r, dtype=torch.float32).unsqueeze(1).to(device)
                b_ns = torch.cat(b_ns).to(device)
                b_d = torch.tensor(b_d, dtype=torch.float32).unsqueeze(1).to(device)

                curr_q = model(b_s).gather(1, b_a)
                with torch.no_grad():
                    max_next_q = target_model(b_ns).max(1)[0].unsqueeze(1)
                    target_q = b_r + gamma * max_next_q * (1 - b_d)

                optimizer.zero_grad()
                nn.MSELoss()(curr_q, target_q).backward()
                optimizer.step()

        if ep % 5 == 0:
            target_model.load_state_dict(model.state_dict())
        epsilon = max(0.05, epsilon * epsilon_decay)
        reason = next_info.get("terminal_reason", "truncated")
        print(f"Episode {ep+1}/{episodes} | 得分: {total_reward:.2f} | Epsilon: {epsilon:.2f} | 结局: {reason}")

    torch.save(model.state_dict(), model_path)
    print(f"{task_name} DQN 模型已保存到 models/")
    env.close()

if __name__ == "__main__":
    train_dqn(task_num=1, episodes=30)