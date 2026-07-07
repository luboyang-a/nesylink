import gymnasium as gym
from nesylink.env import make_env
from submissions.rl_logic_agent import policy
from submissions.logic_agent_liudj import extract_scene, inventory_from_info

def train_rl_agent(task_num: int, episodes: int):
    env = make_env(
        task_id=f"mathematical_logic/task_{task_num}",
        observation_mode="pixels",
        render_mode="rgb_array",
        max_steps=2000
    )

    print(f"Q-Learning 训练 Task {task_num}...")
    policy.epsilon = 0.4
    for ep in range(episodes):
        obs, info = env.reset()
        policy.reset(task_id=f"mathematical_logic/task_{task_num}")
        done = False
        total_reward = 0
        policy.epsilon = max(0.05, policy.epsilon * 0.992)
        last_state_str = None
        macro_act_idx = None
        macro_reward = 0.0
        while not done:
            scene_before = extract_scene(obs, policy.previous_player)
            inv_before = inventory_from_info(info)
            current_state_str = policy._get_abstract_state(scene_before, inv_before)
            if current_state_str != last_state_str:
                if last_state_str is not None and macro_act_idx is not None:
                    policy.learn(last_state_str, macro_act_idx, macro_reward, current_state_str)
                macro_reward = 0.0
                action = policy.act(obs, info)
                macro_act_idx = policy.last_macro_act_idx
                last_state_str = current_state_str
            else:
                action = policy.act(obs, info)
            next_obs, reward, terminated, truncated, next_info = env.step(action)
            done = terminated or truncated
            total_reward += reward
            macro_reward += reward
            if terminated:
                if next_info.get("terminal_reason") == "world_completed":
                    final_reward = 150.0
                else:
                    final_reward = -50.0
                if last_state_str is not None and macro_act_idx is not None:
                    policy.learn(last_state_str, macro_act_idx, macro_reward + final_reward, "TERMINAL")
            obs, info = next_obs, next_info
        print(f"Episode {ep+1}/{episodes} | 本局得分: {total_reward:.2f} | 探索率: {policy.epsilon:.3f} | 已学符号状态数: {len(policy.q_table)}")
    policy.save_weights()
    print("\n神经符号 Q-Learning 训练成功结束！")
    env.close()

if __name__ == "__main__":
    train_rl_agent(task_num=5, episodes=300)