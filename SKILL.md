---
name: boss-zhipin-copilot
description: >-
  BOSS 直聘求职 copilot。配合「仿真人浏览器后端」（默认 agent-browser-runtime，亦支持 Codex 托管等）用真实光标安全地检索/收藏岗位、读 JD、撰写破冰话术并按授权发送或仅本地成稿。
  输入 = 简历/工作事实文件 + 一句求职目标，或仅一个检索词/目标句。Agent 据此生成 profile（检索词 + 硬排除 + 评分门槛 + 事实锚点），
  建立标准目标岗位库，在 BOSS 检索→过滤→书签入库，读 JD 写破冰话术（自检 gate），按用户授权直接发送或仅产出本地文档。
  强制走仿真人浏览器后端正门、真实光标、限速、撞墙停手、授权门控，绝不裸 CDP。适用于 WorkBuddy / OpenClaw / Codex / Claude Code 等任意 Agent。
---

# boss-zhipin-copilot

一个**通用、可配置、开源**的 BOSS 直聘求职 copilot。把你的「简历 + 求职目标」或「一句话目标」
沉淀成可复用的能力：自动建目标岗位画像与检索词、建立评分机制、建岗位库、在 BOSS 检索收藏、写破冰话术、按授权发送。

> 本 skill 是**应用层**；浏览器运行时由「仿真人浏览器后端」提供（经一套 BrowserDriver 契约即插即用）。
> 默认后端 [agent-browser-runtime](https://github.com/energypantry/agent-browser-runtime)（brs.js → broker → companion extension 真实光标）；
> 也支持 [OpenAI Codex](https://developers.openai.com/codex/app/chrome-extension) 托管模式（hosted，生成可粘贴的 @Chrome 提示词）。
> 所有浏览器动作只经后端正门真实光标执行，**绝不直连 CDP**。
> 后端契约与兼容清单见 `references/browser_backend.md`。

---

## 何时使用

- 用户要在 BOSS 直聘「找工作 / 建目标岗位库 / 批量收藏 / 写破冰话术 / 发消息」。
- 触发语示例：
  - 「帮我在 BOSS 找策略产品经理岗位」
  - 「根据我的简历生成求职画像和检索词」
  - 「收藏这几个岗位」「写破冰话术」「把这些岗发消息」

---

## 前置依赖（准入，缺一不可 → fail loud）

1. **仿真人浏览器后端已就绪**（关键准入）：本 skill 必须运行在「仿真人浏览器」之上，直接裸 CDP / 合成点击会触发 BOSS 反作弊（曾导致封号）。
   - **本地全自动（默认）**：安装 [agent-browser-runtime](https://github.com/energypantry/agent-browser-runtime)（Docker 三容器 + 经 noVNC 登录 BOSS），设 `BZC_BACKEND=brs`（默认）；
     `brs status` 须返回 `extensionConnected: true`。
   - **Codex 托管**：安装 OpenAI Codex 桌面端并启用 Chrome 插件，设 `BZC_BACKEND=codex`；浏览器由 Codex 托管，本 skill 只生成步骤提示词。
   - 未设置/缺失任何后端 → `common.sh` **fail-loud 并贴安装链接**，拒绝启动（详见 `references/browser_backend.md`）。
2. **后端路径/凭据**：`brs` 后端设 `BRS_JS`（或 `AGENT_BROWSER_RUNTIME_HOME`）；脚本自动探测常见路径。
3. **Python3 + pyyaml**：`pip install -r requirements.txt`。
4. **profile.yaml**：由本 skill 生成（见 Step 0）。
5. **目标岗位库 CSV**：由 `setup_library.sh` 生成（见 Step 1）。

---

## 安全纪律（灵魂，R1–R9 全文见 references/safety_rules.md）

- **R1** 只走仿真人浏览器后端正门（默认 brs.js），绝不裸 CDP / `Runtime.evaluate` 合成点击 / 查询串捷径。
- **R2** 只真实光标（`ui.click`/`ui.type`），禁合成点击。
- **R3** 限速强制：动作间隔 ≥`ACTION_INTERVAL_SECONDS`(5s)，每日收藏+开聊 ≤`DAILY_CAP`(100)。
- **R4** 撞墙即停：验证码/滑块 → 停手交人工，冷却 ≥24h，绝不恢复自动化（`exit 3`）。
- **R5** 授权门控：书签需批次授权；发消息需**每岗** `AUTHORIZED=1`。
  **门控对两种后端一致**：本地 `brs` 与托管 `codex`（hosted）的真实光标发送**都**必须 `AUTHORIZED=1`。
  > ⚠️ hosted 模式**未授权时绝不 emit 任何「发送」计划**——`bz_emit_plan` 在遇到发送动作且 `AUTHORIZED≠1` 时只产出浏览/读 JD/本地成稿步骤，绝不生成发送步骤（等价于 `exit 4` 拒绝）。
- **R6** 合并打开、避免无谓重开（同次任务合并书签+读JD+授权发送）。
- **R7** 预飞 1 岗跑通整条路径，再复制其余。
- **R8** 单 lease 连续 tab，批量不杀重启（burst）。
- **R9** 复核收敛：每步仅 1 个权威产物，最多 1 次交叉校验。
- 禁止频繁开关 tab / 本地打开 BOSS HTML / 盲坐标点击。

---

## 工作流

### Step 0 · 生成 / 校验 profile（输入契约）

- **入口 A（推荐）**：用户给「简历/工作事实文件 + 一句目标」
  → `python3 scripts/build_profile.py --goal "..." --resume 简历.md --out profile.yaml` 抽草稿；
  Agent 再复核补全 `hard_exclude` / `boost_keywords` / `fact_anchors`（依据 `references/profile_schema.md`）。
- **入口 B（最简）**：用户只给检索词 / 目标句 → 同上抽取；解析不出的维度（城市/薪资/经验）保守留空（=不限），
  必要时向用户追问 1 个最关键问题。
- **产物**：`profile.yaml`，后续所有脚本的唯一输入。

### Step 1 · 建 / 校验岗位库

- `bash scripts/setup_library.sh` 生成空 `target_library.csv`（或用 `$LIB_CSV` 指定）。
- 本库是检索 / 去重 / 入库的**唯一权威数据源**（`references/target_library_schema.md`）。

### Step 2 · 检索 → 过滤 → 书签入库

1. Agent 用仿真人浏览器后端真实 UI 在 BOSS 搜索框键入 `profile.search.queries` 每个词
   （真实光标 `bz_ui ... type` + 回车，**禁止** `?query=&city=&page=` 捷径 URL）。
2. 收集结果卡片 → 写入「待评估 CSV」（列：岗位名/公司名/城市/薪资/经验要求/公司阶段/公司规模/类型/URL 等）。
3. `python3 scripts/filter_library.py --profile profile.yaml --input 待评估.csv --library target_library.csv --out eval.json`
   → 应用硬排除 + 门槛 + 评分，输出通过清单并把通过项追加进库（状态=已收藏(感兴趣)）。
4. 对通过项逐个书签：`bash scripts/process_job.sh --url <岗URL> --bookmark`
   （或开一个 lease 复用：`--lease <id> --tab <id>`）。
5. 纪律：预飞 1 岗跑通选择器 → 其余同路径复用；批量间按 `references/cooldown_config.md` 间隔；撞墙即停。

### Step 3 · 读 JD / 招聘方（备话术）

- `bash scripts/process_job.sh --url <岗URL> --read-jd --out recruiter_jd.json`
  → 解析 `.job-boss-info .name`（真实招聘方，**非登录账号**）/ `.job-sec-text`（完整 JD）/ `.sider-company`。
- **输出契约（重要）**：`--read-jd` 现在写出的 `recruiter_jd.json` 是一个 **JSON 列表**
  `[{id, title, jd, recruiter, company}, ...]`（每岗一个元素；批量读 JD 时列表含多个元素）。
  > ⚠️ 旧 prose 曾暗示「单 dict」——已废止。消费方须按**列表**处理。
- 此 JSON 是后续话术的**唯一 JD 依据**。

### Step 4 · 写破冰话术（icebreaker writer，通用）

对每个目标岗位：

1. **JD 洞察**：1–2 句复述该 JD 的具体业务点，含 ≥3 个 JD 原文 distinctive 业务词（证明你读了它）。
2. **事实匹配**：从 `profile.fact_anchors` 取凭据，每段须「公司+动作+数字」、可溯源、**无编造**；
   AI/AIGC 只锚定具体场景，不暗示生产级大模型自研。
3. **话术**（≤200 字）：真实招聘方称呼 + JD 共鸣点 + 事实凭据 + 诚实边界（对硬门槛缺口主动点明可迁移能力）。
4. **自检 gate**：`python3 scripts/audit_icebreaker.py recruiter_jd.json 话术.md 事实库.md keys.json`
   要求 **JD≥90% 且 事实≥90%**（keys 字典由 Agent 为当批每岗写 `jd/fact` 锚点，写字典即强制精读 JD）。
   不达标 → 重写未命中岗。
   > **输入契约**：`recruiter_jd.json` 为 Step 3 产出的 **JSON 列表**；`audit_icebreaker.py` 按列表逐岗消费，
   > 并内置 `isinstance` 兜底——若传入的是单个 dict（旧格式/单岗）也能正常运行，不必手动包装成列表。
5. 完成即**停等用户审核**，不自动发送。

### Step 5 · 发送或仅本地（授权门控）

- 用户**每岗**显式授权（`AUTHORIZED=1`）
  → `bash scripts/process_job.sh --url <岗URL> --send --msg 话术.txt` 真实光标发送；
  发送前校验对话列表是否已有我方发起内容、称呼/岗位一致。
- 未授权 → 仅产出本地文档（如 `破冰沟通YYYYMMDD.md`），**不发送**。

### Step 6 · 扫描聊天列表（可选，去重 / 验收）

- `bash scripts/scan_chat.sh` 调 `zhipin-chat.extract.js` 取会话快照，
  与 `target_library.csv` 按 (name, company, role) 交叉比对，判已发 / 去重。**只读，不改状态**。

---

## 脚本清单

| 脚本 | 用途 |
|---|---|
| `scripts/common.sh` | 被 source：后端探测 + `source backends/$BZC_BACKEND.sh` + fail-loud + 撞墙/冷却助手 |
| `scripts/backends/brs.sh` | 默认后端：agent-browser-runtime（已实现，local） |
| `scripts/backends/codex.sh` | 托管后端：Codex Chrome 扩展（hosted，生成 @Chrome 提示词） |
| `scripts/backends/cloak.sh` | 候选后端：CloakBrowser（骨架+API 映射，待实现驱动） |
| `scripts/setup_library.sh` | 初始化空岗位库 CSV |
| `scripts/process_job.sh` | 单岗：书签 / 读JD / 发消息（可复用 lease；hosted 模式短路到 emit_plan） |
| `scripts/scan_chat.sh` | 扫描聊天列表（hosted 模式短路到 emit_plan） |
| `scripts/zhipin-chat.extract.js` | 聊天列表提取器（broker 端执行） |
| `scripts/build_profile.py` | 目标句 → profile 草稿 |
| `scripts/filter_library.py` | profile 驱动过滤 + 评分 + 入库 |
| `scripts/audit_icebreaker.py` | 破冰话术自检 gate（JD≥90% + 事实≥90%） |

---

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `BZC_BACKEND` | `brs` | 浏览器后端名：`brs`（默认，已实现）/ `codex`（hosted，已实现）/ `cloak`（仅骨架，**未实现驱动，勿用**，详见 `references/browser_backend.md`） |
| `BRS_JS` | 自动探测 | brs 后端：brs.js 路径 |
| `AGENT_BROWSER_RUNTIME_HOME` | — | brs 后端：agent-browser-runtime 根目录（辅助探测） |
| `NODE` / `PYTHON` | `node` / `python3` | 可执行 |
| `PROFILE` | `./profile.yaml` | profile 文件 |
| `LIB_CSV` | `./target_library.csv` | 岗位库 CSV |
| `WORK_DIR` | `./.work` | 中间产物目录 |
| `AUTHORIZED` | `0` | 发消息授权（=1 才允许） |
| `ACTION_INTERVAL_SECONDS` | `5` | 动作间隔下限 |
| `DAILY_CAP` | `100` | 每日收藏+开聊上限 |
| `BOOKMARK_COOLDOWN` / `SEND_COOLDOWN` | `8` / `20` | 书签/发送间隔 |

---

## 输出

- `profile.yaml`：求职画像（输入契约）。
- `target_library.csv`：目标岗位库（权威，去重主键=URL）。
- `.work/recruiter_jd.json` / `.work/eval.json` / `.work/chat_scan.json`：中间产物。
- `破冰沟通YYYYMMDD.md`：话术文档（未授权时本地成稿）。

---

## 错误处理

- 后端未就绪（`bz_status` 失败 / 缺 companion 扩展）→ 退出，不降级裸 CDP。
- 撞验证墙 → `exit 3`，停手交人工，冷却 ≥24h。
- 发送未授权 → `exit 4` 拒绝。
- 选择器漂移 → 回到 `references/boss_selectors.md` 复核，**禁止绕过**（绕过=误触/误判）。

---

## 与浏览器后端（BrowserDriver）的关系

本 skill 是 BOSS 直聘的「应用层」，浏览器由「仿真人浏览器后端」提供。
本 skill 所有浏览器动作只经后端正门真实光标执行，绝不直连 CDP。
后端是**可插拔**的：`common.sh` 按 `BZC_BACKEND` 加载 `scripts/backends/<name>.sh`，
每个后端实现 `references/browser_backend.md` 定义的 `bz_*` 契约（status/browse_start/browse_html/browse_end/ui/extract）。
当前：`brs`（默认，已实现）、`codex`（hosted，已实现）、`cloak`（骨架，待实现）。
运行时纪律见各后端自身文档（`references/` 不重复运行时细节）。
