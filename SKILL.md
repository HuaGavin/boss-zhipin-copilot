---
name: boss-zhipin-copilot
description: >-
  通用 BOSS 直聘求职 copilot：配合仿真人浏览器后端用真实光标安全检索/收藏岗位、读 JD、写破冰话术并按授权发送。强制走后端正门、真实光标、限速、撞墙停手、授权门控，绝不裸 CDP。四类资产（脚本/选择器/页面/点位）一律优先复用 skill 内置，禁止现写等价脚本或重猜选择器；新建前必查 script_catalog.md + boss_selectors.md。
---

通用、可配置、开源的 BOSS 直聘求职 copilot：把「简历 + 求职目标」沉淀为可复用能力——自动建岗位画像与检索词、建评分机制、建岗位库、检索收藏、写破冰话术、按授权发送。

> 🔌 **应用层架构**：浏览器运行时由「仿真人浏览器后端」经 `bz_*` 契约即插即用提供。默认 [agent-browser-runtime](https://github.com/energypantry/agent-browser-runtime)（真实光标）；亦支持 [Codex](https://developers.openai.com/codex/app/chrome-extension) 托管（生成可粘贴提示词）。**所有浏览器动作只经后端正门真实光标执行，绝不直连 CDP。**

**流水线**：`简历/目标` → `profile.yaml` → 检索·过滤·入库 → 读 JD → 写话术（自检 gate）→ 授权发送 / 仅本地成稿

> 🛑 **最高优先级前置门控**：任何写脚本 / 猜选择器·页面·点位前，**必须先 `Read references/script_catalog.md` + `references/boss_selectors.md`**（统一原则见下方「🛑 优先复用与增量更新」）。已有对应项时现写即违规——立即停用，改用内置。复用优先于一切。

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

## 🛑 优先复用与增量更新（Reuse-First & Incremental Update · 最高优先级）

> 本 skill 预建了全部资产（**脚本 / 选择器 / 页面 / 点位**），目的就是让 Agent 不再现写或盲猜——那既是误差之源也是低效之源。四类资产统一遵循同一原则：

- **① 复用优先**：动手前先查已有资产——
  - 脚本 → `references/script_catalog.md`（任务 → 内置命令精确映射）
  - 选择器 / 页面 / 点位 → `references/boss_selectors.md`
  - 凡已有对应条目，**必须直接复用**：禁止重写等价脚本、禁止重猜选择器、禁止盲试页面 URL、禁止自造点位。
- **② 发现错误 → 就地更新**：已有条目实测漂移 / 失效，**直接改对应条目**（fix-in-place）惠及所有未来运行；**禁止绕过**（绕过 = 误触 / 误判，见 R1）。
- **③ 发现新内容 → 补进对应位置**：
  - 新脚本 → 收编 `scripts/` + 登记 `script_catalog.md`
  - 新选择器 / 页面 / 点位 → 补进 `boss_selectors.md` 对应节（标注「首次校验」）
- **④ 受控逃逸阀**：仅当确属全新、与现有资产无重叠才新建；新建必登记；**无法说清「为何现有不适用」时，默认就地改，不得新建**。任务执行中**禁止临时改写 `process_job.sh` 等内置脚本绕过门控**——源码修改走 skill 维护流程（改后 commit）。

## 工作流
### Step 0 · 生成 / 校验 profile + 解析求职意图
- `python3 scripts/build_profile.py --goal "..." [--resume 简历.md] --out profile.yaml` 抽草稿；Agent 复核补全 `hard_exclude` / `boost_keywords` / `fact_anchors`（依据 `references/profile_schema.md`）。解析不出的维度保守留空（=不限），必要时追问 1 个关键问题。→ **产物 `profile.yaml`**（后续唯一输入）。（复用 `build_profile.py`，禁现写等价脚本）
- **主动解析求职意图（长期能力）**：用户常以自然语言提需求（如"想找一家 B 轮以上的中型公司做后端开发""北京全职20k以上5年经验"）。这类隐含的筛选条件**必须由 `scripts/intent_filters.py` 自动识别并映射到 BOSS 搜索页筛选器**，**优先在搜索阶段应用**，缩小结果范围，避免下游读大量不符岗 JD。用法：
  - `python3 scripts/intent_filters.py parse "自然语言" [--profile profile.yaml]` → 解析出 FilterSpec（意图覆盖 profile 默认）
  - `python3 scripts/intent_filters.py build --profile profile.yaml [--intent "文本"] [--scale 302,303] [--exp 106] ...` → 合并 profile+意图+显式维度覆盖 → 最终 FilterSpec
  - 编码映射与点位见 `references/boss_selectors.md` 五「结果页筛选器」（六维度全覆盖：公司规模/融资阶段/工作经验/学历要求/薪资待遇/求职类型）。**复用内置，禁现写等价解析。**

### Step 1 · 建 / 校验岗位库
`bash scripts/setup_library.sh` 生成空 `target_library.csv`（`$LIB_CSV` 可指定）。本库是检索/去重/入库的**唯一权威数据源**（`references/target_library_schema.md`）。（复用 `setup_library.sh`，禁现写）

### Step 2 · 检索（先筛选）→ 过滤 → 书签入库
> **🔒 流程铁律：筛选优先于后续操作。** 先按筛选条件在「搜索结果页」源头过滤 → 再对过滤后的岗位列表执行收集/详情抓取/匹配分析。绝不让未过筛的岗位进入下游（读 JD / 写话术 / 入库），那会成倍浪费真实光标动作。

1. **检索收集（源头筛选 + 只读）**（复用内置，禁自写）：
   `bash scripts/search_jobs.sh --profile profile.yaml --out .work/candidates.csv [--intent "自然语言意图"] [--scale "302,303"] [--stage 804,805] [--exp 106] [--degree 203] [--salary 406] [--jobtype 1901]`
   - 查询词取自 `profile.search.queries`（或 `--queries "词1,词2"`）；走 `bz_*` 真实光标、复用同 tab、**禁 `?query=&city=&page=` 捷径**。
   - **六维度筛选在搜索结果页源头应用（核心优化）**：搜索框下方 hover 出下拉、复选（点位/编码见 `boss_selectors.md` 五）。筛选来源优先级：① `profile.thresholds` 默认（scale_min/max、salary_floor、seniority_years 自动推导）→ ② `--intent "文本"` 自动解析隐含条件（如"B轮以上中型公司"）覆盖同名维度 → ③ 显式 `--scale/--stage/--exp/--degree/--salary/--jobtype` 最高优先级覆盖。**在源头筛掉不符岗，比读 JD 详情页后再筛高效得多**（实测：下游 JD 阅读量可降 30–50%）。
   - 产 `candidates.csv`（列：岗位名/公司名/城市/经验要求/URL）。⚠️ **无薪资列**——卡片薪资被字体反爬混淆，须 Step 3 从 JD 详情页取。
2. **过滤打分去重**（复用 `filter_library.py`，禁现写）：`python3 scripts/filter_library.py --profile profile.yaml --input .work/candidates.csv --out .work/eval.json`
   - **省略 `--library` = 只读候选清单、不入库**；通过项在 `eval.json.passed`，Top-N 自行按「评分」截断。
   - 确需入库再加 `--library target_library.csv`（通过项追加，状态=已收藏(感兴趣)，按 URL 去重）。
3. 逐岗书签：`AUTHORIZED=1 bash scripts/process_job.sh --url <岗URL> --bookmark`（复用 lease：`--lease <id> --tab <id>`）。
   - 核对实际收藏：个人中心「感兴趣」tab（`https://www.zhipin.com/web/geek/recommend`，见 `boss_selectors.md` 六，**只读**，勿在此页改状态）。列表页**每卡另有 `a.btn-startchat` 可直接开聊**，卡片 DOM 结构见 `boss_selectors.md` 六「收藏列表卡片 DOM」。
4. 预飞 1 岗跑通选择器 → 同路径复用；按 `references/cooldown_config.md` 间隔；撞墙即停。

### Step 3 · 读 JD / 招聘方
单岗：`bash scripts/process_job.sh --url <岗URL> --read-jd --out recruiter_jd.json`（`<岗URL>` 用 `https://www.zhipin.com/job_detail/<jid>.html`，**去掉 `?securityId=...`**，见 `boss_selectors.md` 六/三）→ 解析 `.job-boss-info .name`（真实招聘方，**非登录账号**）/ `.job-sec-text`（完整 JD）/ `.sider-company`。读 JD 前用 `bz_wait $BZ_LEASE $BZ_TAB job-sec-text` 等渲染就绪，避免空串（见 `safety_rules.md` 十）。
**批量（N 岗）禁止另写 `read_jd_batch.py`** → shell 循环复用单岗命令（白赚真实光标 + 撞墙检查 + 解析）：
`for u in $(cat urls.txt); do bash scripts/process_job.sh --url "$u" --read-jd --out .work/jd_$((++n)).json; done`
**输出契约**：每岗产出单元素 JSON 列表 `[{id,title,jd,recruiter,company}]`；合并为批量数组即话术**唯一 JD 依据**（见 `audit_icebreaker.py` 用法）。

### Step 4 · 写破冰话术（通用）
1. **JD 洞察**：1–2 句复述具体业务点，含 ≥3 个 JD 原文 distinctive 词。
2. **事实匹配**：从 `profile.fact_anchors` 取凭据，每段「公司+动作+数字」、可溯源、无编造。
3. **话术**（≤200 字）：真实招聘方称呼 + JD 共鸣 + 事实凭据 + 诚实边界。
4. **自检 gate**：`python3 scripts/audit_icebreaker.py recruiter_jd.json 话术.md 事实库.md keys.json` 要求 **JD≥90% 且 事实≥90%**（keys 由 Agent 为每岗写 `jd/fact` 锚点，写即强制精读）。不达标 → 重写。
5. 完成即**停等用户审核**，不自动发送。

### Step 5 · 发送或仅本地（授权门控）
- 用户**每岗**显式授权（`AUTHORIZED=1`）→ `bash scripts/process_job.sh --url <岗URL> --send --msg 话术.txt` 真实光标发送（发送前校验对话列表已有我方内容、称呼/岗位一致）。
- ⚠️ **须前台、逐岗、人工实时在环执行，禁止委托无人值守后台批量跑**（即便已授权）：撞墙无人接手 / 无法中断 / 会话结束即死。仅只读操作可后台（见 `safety_rules.md` 红线）。
- 未授权 → 仅产出本地文档（如 `破冰沟通YYYYMMDD.md`），**不发送**。

### Step 6 · 扫描聊天列表（可选）
`bash scripts/scan_chat.sh` 调 `zhipin-chat.extract.js` 取快照，与 `target_library.csv` 按 (name,company,role) 交叉比对，判已发/去重。**只读，不改状态**。（复用，禁现写）

---

## 脚本清单
| 脚本 | 用途 |
|---|---|
| `scripts/common.sh` | 被 source：后端探测 + `source backends/$BZC_BACKEND.sh` + fail-loud + 撞墙/冷却助手 |
| `scripts/backends/brs.sh` | 默认后端：agent-browser-runtime（local，已实现） |
| `scripts/backends/codex.sh` | 托管后端：Codex Chrome 扩展（hosted，生成 @Chrome 提示词） |
| `scripts/backends/cloak.sh` | 候选后端：CloakBrowser（骨架，待实现，勿用） |
| `scripts/setup_library.sh` | 初始化空岗位库 CSV |
| `scripts/search_jobs.sh` | 多词检索：复用同 tab、只读收集结果卡 → `candidates.csv`（hosted 短路 emit_plan） |
| `scripts/parse_search.py` | 搜索结果卡片解析（search_jobs 内部调用；不含薪资） |
| `scripts/process_job.sh` | 单岗：书签/读JD/发消息（可复用 lease；hosted 短路到 emit_plan） |
| `scripts/scan_chat.sh` | 扫描聊天列表（hosted 短路到 emit_plan） |
| `scripts/zhipin-chat.extract.js` | 聊天列表提取器（broker 端执行） |
| `scripts/build_profile.py` | 目标句 → profile 草稿 |
| `scripts/filter_library.py` | profile 驱动过滤 + 评分 + 入库 |
| `scripts/audit_icebreaker.py` | 破冰话术自检 gate（JD≥90% + 事实≥90%） |
| `scripts/parse_job.py` | 读JD 的 HTML DOM 解析（process_job 内部调用） |

> 📌 **复用前必查 `references/script_catalog.md`**：任务 → 内置脚本精确命令映射 + 反模式清单。凡表中有脚本必须复用，禁止重写（见上方「🛑 优先复用与增量更新」）。

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
| `COOLDOWN_JITTER` | `3` | 间隔随机抖动幅度（±秒，防机器特征） |
| `BACKOFF_MAX` | `60` | 软限流指数退避上限（秒） |
| `DAILY_CAP` | `100` | 每日收藏+开聊上限 |
| `BOOKMARK_COOLDOWN` / `SEND_COOLDOWN` | `8` / `20` | 书签/发送间隔 |

---

## 错误处理
- 失败分类与「异常 → 动作」完整表见 `references/safety_rules.md` 十（解析空/选择器漂移/撞墙/软限流/部分加载/网络/凭证未连接/日上限）。
- 后端未就绪（`bz_status` 失败 / 缺 companion 扩展 / 解析失败）→ `exit 2`（runtime/companion 未就绪，不降级裸 CDP）。
- 撞验证墙 → `exit 3`，停手交人工，冷却 ≥24h。
- 发送/书签未授权 → `exit 4` 拒绝。
- 单日改状态动作达 `DAILY_CAP` 上限 → `exit 5` 停手（R3）。
- 发送后话术仍在输入框草稿态（未真正发出）→ `exit 7`（见 `process_job.sh` 严格送达判定）。
- 选择器漂移 → 回 `references/boss_selectors.md` 复核，**禁止绕过**（绕过=误触/误判）。

---

## 产物文件
- `profile.yaml`：求职画像（输入契约）。
- `target_library.csv`：目标岗位库（权威，去重主键=BOSS URL 的 `job_detail/<jid>`；辅助键=(公司名+岗位名+BOSS称呼)，防同公司同岗不同招聘方被误并）。
- `.work/recruiter_jd.json` / `.work/eval.json` / `.work/chat_scan.json`：中间产物。
- `破冰沟通YYYYMMDD.md`：话术文档（未授权时本地成稿）。
