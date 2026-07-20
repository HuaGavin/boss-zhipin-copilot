# boss-zhipin-copilot

> 一个通用、可配置、开源的 **BOSS 直聘求职 copilot** skill。
> 配合「仿真人浏览器后端」（默认 [agent-browser-runtime](https://github.com/energypantry/agent-browser-runtime)，亦支持 [OpenAI Codex](https://developers.openai.com/codex/app/chrome-extension) 托管等）的真实光标浏览器，
> 把「简历 + 求职目标」或「一句话目标」沉淀成可复用的能力：
> **自动生成目标岗位画像与检索词 → 建立评分机制 → 建岗位库 → 在 BOSS 检索/收藏 → 读 JD 写破冰话术 → 按授权发送或仅本地成稿。**

所有浏览器动作只经后端正门**真实光标**执行，强制限速、撞墙停手、授权门控，**绝不裸 CDP**。后端可插拔（BrowserDriver 契约，见 `references/browser_backend.md`）。
适用于 WorkBuddy / OpenClaw / Codex / Claude Code 等任意 Agent 产品。

---

## ✨ 特性

- **输入极简**：给「简历/工作事实 + 一句目标」，或只给一个检索词 / 目标句即可启动。
- **profile 驱动，零硬编码个人偏好**：检索词、硬排除类、评分门槛、破冰事实锚点全部来自 `profile.yaml`，
  仓库**不预置任何平台的默认排除列表**（避免误杀别人的机会）。
- **安全内建**：R1–R9 安全纪律全程兜底（真实光标、限速、撞墙冷却≥24h、授权门控、合并打开、预飞复制、单 lease、复核收敛）。
- **完整闭环**：检索 → 过滤 → 书签入库 → 读 JD → 写破冰话术（自检 gate）→ 按授权发送 / 本地成稿。
- **跨平台**：Bash 包 `brs.js`（CLI 编排）+ Python 做数据逻辑，符合 OpenClaw 生态主流约定。

---

## 🧱 架构

```
┌──────────────────────────────────────────────────────────┐
│  boss-zhipin-copilot (本 skill = 应用层)                    │
│  SKILL.md + scripts/ (bash+python) + references/ + assets/  │
│  对 BrowserDriver 契约 (bz_*) 编程，不直接耦合某个浏览器     │
└───────────────────────────┬──────────────────────────────┘
                              │ BZC_BACKEND 选择后端
              ┌───────────────┼────────────────┐
              ▼               ▼                ▼
       ┌────────────┐  ┌──────────────┐  ┌────────────┐
       │ brs (默认)  │  │ codex (hosted)│  │ cloak(骨架) │  ...可扩展
       │ agent-      │  │ Codex Chrome  │  │ CloakBrowser│
       │ browser-    │  │ 扩展 @Chrome  │  │ 隐身Chromium│
       │ runtime     │  │ 提示词        │  │            │
       └────────────┘  └──────────────┘  └────────────┘
  全部「仿真人浏览器」：真实光标 / 持久登录态 / 反检测，绝不裸 CDP
```

---

## 📋 前置依赖

> ⚠️ **本 skill 必须运行在「仿真人浏览器」之上**。没有它 → 脚本启动时 **fail-loud 并贴安装链接**，拒绝执行（直接裸 CDP / 合成点击会触发 BOSS 反作弊，曾导致封号）。

1. **仿真人浏览器后端（二选一）**：
   - **本地全自动（默认 `brs`）**：部署 [agent-browser-runtime](https://github.com/energypantry/agent-browser-runtime)（Docker 三容器 + 经 noVNC 登录 BOSS）。
     `brs status` 须返回 `extensionConnected: true`。设 `BZC_BACKEND=brs`（默认）。
   - **Codex 托管（`codex`）**：安装 OpenAI Codex 桌面端并启用 Chrome 插件（[官方文档](https://developers.openai.com/codex/app/chrome-extension)）。
     设 `BZC_BACKEND=codex`；浏览器由 Codex 托管，本 skill 只生成可粘贴的 `@Chrome` 步骤提示词，非浏览器逻辑照常本地跑。
   - 其他候选（CloakBrowser 等）见 `references/browser_backend.md` 支持矩阵。
2. **Node.js** 与 **Python 3**（在 `PATH` 上，或用 `NODE` / `PYTHON` 环境变量指定）。
3. **pyyaml**：`pip install -r requirements.txt`。

---

## 🚀 安装

### 作为 Agent skill 安装（WorkBuddy / OpenClaw）

```bash
# 克隆（或下载 ZIP）
git clone <你的仓库地址> boss-zhipin-copilot

# WorkBuddy: 拷到项目级或用户级 skills 目录
cp -r boss-zhipin-copilot ~/.workbuddy/skills/        # 用户级
# 或  K:/求职/求职应聘2026/求职Buddy/.workbuddy/skills/   # 项目级

# OpenClaw: 拷到 skills 目录
cp -r boss-zhipin-copilot ~/.openclaw/skills/

# 安装 Python 依赖
cd boss-zhipin-copilot
pip install -r requirements.txt
```

> skill 是目录即生效，无需注册命令。下次会话 Agent 会自动加载。

### 选择浏览器后端（关键）

```bash
# 默认（本地全自动）：agent-browser-runtime
export BZC_BACKEND=brs
export BRS_JS="/绝对路径/agent-browser-runtime/cli/brs.js"   # 或 AGENT_BROWSER_RUNTIME_HOME
# 或 用 Codex 托管浏览器（生成 @Chrome 提示词，由 Codex 执行）
export BZC_BACKEND=codex
```

脚本会自动探测 `brs.js` 常见路径；未设置/缺失任何后端会 **fail-loud** 并提示安装链接。
支持的完整清单与如何新增后端见 `references/browser_backend.md`。

---

## 🎯 快速开始

```bash
cd boss-zhipin-copilot

# 0) 生成求职画像（从一句目标 + 可选简历）
python3 scripts/build_profile.py \
  --goal "我想找要求5年以上经验、月薪4万元以上的策略产品经理岗位（北京）" \
  --resume 我的简历.md --out profile.yaml
# → Agent 复核补全 hard_exclude / boost_keywords / fact_anchors

# 1) 初始化岗位库
bash scripts/setup_library.sh

# 2) 在 BOSS 用真实 UI 搜索 profile.search.queries，收集结果卡片到 待评估.csv
#    （Agent 执行；禁止拼接搜索 URL 捷径）
#    然后过滤 + 评分 + 入库：
python3 scripts/filter_library.py \
  --profile profile.yaml --input 待评估.csv \
  --library target_library.csv --out .work/eval.json

# 3) 对每个通过项书签（真实光标）
bash scripts/process_job.sh --url <岗位URL> --bookmark

# 4) 读 JD（备话术）
bash scripts/process_job.sh --url <岗位URL> --read-jd --out .work/recruiter_jd.json

# 5) 写破冰话术 + 自检 gate（详见 SKILL.md Step 4）
python3 scripts/audit_icebreaker.py .work/recruiter_jd.json 话术.md 事实库.md keys.json

# 6) 用户授权后发送（或仅本地成稿）
AUTHORIZED=1 bash scripts/process_job.sh --url <岗位URL> --send --msg 话术.txt
```

完整工作流、纪律与脚本参数见 **[SKILL.md](SKILL.md)**。

---

## ⚙️ 核心配置：profile.yaml

`profile.yaml` 是整个 skill 的唯一输入契约。结构（完整说明见 `references/profile_schema.md`）：

```yaml
search:
  city: "北京"
  queries: ["策略产品经理 北京"]
thresholds:
  salary_floor: 40000      # 月薪下限（元），0=不限
  seniority_years: 5       # 经验年限下限，0=不限
hard_exclude:              # 命中任一即不入库（只列你确实无经验的类）
  - category: "广告/IAA"
    keywords: ["IAA", "广告变现", "买量"]
boost_keywords: ["增长", "留存", "C端", "0-1", "Agent"]
fact_anchors:              # 破冰事实锚点，必须真实可溯源
  - anchor: "用户增长"
    evidence: "某内容平台渠道增长，次留提升 3%"
```

仓库自带：
- `assets/profile_template.yaml`：空模板，复制为 `profile.yaml` 填写。
- `assets/example_profile.yaml`：**虚构示例**（候选人「李明」），演示 schema，非真实数据。
- `assets/target_library_template.csv`：空库模板（表头）。

---

## 🔒 安全

- 只走 `brs.js` 正门；真实光标；限速（间隔≥5s、日≤100）；撞验证码/滑块立即停手冷却≥24h。
- 书签需批次授权；发消息需**每岗** `AUTHORIZED=1`。未授权只浏览/读/本地成稿。
- 详细纪律见 `references/safety_rules.md`（R1–R9）与 `references/cooldown_config.md`。

---

## 📁 目录结构

```
boss-zhipin-copilot/
├── SKILL.md                      # 主入口：工作流 + 安全纪律
├── README.md                     # 本文件
├── LICENSE                       # MIT
├── requirements.txt              # pyyaml
├── references/
│   ├── profile_schema.md         # profile.yaml 字段定义
│   ├── target_library_schema.md  # 岗位库 CSV schema
│   ├── boss_selectors.md         # BOSS 选择器（需实况校验）
│   ├── safety_rules.md           # R1–R9 安全纪律
│   └── cooldown_config.md        # 限速配置
├── scripts/
│   ├── common.sh                 # 后端探测 + source backends/$BZC_BACKEND.sh + fail-loud + 撞墙/冷却
│   ├── backends/
│   │   ├── brs.sh                # 默认后端：agent-browser-runtime（已实现）
│   │   ├── codex.sh              # 托管后端：Codex Chrome 扩展（已实现，生成提示词）
│   │   └── cloak.sh              # 候选后端：CloakBrowser（骨架+API 映射）
│   ├── setup_library.sh          # 初始化空库
│   ├── process_job.sh            # 单岗：书签/读JD/发消息（hosted 短路到 emit_plan）
│   ├── scan_chat.sh              # 扫描聊天列表（hosted 短路到 emit_plan）
│   ├── zhipin-chat.extract.js    # 聊天列表提取器
│   ├── build_profile.py          # 目标句→profile 草稿
│   ├── filter_library.py         # 过滤+评分+入库
│   └── audit_icebreaker.py       # 话术自检 gate
└── assets/
    ├── profile_template.yaml
    ├── example_profile.yaml      # 虚构示例
    └── target_library_template.csv
```

---

## 🤝 贡献

欢迎 PR。新增能力请保持：
- 浏览器动作只经后端正门（BrowserDriver 契约），不引入裸 CDP / 合成点击。
- 个人偏好走 `profile.yaml`，不在脚本硬编码。
- 新增浏览器后端：在 `scripts/backends/` 实现 `bz_*` 契约并在 `references/browser_backend.md` 补一行（见该文件「如何新增后端」）。
- 新增脚本遵循 OpenClaw 约定（描述性命名、动词前缀、环境变量而非硬编码路径、幂等）。

---

## 📄 License

[MIT](LICENSE)
