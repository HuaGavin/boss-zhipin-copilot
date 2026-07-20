---
name: boss-zhipin-copilot
description: >-
  通用开源 BOSS 直聘求职 copilot。配合仿真人浏览器后端（默认 agent-browser-runtime，亦支持 Codex 托管）用真实光标安全地检索/收藏岗位、读 JD、写破冰话术，并按授权发送或仅本地成稿。
  输入 = 简历/工作事实文件 + 求职目标，或仅一句目标句；输出 = profile（检索词+硬排除+评分门槛+事实锚点）、目标岗位库、破冰话术。强制走后端正门、真实光标、限速、撞墙停手、授权门控，绝不裸 CDP。
---

# boss-zhipin-copilot

通用、可配置、开源的 BOSS 直聘求职 copilot：把「简历 + 求职目标」沉淀为可复用能力——自动建岗位画像与检索词、建评分机制、建岗位库、检索收藏、写破冰话术、按授权发送。

> 🔌 **应用层架构**：浏览器运行时由「仿真人浏览器后端」经 `bz_*` 契约即插即用提供。默认 [agent-browser-runtime](https://github.com/energypantry/agent-browser-runtime)（真实光标）；亦支持 [Codex](https://developers.openai.com/codex/app/chrome-extension) 托管（生成可粘贴提示词）。**所有浏览器动作只经后端正门真实光标执行，绝不直连 CDP。**

**流水线**：`简历/目标` → `profile.yaml` → 检索·过滤·入库 → 读 JD → 写话术（自检 gate）→ 授权发送 / 仅本地成稿

---

## 何时使用
- 用户在 BOSS 直聘「找工作 / 建目标岗位库 / 批量收藏 / 写破冰话术 / 发消息」。
- 触发语：「帮我在 BOSS 找策略产品经理」「根据简历生成求职画像和检索词」「收藏这几个岗位」「写破冰话术」「把这些岗发消息」。

---

## 前置依赖（缺一不可 → fail loud）
1. **仿真人浏览器后端就绪**（关键准入，裸 CDP 曾致封号）：
   - 本地（默认）：部署 [agent-browser-runtime](https://github.com/energypantry/agent-browser-runtime)，`BZC_BACKEND=brs`（默认），`brs status` 须 `extensionConnected: true`。
   - Codex 托管：`BZC_BACKEND=codex`，由 Codex 托管浏览器，本 skill 仅生成步骤提示词。
   - 缺失 → `common.sh` fail-loud 并贴安装链接。契约见 `references/browser_backend.md`。
2. **Python3 + pyyaml**：`pip install -r requirements.txt`。
3. **profile.yaml / 岗位库 CSV**：由本 skill 在工作流 Step 0/1 自动生成（无需预置）。

---

## 安全纪律（灵魂 · 全文见 references/safety_rules.md）
- **R1** 只走仿真人浏览器后端正门，绝不裸 CDP / `Runtime.evaluate` / 查询串捷径。
- **R2** 只用真实光标（`ui.click`/`ui.type`），禁合成点击。
- **R3** 限速：动作间隔 ≥`ACTION_INTERVAL_SECONDS`(5s)；每日收藏+开聊 ≤`DAILY_CAP`(100)。
- **R4** 撞墙即停：验证码/滑块 → `exit 3`，停手交人工，冷却 ≥24h，绝不恢复自动化。
- **R5** 授权门控：书签需批次授权；发消息需**每岗** `AUTHORIZED=1`。门控在 `process_job.sh` 顶部早于 hosted 短路执行，未授权带 `--send`/`--bookmark` 直接 `exit 4`。
- **R6** 合并打开，避免无谓重开（同次任务合并书签+读JD+授权发送）。
- **R7** 预飞 1 岗跑通整条路径，再复制其余。
- **R8** 单 lease 连续 tab，批量不杀重启（burst）。
- **R9** 复核收敛：每步仅 1 个权威产物，最多 1 次交叉校验。
- ⚠️ 禁止频繁开关 tab / 本地打开 BOSS HTML / 盲坐标点击。

---

## 工作流
### Step 0 · 生成 / 校验 profile
`python3 scripts/build_profile.py --goal "..." [--resume 简历.md] --out profile.yaml` 抽草稿；Agent 复核补全 `hard_exclude` / `boost_keywords` / `fact_anchors`（依据 `references/profile_schema.md`）。解析不出的维度保守留空（=不限），必要时追问 1 个关键问题。→ **产物 `profile.yaml`**（后续唯一输入）。

### Step 1 · 建 / 校验岗位库
`bash scripts/setup_library.sh` 生成空 `target_library.csv`（`$LIB_CSV` 可指定）。本库是检索/去重/入库的**唯一权威数据源**（`references/target_library_schema.md`）。

### Step 2 · 检索 → 过滤 → 书签入库
1. 真实 UI 在 BOSS 搜索框键入 `profile.search.queries` 每个词（`bz_ui ... type` + 回车，**禁止** `?query=&city=&page=` 捷径）。
2. 收集结果卡 → 写「待评估 CSV」（列：岗位名/公司名/城市/薪资/经验要求/公司阶段/规模/类型/URL）。
3. `python3 scripts/filter_library.py --profile profile.yaml --input 待评估.csv --library target_library.csv --out eval.json` → 硬排除+门槛+评分，通过项追加进库（状态=已收藏(感兴趣)）。
4. 逐岗书签：`bash scripts/process_job.sh --url <岗URL> --bookmark`（复用 lease：`--lease <id> --tab <id>`）。
5. 预飞 1 岗跑通选择器 → 同路径复用；按 `references/cooldown_config.md` 间隔；撞墙即停。

### Step 3 · 读 JD / 招聘方
`bash scripts/process_job.sh --url <岗URL> --read-jd --out recruiter_jd.json` → 解析 `.job-boss-info .name`（真实招聘方，**非登录账号**）/ `.job-sec-text`（完整 JD）/ `.sider-company`。
**输出契约**：`recruiter_jd.json` 为 **JSON 列表** `[{id,title,jd,recruiter,company}]`（批量含多元素）；兼容单 dict。此为话术**唯一 JD 依据**。

### Step 4 · 写破冰话术（通用）
1. **JD 洞察**：1–2 句复述具体业务点，含 ≥3 个 JD 原文 distinctive 词。
2. **事实匹配**：从 `profile.fact_anchors` 取凭据，每段「公司+动作+数字」、可溯源、无编造。
3. **话术**（≤200 字）：真实招聘方称呼 + JD 共鸣 + 事实凭据 + 诚实边界。
4. **自检 gate**：`python3 scripts/audit_icebreaker.py recruiter_jd.json 话术.md 事实库.md keys.json` 要求 **JD≥90% 且 事实≥90%**（keys 由 Agent 为每岗写 `jd/fact` 锚点，写即强制精读）。不达标 → 重写。
5. 完成即**停等用户审核**，不自动发送。

### Step 5 · 发送或仅本地（授权门控）
- 用户**每岗**显式授权（`AUTHORIZED=1`）→ `bash scripts/process_job.sh --url <岗URL> --send --msg 话术.txt` 真实光标发送（发送前校验对话列表已有我方内容、称呼/岗位一致）。
- 未授权 → 仅产出本地文档（如 `破冰沟通YYYYMMDD.md`），**不发送**。

### Step 6 · 扫描聊天列表（可选）
`bash scripts/scan_chat.sh` 调 `zhipin-chat.extract.js` 取快照，与 `target_library.csv` 按 (name,company,role) 交叉比对，判已发/去重。**只读，不改状态**。

---

## 脚本清单
| 脚本 | 用途 |
|---|---|
| `scripts/common.sh` | 被 source：后端探测 + `source backends/$BZC_BACKEND.sh` + fail-loud + 撞墙/冷却助手 |
| `scripts/backends/brs.sh` | 默认后端：agent-browser-runtime（local，已实现） |
| `scripts/backends/codex.sh` | 托管后端：Codex Chrome 扩展（hosted，生成 @Chrome 提示词） |
| `scripts/backends/cloak.sh` | 候选后端：CloakBrowser（骨架，待实现，勿用） |
| `scripts/setup_library.sh` | 初始化空岗位库 CSV |
| `scripts/process_job.sh` | 单岗：书签/读JD/发消息（可复用 lease；hosted 短路到 emit_plan） |
| `scripts/scan_chat.sh` | 扫描聊天列表（hosted 短路到 emit_plan） |
| `scripts/zhipin-chat.extract.js` | 聊天列表提取器（broker 端执行） |
| `scripts/build_profile.py` | 目标句 → profile 草稿 |
| `scripts/filter_library.py` | profile 驱动过滤 + 评分 + 入库 |
| `scripts/audit_icebreaker.py` | 破冰话术自检 gate（JD≥90% + 事实≥90%） |
| `scripts/parse_job.py` | 读JD 的 HTML DOM 解析（process_job 内部调用） |

---

## 环境变量
| 变量 | 默认 | 说明 |
|---|---|---|
| `BZC_BACKEND` | `brs` | 后端：`brs`(默认已实现)/`codex`(hosted已实现)/`cloak`(仅骨架) |
| `BRS_JS` | 自动探测 | brs.js 路径（或 `AGENT_BROWSER_RUNTIME_HOME` 辅助） |
| `NODE` / `PYTHON` | `node` / `python3` | 可执行 |
| `PROFILE` | `./profile.yaml` | profile 文件 |
| `LIB_CSV` | `./target_library.csv` | 岗位库 CSV |
| `WORK_DIR` | `./.work` | 中间产物目录 |
| `AUTHORIZED` | `0` | 发消息/书签授权（=1 才允许） |
| `ACTION_INTERVAL_SECONDS` | `5` | 动作间隔下限 |
| `DAILY_CAP` | `100` | 每日收藏+开聊上限 |
| `BOOKMARK_COOLDOWN` / `SEND_COOLDOWN` | `8` / `20` | 书签/发送间隔 |

---

## 错误处理
- 后端未就绪（`bz_status` 失败 / 缺 companion 扩展）→ 退出，不降级裸 CDP。
- 撞验证墙 → `exit 3`，停手交人工，冷却 ≥24h。
- 发送/书签未授权 → `exit 4` 拒绝。
- 选择器漂移 → 回 `references/boss_selectors.md` 复核，**禁止绕过**（绕过=误触/误判）。

---

## 产物文件
- `profile.yaml`：求职画像（输入契约）。
- `target_library.csv`：目标岗位库（权威，去重主键=URL）。
- `.work/recruiter_jd.json` / `.work/eval.json` / `.work/chat_scan.json`：中间产物。
- `破冰沟通YYYYMMDD.md`：话术文档（未授权时本地成稿）。
