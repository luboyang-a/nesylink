# NesyLink 项目要求与下一步完成方案

> 这是曹潇月个人使用的项目进度清单；先看本页，后文仅供查证。
> 最近更新：2026 年 7 月 18 日

## 我的当前进度（只看这里即可）

### 文件怎么分

| 文件 | 用途 | 修改规则 |
|---|---|---|
| `submissions/robust_cxy_agent.py` | 我的当前候选策略 | 我的修改都写这里，我的测评显式指定它 |
| `submissions/robust_cxy_legacy_agent.py` | 我 7 月 14 日 04:51 版本的兼容实现 | 一般不直接修改 |
| `submissions/robust_new_agent.py` | 团队公共候选策略 | 保持拉取状态，不直接混入我的实验 |
| `utils/check_*.py`、`utils/evaluate_final_agent.ps1` | 团队公共测试脚本 | 保持默认测试公共 new；我的测试在命令中显式绑定 cxy |

团队协作原则：每个人先在自己的 Agent 文件中开发和提交结果；统一使用同一套评测口径比较；最后由团队选出最佳版本或合并有效改动，再生成唯一最终提交入口。不要多人同时直接改同一个候选文件。

### 已完成

- [x] 确认正式测评口径：原始 60%、spatial 30%、五种颜色 10%；
- [x] 我的 Agent 使用允许的像素、`inventory`、`last_reward` 和 `task_id`；
- [x] P0 完成：Task 4 两个重点用例通过；
- [x] P0 完成：Task 5 spatial A/B/C 全部打开 4 个宝箱、零受伤并达到 `world_completed`；
- [x] `LogicSubmissions/Logic.lean` 编译通过，无 `sorry`、`admit`、`axiom`；
- [x] 我的 cxy 文件与团队公共 new 文件已经分开。

### 下一步（按顺序做）

1. **保存当前版本**：提交 `robust_cxy_agent.py` 和它依赖的 `robust_cxy_legacy_agent.py`，记录 commit；
2. **跑 10 局小样本**：五关都用 cxy，按正式 60/30/10 套件运行，保存 `eval_results/cxy_final_10.json`；
3. **修失败项**：优先检查 `high_contrast`，再处理 Task 2–5 的颜色或布局失败；
4. **跑 100 局正式测评**：保存 `eval_results/cxy_final_100.json`，记录命令、seed、commit、步数设置；
5. **补 Lean 对应**：优先修正怪物 HP、宝箱 loot、按钮触发、Task 5 全宝箱目标，并整理 Python—Lean 对应表；
6. **完成报告与提交包**：使用最终 JSON 写结果，补截图、失败案例、复现命令和干净环境测试；
7. **团队最终选择**：比较每个人同口径结果，决定直接采用最佳 Agent，或把明确有效的修改合并到最终入口。

### 目前还没完成

- [ ] 当前 cxy 的五关完整 60/30/10 JSON；
- [ ] 每关 100 episode 的正式结果；
- [ ] Lean 与 Python 关键机制完全对齐；
- [ ] 正式报告、截图、干净环境复现和最终 ZIP；
- [ ] 团队最终 Agent 版本选择。

---

## 核心要求摘要

项目技术方向是：

> **像素感知 → 符号状态 → 局内短期目标 → BFS / 安全执行**

旧版 `redraw_symbols` 式的极端视觉泛化不进入正式鲁棒性套件。Task 5 必须真正达到 `world_completed`，不能用刷 reward 代替通关。当前 P0 已完成，主要剩余工作是正式分层测评、Lean 语义增强以及报告和提交包。

### 关于 Task 5 “成功”的准确解释

需要区分两个层次：

- **测评脚本中的 episode 成功**：Task 5 必须达到 `world_completed`，否则 `success=False`；
- **课程最终评分**：不会只根据 `success_rate`，还会综合 reward、milestone、阶段进展、学习或规划策略的难度、Lean 形式化完成度、报告质量和可读性。

因此，Task 5 没有完整通关时仍可能因完成部分目标、策略设计和形式化获得部分课程分，但不能在自动测评结果中算作成功通关。

---

## 一、群聊讨论的核心问题

群聊中实际上混合了三种不同的“泛化”能力。

### 1. 局内探索

Agent 进入一个新房间后，根据当前看到的内容决定下一步做什么。例如：

- 看见宝箱，就规划路径去开宝箱；
- 拿到钥匙，就寻找并开启锁门；
- 看见怪物靠近，就攻击、格挡或躲避；
- 当前房间没有目标，就探索尚未访问的出口。

这是项目最核心、也最符合“塞尔达式 Agent”的能力。

### 2. 布局泛化

墙壁、出生点、宝箱、怪物或出口位置改变后，Agent 不能继续执行固定动作序列，而要：

1. 从当前画面重新识别地图；
2. 构造新的符号状态；
3. 根据新位置重新运行 BFS；
4. 选择当前可达的短期目标。

### 3. 视觉泛化

颜色、纹理甚至符号整体改变后，Agent 仍然要理解每个图形代表什么。

群聊质疑的重点是：如果画面被完全重画成陌生符号，而每次测评又只有一次 episode，Agent 很难在局内从零学习所有符号含义。这种测评更接近“重新学习视觉语义”，与 Task 5 的任务规划目标存在冲突。

---

## 二、群聊最终可以确认的口径

根据助教后续回复，可以整理出以下结论：

1. **策略实现方式开放。**

   可以使用规则、搜索、强化学习、监督学习、离线学习、在线学习，或者组合方法。

2. **允许每关使用专用策略。**

   也可以使用一个共享策略完成五关。统一策略更能体现复用和泛化能力，但不是基础得分的强制条件。

3. **Hardcoding 不被禁止。**

   如果规则策略和 Lean 形式化做得好，助教并不反对。但固定动作序列式“背板”明显弱于根据当前画面重新规划。

4. **旧版极端视觉泛化不是最终测评本意。**

   助教明确表示，之前那种视觉泛化是沟通未对齐造成的，最终不会采用那种方式。

5. **Task 5 会考察局内探索效率。**

   主要通过最大步数、完成情况、阶段目标和 reward 判断。

6. **不能靠反复穿门刷 reward。**

   最终不会只看累计 reward。如果发现 Agent 在两个房间之间来回刷分但没有完成任务，可能被识别并扣分。

7. **当前公布的测评比例是：**

   - 原始地图：60%；
   - 地图布局变化：30%；
   - 渲染或颜色变化：10%。

### 当前执行口径

结合群聊公告、当前测评文档和 `evaluate_policy.py`，目前可以确定：

1. 正式鲁棒性测评按原始地图 60%、布局变化 30%、颜色变化 10% 划分；
2. 10% 颜色阶段依次循环以下五种变体：

- `grayscale`；
- `dark`；
- `bright`；
- `high_contrast`；
- `inverted`。

3. `redraw_symbols` 和 `redraw_geometric` 虽然仍保留为脚本中可手动调用的观察变体，但不进入正式 `--robustness-suite`；
4. Task 5 和其他任务一样，只有达到 `world_completed` 才计为成功；
5. 策略性能的主要指标是 `success_rate`，reward、步数、milestone 和 progress 用于辅助分析完成程度与探索效率；
6. 允许五个 `--task-policy` 指向同一个 Agent 文件。通过任务绑定的策略会收到对应 `task_id`，但同一 policy spec 只加载一次，因此 Agent 必须在每个 episode 正确重置内部状态。

除非助教之后明确发布新版规则或新版脚本，否则应直接按当前仓库中的 `evaluate_policy.py` 开发、测试和记录结果，不再把上述已明确事项列为开放问题。

---

## 三、项目正式要求

根据仓库中的任务说明，课程项目同时考察四个部分。

| 模块 | 占比 | 核心要求 |
|---|---:|---|
| 环境形式化 | 30% | 使用 Lean 建模对象、动作、状态转移和安全性质 |
| 策略形式化与证明 | 30% | 证明规划器、动作过滤器或轨迹验证器的性质 |
| 策略性能 | 30% | 五关完成率、阶段进展、布局和颜色鲁棒性 |
| 报告与可读性 | 10% | 说明方法、定理、实验结果和复现方式 |

### 正式 Agent 可以使用的信息

- 当前像素观测 `obs`；
- 上一步标量奖励 `last_reward`；
- 测评接口显式提供的物品栏；
- 使用 `--task-policy` 时显式提供的 `task_id`。

### 正式 Agent 不能直接使用的信息

- 玩家真实坐标、血量和朝向；
- 房间 ID、房间坐标；
- 实体数量和实体真实坐标；
- 地图真值、地图变体名称；
- 机关隐藏状态；
- 完整事件列表；
- reward 的内部细分信号；
- 只在 `full` 调试模式中提供的内部状态。

调试和训练阶段可以使用完整 `info` 做标注、分析和验证，但最终推理阶段必须使用 `safe` 接口。

---

## 四、当前完成进度

### 总体状态

| 工作项 | 当前状态 | 说明 |
|---|---|---|
| 个人最终 Agent 主体 | P0 已实现 | `robust_cxy_agent.py` 已有像素抽取、符号地图、BFS、房间记忆和任务高层逻辑 |
| 团队公共 Agent | 保持上游状态 | `robust_new_agent.py` 已恢复为当前 Git HEAD，不再混入曹潇月的未提交修改 |
| 布局泛化 | P0 重点用例通过 | Task 5 spatial A/B/C 全部成功；Task 4 spatial C 成功；其余五关完整 spatial 小样本仍待 P1 重跑 |
| 颜色鲁棒性 | 部分通过 | 历史 Task 1 多数颜色成功、Task 4 grayscale 成功；五关五种正式颜色尚无当前 cxy 统一结果 |
| Task 4 / Task 5 | P0 完成 | 固定 5 个回归用例全部达到 `world_completed` |
| QN / DQN | 实验分支 | 引用旧专家；Task 5 缺少 Q 表，不适合作为最终主线 |
| Lean | 可编译、待增强 | 2026-07-18 实测编译通过且无 `sorry/admit/axiom`，但部分语义与真实环境不一致 |
| 报告与提交包 | 未完成 | 缺少正式报告、五关 JSON、截图和复现包 |

### 1. 当前 Agent 主体

曹潇月个人后续开发、测试和候选提交入口是：

```text
submissions/robust_cxy_agent.py
```

其中 `submissions/robust_cxy_legacy_agent.py` 保存 2026-07-14 04:51 提交 `0c3c087` 的已验证策略，供新版 cxy 复用。`submissions/robust_new_agent.py` 是团队公共文件，保持当前 Git HEAD；除非团队明确决定合并，不再把个人实验直接写入该文件。

它已经具备以下能力：

- 从像素识别玩家、墙壁、宝箱、怪物、按钮、陷阱和出口；
- 构建当前房间的符号地图；
- 根据当前布局重新运行 BFS，而不是执行固定动作序列；
- 保存跨房间记忆；
- 根据钥匙、装备、宝箱、怪物和出口选择短期目标；
- 只读取允许的 `inventory` 和 `task_id`；
- 针对 Task 4、Task 5 编写了专门的高层流程。

因此，当前方案不是纯粹背固定坐标，整体方向符合群聊中所说的“根据当前画面规划短期目标”。

### 2. 当前已验证的鲁棒性

历史上对当时名为 `robust_new_agent.py`、后来重命名为 `robust_cxy_agent.py` 的曹潇月策略做过以下 Task 1 实测：

| 测试阶段 | 样本数 | 结果 | 说明 |
|---|---:|---:|---|
| 原始地图 | 6 | 6/6 | 全部成功 |
| 布局变化 | 3 | 3/3 | spatial A/B/C 各一局，全部成功 |
| 灰度 | 1 | 成功 | 颜色变化 |
| 变暗 | 1 | 成功 | 颜色变化 |
| 变亮 | 1 | 成功 | 颜色变化 |
| 反色 | 1 | 成功 | 颜色变化 |
| 高对比度 | 1 | 失败 | 当前明确短板 |

这些结果能够证明：

- 当前策略确实能处理 Task 1 的布局变化；
- 当前感知层能够处理多数已有颜色变体；
- 高对比度模式仍然存在识别问题。

但这些结果只来自 Task 1，不能据此宣称 Task 2–5 也全部具备相同鲁棒性。

### 3. QN / DQN 当前不适合做最终主线

现有 QN 历史结果中：

- Task 1–3 的历史表现较好；
- Task 4 原始地图成功，但颜色测试表现不稳定；
- 没有 Task 5 的完整 QN 结果。

同时，`qn_agent.py` 存在以下问题：

- 引用的是旧版 `robust_improved_agent.py`；
- 没有使用最新的 `robust_new_agent.py`；
- 只有 Task 1–4 的 Q 表；
- Task 5 找不到 Q 表时会退化为随机高层目标；
- 会修改共享专家对象的目标选择函数，存在全局状态和加载顺序风险。

因此建议：

> 将 `robust_cxy_agent.py` 固定为曹潇月个人测试与候选提交主线，QN/DQN 只保留为实验对照；团队公共 `robust_new_agent.py` 单独维护。

### 4. 正式提交入口存在一个关键问题

`robust_cxy_agent.py` 的 Task 4、Task 5 高层逻辑依赖 `task_id`。

如果只使用共享策略：

```powershell
--policy submissions/robust_cxy_agent.py
```

正式 `safe` 模式不会向共享策略提供任务编号。

更稳妥的提交方式，是把同一个文件分别绑定到五关：

```powershell
python utils/evaluate_policy.py `
  --tasks `
    mathematical_logic/task_1 `
    mathematical_logic/task_2 `
    mathematical_logic/task_3 `
    mathematical_logic/task_4 `
    mathematical_logic/task_5 `
  --task-policy mathematical_logic/task_1=submissions/robust_cxy_agent.py `
  --task-policy mathematical_logic/task_2=submissions/robust_cxy_agent.py `
  --task-policy mathematical_logic/task_3=submissions/robust_cxy_agent.py `
  --task-policy mathematical_logic/task_4=submissions/robust_cxy_agent.py `
  --task-policy mathematical_logic/task_5=submissions/robust_cxy_agent.py `
  --info-mode safe `
  --robustness-suite `
  --num-envs 100
```

这样仍然复用了同一套感知、规划和执行代码，只是允许高层任务管理器知道当前任务编号。

---

## 五、Lean 形式化当前状态

当前文件：

```text
LogicSubmissions/Logic.lean
```

已经完成的部分：

- Lean 4 编译通过；
- 没有发现 `sorry`、`admit` 或 `axiom`；
- 定义了位置、动作和物品栏；
- 定义了墙、陷阱、怪物、宝箱、按钮、开关、桥和出口；
- 定义了安全位置和状态转移；
- 证明了动作合法性；
- 证明了路径安全相关性质；
- 证明了执行序列的拼接；
- 为五关编写了抽象的阶段组合定理。

### 当前主要风险

1. **怪物 HP 与真实环境不一致。**

   当前 Lean 模型中一次攻击会直接删除怪物，而真实环境中的怪物通常需要多次攻击。

2. **宝箱 loot 被过度简化。**

   当前模型中开箱统一增加钥匙，但真实宝箱可能提供金币、回血、钥匙或剑。

3. **按钮触发方式可能不一致。**

   当前模型把按钮处理成 `attack` 交互，但真实按钮通常是走上去触发。

4. **Task 5 目标没有完全对应。**

   真实 Task 5 的目标是探索多个房间并打开全部宝箱，当前部分定理更接近“按钮—钥匙—出口”。

5. **尚未证明 Python BFS 满足 Lean 契约。**

   当前定义了 `PathPlanSound`，并证明满足该谓词的路径是安全的，但尚未证明 Python 中实际 BFS 返回的路径一定满足它。

6. **部分任务定理证明强度偏弱。**

   一些定理把“各阶段已经可以执行”作为前提，然后证明这些阶段能够拼接。它们证明了组合正确性，但没有证明规划器一定能找到这些阶段。

---

## 六、建议的最终技术路线

不建议在截止日前突然转向复杂的在线强化学习。当前最合适的架构是：

```text
像素观测 obs
    ↓
对象与地图识别
    ↓
当前房间 Symbolic Scene
    ↓
短期目标管理器
    ↓
BFS / 安全动作过滤
    ↓
移动、攻击、开箱、过门
```

### 高层目标选择顺序

1. 怪物构成直接危险时，格挡、攻击或避让；
2. 当前房间有可达宝箱时，前往并打开；
3. 有按钮或开关且可能解锁路径时，触发机关；
4. 获得钥匙后，尝试对应的锁门；
5. 当前房间没有有效目标时，探索尚未访问的出口；
6. Task 5 记录房间—出口图、已开宝箱和近期状态，避免无进展往返；
7. 每次进入新房间，都从当前像素重新构图并运行 BFS。

### 共享能力和任务专用能力

| 层次 | 共享内容 | 任务专用内容 |
|---|---|---|
| 感知层 | 玩家、墙、对象、出口和动态画面识别 | 尽量不做任务专用 |
| 规划层 | BFS、交互邻接、安全过滤、基础战斗动作 | 尽量不做任务专用 |
| 记忆层 | 房间图、访问记录、无进展检测 | Task 5 加强循环检测 |
| 目标层 | 宝箱、怪物、机关、出口的通用优先级 | Task 4/5 的任务链顺序 |

这样既允许针对不同任务设计高层策略，又能体现统一的感知、规划和执行架构。

---

## 七、下一步完成方案

### P0：保存并遵循当前测评口径（已完成）

- 60% 原始地图、30% 布局变化、10% 颜色变化；
- 颜色阶段按 `grayscale`、`dark`、`bright`、`high_contrast`、`inverted` 准备；
- 正式鲁棒性套件不包含 `redraw_symbols/redraw_geometric`；
- Task 5 必须达到 `world_completed` 才计为成功；
- `success_rate` 是主要指标，reward 和阶段事件是辅助指标；
- 使用五个 `--task-policy` 将同一个个人候选入口 `robust_cxy_agent.py` 绑定到五关；
- 如果助教发布新版 `evaluate_policy.py`，再对照代码差异更新本节和测试命令。

当前最终解释为：自动测评成功严格使用 `world_completed`；课程总评综合完成率、阶段进展、策略难度、形式化和报告，不把完成率作为唯一评分依据。

### P0：确定个人候选 Agent 与团队文件边界（已完成）

- 固定 `submissions/robust_cxy_agent.py` 为曹潇月个人开发、测试和候选提交主线；
- `submissions/robust_new_agent.py` 保持团队上游 HEAD，不再承载个人未提交实验；
- `submissions/robust_cxy_legacy_agent.py` 保存 `0c3c087` 的已验证旧策略，仅作为 cxy 内部兼容实现；
- QN/DQN 只保留为实验对照；
- 不让 QN/DQN 修改最终专家对象的全局行为；
- 使用五个 `--task-policy` 绑定同一个最新 Agent；
- 验证连续跑多个任务时，内部状态能够正确重置。

最终入口已经固定为：

```text
submissions/robust_cxy_agent.py
```

仓库公共脚本仍以团队 `robust_new_agent.py` 为默认入口，不能直接用来证明 cxy 当前结果。个人测试必须显式指定 cxy 文件，例如：

```powershell
# 示例：单独测试 Task 5，并显式绑定个人 Agent
python utils/evaluate_policy.py `
  --tasks mathematical_logic/task_5 `
  --task-policy mathematical_logic/task_5=submissions/robust_cxy_agent.py `
  --info-mode safe --robustness-suite --num-envs 10
```

个人正式命令应让五个 `--task-policy` 均显式指向同一个 `robust_cxy_agent.py`。公共 `check_final_agent_contract.py`、`check_task45_p0.py` 和 `evaluate_final_agent.ps1` 保持 HEAD，仍测试团队 `robust_new_agent.py`；不要为了个人测试修改它们。QN/DQN 不会被个人候选入口导入，因此其 monkey patch 不会影响 cxy 测评。

此前用等价的 cxy 显式绑定完成过契约检查，确认：

- 五关绑定到同一个 `robust_cxy_agent.Policy` 对象；
- `reset()` 会清空代表性的跨 episode、跨任务状态；
- `safe_info` 只包含 `last_reward`、`inventory` 和 `task_id`；
- 五关均能收到正确 `task_id` 并输出 `0..6` 范围内的合法动作；
- 最终入口不会导入 QN、DQN 或旧版 `robust_improved_agent`。

五关原始地图各 1 局的端到端 smoke test 也已完成：

| Task | 成功 | 步数 | Reward |
|---|---:|---:|---:|
| Task 1 | 是 | 290 | 127.050 |
| Task 2 | 是 | 173 | 138.270 |
| Task 3 | 是 | 554 | 167.960 |
| Task 4 | 是 | 1083 | 256.170 |
| Task 5 | 是 | 1089 | 158.060 |

Task 5 本次运行打开 4 个宝箱、完成 5 次换房、击杀 1 只怪物、按下 1 个按钮、没有触发陷阱，并最终达到 `world_completed`。结果保存在：

```text
eval_results/final_agent_smoke_1.json
```

### P0：优先完成 Task 4 和 Task 5

截至 2026-07-18 当前工作区，按 `utils/check_task45_p0.py` 的同一 5 用例口径、但显式加载 `robust_cxy_agent.py` 的结果为：

| 用例 | 结果 | 步数 | 说明 |
|---|---:|---:|---|
| Task 4 `spatial_c/default` | 通过 | 1499 | 达到 `world_completed` |
| Task 4 `default/grayscale` | 通过 | 1072 | 达到 `world_completed` |
| Task 5 `spatial_a/default` | 通过 | 1148 | 4 个宝箱，零受伤，达到 `world_completed` |
| Task 5 `spatial_b/default` | 通过 | 1185 | 4 个宝箱，零受伤，达到 `world_completed` |
| Task 5 `spatial_c/default` | 通过 | 1130 | 4 个宝箱，零受伤，达到 `world_completed` |

因此本 P0 **已经完成**。Task 4 的两个重点回归用例和 Task 5 的三种固定 spatial 布局均已达到 `world_completed`。Task 5 三局均打开全部 4 个宝箱且没有 `agent_damaged` 事件，不再以部分 reward 或房间往返代替通关。

实现上，个人候选入口是单一的 `submissions/robust_cxy_agent.py`：Task 4 和 Task 5 `spatial_c` 通过 `robust_cxy_legacy_agent.py` 复用曹潇月提交 `0c3c087` 中已经验证的像素策略；Task 5 `spatial_a/b` 使用后续加入的房间切换识别、宝箱路线和停滞恢复逻辑。布局选择只读取首帧像素、`inventory` 和 `task_id`，符合 `safe` 信息约束。公共 `robust_new_agent.py` 不参与这些个人 P0 结果。

Task 4 重点：

- 正确识别机关状态；
- 完成拿钥匙、拿剑、过桥、杀怪和开最终宝箱的顺序；
- 避免在桥方向错误时反复尝试不可达目标。

Task 5 必做：

- 保存已访问房间和出口；
- 保存已经完成的宝箱、按钮、钥匙和怪物子目标；
- 增加无进展计数；
- 无进展时重新选择目标；
- 对近期的房间—出口往返设置禁忌记忆；
- 根据物品变化、画面变化或 reward 确认真实进展；
- 以打开全部宝箱和 `world_completed` 为目标；
- 不把累计 reward 最大化当作任务完成的替代品。

### P1：运行正式分层测评

当前状态：**未完成**。仓库现有 JSON 包括五关原始地图 smoke、Task 1–4 的历史 QN 结果和旧版 Task 4/5 P0 baseline，但没有针对当前 `robust_cxy_agent.py` 的五关完整 60/30/10 JSON。P0 的五个重点回归已在当前代码上逐项复现，但尚未保存为新的 JSON 文件。

按以下顺序执行：

1. 冻结当前 cxy 代码版本，记录 `git status`、commit（若未提交则记录工作区 diff）和 Python/Lean 版本；
2. 参照 `check_final_agent_contract.py` 的检查项，以 cxy 路径运行个人契约检查；不要修改公共脚本默认路径；
3. 参照 `check_task45_p0.py` 的 5 个 case，以 cxy 路径运行个人 P0 回归；不要修改公共脚本默认路径；
4. 运行五关小样本正式套件并保存 JSON：

```powershell
python utils/evaluate_policy.py --tasks mathematical_logic/task_1 mathematical_logic/task_2 mathematical_logic/task_3 mathematical_logic/task_4 mathematical_logic/task_5 --task-policy mathematical_logic/task_1=submissions/robust_cxy_agent.py --task-policy mathematical_logic/task_2=submissions/robust_cxy_agent.py --task-policy mathematical_logic/task_3=submissions/robust_cxy_agent.py --task-policy mathematical_logic/task_4=submissions/robust_cxy_agent.py --task-policy mathematical_logic/task_5=submissions/robust_cxy_agent.py --info-mode safe --robustness-suite --num-envs 10 --json-out eval_results/cxy_final_10.json
```

5. 按 task、`original/spatial/color` 和具体变体汇总失败，优先修复 `high_contrast` 及 Task 2–5 未覆盖的颜色失败；
6. 小样本稳定后运行每关 100 episode 的正式套件并保存最终 JSON：

```powershell
python utils/evaluate_policy.py --tasks mathematical_logic/task_1 mathematical_logic/task_2 mathematical_logic/task_3 mathematical_logic/task_4 mathematical_logic/task_5 --task-policy mathematical_logic/task_1=submissions/robust_cxy_agent.py --task-policy mathematical_logic/task_2=submissions/robust_cxy_agent.py --task-policy mathematical_logic/task_3=submissions/robust_cxy_agent.py --task-policy mathematical_logic/task_4=submissions/robust_cxy_agent.py --task-policy mathematical_logic/task_5=submissions/robust_cxy_agent.py --info-mode safe --robustness-suite --num-envs 100 --json-out eval_results/cxy_final_100.json
```

小样本至少应覆盖：

- 每关原始地图 3 局；
- spatial A/B/C 各 1 局；
- 助教最终确认的颜色变体各 1 局。

每次测评必须保存：

- 完整 JSON；
- 实际运行命令；
- seed；
- Agent 文件路径；
- Git commit 或代码版本；
- 是否修改过 `max_steps` 和 `action_repeat`。

### P1：增强 Lean 与 Python 的对应关系

当前状态：**编译与基础安全证明完成，语义对齐未完成**。2026-07-18 使用 `lake env lean LogicSubmissions/Logic.lean` 编译通过，源码未发现 `sorry`、`admit` 或 `axiom`。以下 10 项仍是后续工作，优先完成前 4 项和 Python—Lean 对应表：

截止日前不建议从零证明完整 BFS 的完备性。更可行的增强方案是：

1. 修正怪物 HP；
2. 区分不同宝箱 loot；
3. 把按钮改成踩踏触发；
4. 明确 Task 5 的“全部宝箱已打开”目标；
5. 定义与 Python 一致的安全动作过滤器；
6. 证明过滤后的移动不会越界、撞墙或主动进入陷阱；
7. 定义轨迹检查器；
8. 证明通过检查且达到目标的轨迹满足任务目标；
9. 在报告中明确像素识别是可信前置假设，Lean 验证符号规划和安全层；
10. 给出 Python 函数、Lean 定义和定理的一一对应表。

### P1：完成报告与提交包

当前状态：**未完成**。仓库中尚未发现正式报告、游戏/测评截图或候选提交 ZIP；现有 `eval_results` 也不是当前 cxy 的完整正式套件结果。必须在正式 JSON 固定后再写成功率，防止报告与代码版本不一致。

报告应围绕以下核心主张展开：

> 我们没有使用固定动作序列，而是从像素实时抽取符号地图，根据物品栏和局内历史选择短期目标，并通过 BFS 和安全约束执行；Lean 验证符号规划层和动作安全层。

报告需要包含：

- 五关任务流程；
- 感知、规划和执行架构；
- 正式推理允许使用的信息；
- 训练或调试时是否使用过完整 `info`；
- Lean 定理列表；
- Python 与 Lean 对应关系；
- 原始地图、布局变化、颜色变化成功率；
- `avg_steps`、`avg_reward` 和 milestone；
- Task 5 循环问题及其解决方式；
- 失败案例和局限性；
- 一键复现命令；
- 游戏运行和正式测评截图。

---

## 八、建议时间表

| 日期 | 工作重点 | 交付物 |
|---|---|---|
| 7 月 13–14 日 | 确认测评口径、冻结最终入口、跑五关小样本 | 确认记录、基线 JSON、失败清单 |
| 7 月 14–15 日 | 集中修 Task 4/5 和 spatial 失败 | 可稳定完成复杂任务的 Agent |
| 7 月 16 日 | 修正 Lean 语义并补强安全证明 | 最终 `Logic.lean`、定理清单 |
| 7 月 17 日 | 跑完整正式测评 | 五关分阶段 JSON、命令和代码版本 |
| 7 月 18 日 | 完成报告、截图和复现打包 | 报告、运行证据、候选提交 zip |
| 7 月 19 日 | 缓冲、复现和提交 | 最终 zip、提交确认 |

---

## 九、最终提交检查清单

- [x] 唯一、明确的个人候选 Agent 入口：`submissions/robust_cxy_agent.py`；
- [x] 五关 `task-policy` 绑定方式已经验证；
- [x] `safe` 模式下五关均能加载、接收正确 `task_id` 并输出合法动作；
- [ ] 原始地图、布局变化和最终颜色口径均有测评结果；
- [x] Task 5 P0 三种 spatial 布局均以 4 宝箱和 `world_completed` 结束，不以两房间刷分代替通关；
- [x] `Logic.lean` 编译通过；
- [x] 没有未说明的 `sorry`、`admit` 或 `axiom`；
- [ ] Lean 状态转移与实际 Python 环境的关键机制一致；
- [ ] 报告中的成功率与 JSON、代码版本一致；
- [ ] 已说明训练或调试阶段使用完整 `info` 的范围；
- [ ] 模型权重、依赖和运行路径齐全；
- [ ] 游戏截图和正式测评截图齐全；
- [ ] 从干净环境解压 zip 后完成过一次端到端复现。

---

## 最终建议

当前最重要的事情不是继续训练 QN/DQN，也不是复刻别人特殊的游戏画面，而是：

1. 固定个人候选入口 `robust_cxy_agent.py`，保持团队公共 `robust_new_agent.py` 不动；
2. 正确绑定五个任务的 `task_id`；
3. P0 已完成；先把当前 cxy 状态提交或记录 diff，形成可引用代码版本；
4. 运行每关 10 episode 的五关 60/30/10 小样本并保存 JSON；
5. 修复小样本暴露的颜色和剩余布局失败，再运行每关 100 episode；
6. 补强 Lean 与 Python 的语义对应，优先修正怪物 HP、宝箱 loot、按钮触发和 Task 5 全宝箱目标；
7. 用最终 JSON 更新报告中的成功率、步数、reward、milestone 和失败案例；
8. 补齐截图、复现说明、干净环境测试和最终提交包。
