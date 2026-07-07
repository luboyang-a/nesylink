# 数理逻辑任务测评说明

本文档只说明策略性能测评的核心规则和固定三阶段鲁棒性测试。测评脚本的完整参数、policy 接口、JSON 字段和实现细节见 [测评脚本细节说明](evaluation-details.md)。

## 一、评分依据

策略性能的主要指标是任务完成率：

```text
success_rate = 成功完成任务的 episode 数 / 总 episode 数
```

一次 episode 是否成功，以环境返回的任务完成信号为准，包括 `world_completed` 或等价的终止原因。也就是说，正确率按“是否完成整个任务”计算，而不是按单步动作是否正确计算。

除最终成功率外，测评脚本还会统计阶段性进展，例如：

- 物品搜集：`key_collected`、`gold_collected`、`item_collected`
- 宝箱与机关：`chest_opened`、`button_pressed`、`door_opened`
- 战斗与风险：`monster_killed`、`trap_triggered`、`agent_dead`
- 地图推进：`room_changed`、`exit_reached`、`environment_completed`

这些进度指标用于分析 agent 已经完成了哪些子目标，不替代最终成功率。

## 二、固定三阶段测评

最终使用固定三阶段鲁棒性套件：

```bash
python utils/evaluate_policy.py \
  --policy submissions/student_policy.py \
  --robustness-suite \
  --num-envs 10 \
  --json-out results/robustness_suite_eval.json
```

如果每个 task 有单独的 agent 文件，也可以分别指定：
（需要给出你们自己的调用方法）

```bash
python utils/evaluate_policy.py \
  --tasks mathematical_logic/task_1 mathematical_logic/task_2 \
  --task-policy mathematical_logic/task_1=submissions/task1_agent.py \
  --task-policy mathematical_logic/task_2=submissions/task2_agent.py \
  --robustness-suite \
  --num-envs 10
```

每个 task 会运行三组测评：

| 阶段 | episode 数 | 输入图像 | 目的 |
|---|---:|---|---|
| `original` | 10 | 原始渲染输入 `default` | 测试能否在标准环境中完成任务 |
| `color` | 10 | 灰度、变暗、变亮、高对比度、反色循环使用 | 测试对颜色和亮度变化的鲁棒性 |
| `redraw` | 10 | 前 5 轮使用方案一，后 5 轮使用方案二 | 测试对角色和物体形状变化的鲁棒性 |

如果调整 `--num-envs`，三个阶段都会使用相同 episode 数；重画阶段会尽量在两种重画方案之间平均分配。

## 三、重画方案

### 方案一：几何重画

方案一使用几何形状替代原始 sprite，例如：墙是白色方块，宝箱是黄色菱形，agent 是青色圆形加方向三角，怪物是红色六边形。

![redraw_geometric](assets/redraw_geometric.png)

### 方案二：符号重画

方案二使用更抽象的符号图，例如：墙是黑色方块，宝箱是金色方框加标记，agent 是白色三角箭头，怪物是红色符号块。

![redraw_symbols](assets/redraw_symbols.png)

## 四、结果解读

summary 会按 `(task_id, stage)` 分组输出。例如：

```text
mathematical_logic/task_3 [redraw]
  episodes:     10
  success_rate: 0.700
  avg_steps:    420.5
  avg_reward:   18.300
  variants:     {'redraw_geometric': 5, 'redraw_symbols': 5}
  progress:
    key_collected: 0.900
    chest_opened: 0.800
    monster_killed: 0.600
```

报告中建议至少比较：

- `original` 阶段成功率：标准渲染下能否完成任务。
- `color` 阶段成功率：是否依赖固定颜色。
- `redraw` 阶段成功率：是否依赖原始 sprite 形状。
- `progress` 指标：即使没有最终通关，是否完成了钥匙、宝箱、怪物、出口等子目标

更多参数和输出字段见 [测评脚本细节说明](evaluation-details.md)。
