# 脚本复用目录（Reuse Catalog · 脚本部分）— boss-zhipin-copilot

> **本文件是「任务 → 该复用的内置脚本」唯一权威映射**（四类资产之一）。任何 Agent 写脚本前**必须先查本表**。
> 遵循 SKILL.md「🛑 优先复用与增量更新」：表中有则必须复用；发现错误就地改；确属全新才新建并收编 `scripts/` + 登记本表。
> 选择器 / 页面 / 点位不在此表，索引在 `references/boss_selectors.md`，适用同一原则。

---

## 一、任务 → 精确命令映射

| 你要做的事 | 复用这个（精确命令） | 说明 / 注意 |
|---|---|---|
| 生成求职画像草稿 | `python3 scripts/build_profile.py --goal "..." [--resume 简历.md] --out profile.yaml` | 草稿，Agent 必须复核补全 `hard_exclude` / `boost_keywords` / `fact_anchors` |
| 初始化空岗位库 | `bash scripts/setup_library.sh`（可用 `LIB_CSV` 指定路径） | 按模板生成 `target_library.csv` |
| **多词检索 + 收集结果卡（只读）** | `bash scripts/search_jobs.sh --profile profile.yaml --out .work/candidates.csv` | 查询词取自 `profile.search.queries`（或 `--queries "a,b"`）；走 `bz_*` 真实光标、复用同 tab；产 `candidates.csv`（岗位名/公司名/城市/经验要求/URL，**无薪资**）。内部调 `parse_search.py` |
| **过滤 + 打分 + 去重（只读候选清单，不动账号）** | `python3 scripts/filter_library.py --profile profile.yaml --input 待评估.csv --out .work/eval.json` | **省略 `--library` = 不入库、只产出 `eval.json`（`passed`/`rejected` + 评分）**；需 Top-N 自行按「评分」截断排序 |
| **过滤 + 打分 + 去重 + 入库** | `... --library target_library.csv` | 通过项追加进库（状态=已收藏(感兴趣)），按 URL 去重 |
| 单岗读 JD / 招聘方 | `bash scripts/process_job.sh --url <url> --read-jd --out .work/recruiter_jd.json` | 内部调 `parse_job.py`；真实招聘方 = `.job-boss-info .name`（**非 `user-nav` 本人**） |
| **批量读 JD（N 个）** | `for u in $(cat urls.txt); do bash scripts/process_job.sh --url "$u" --read-jd --out .work/jd_$((++n)).json; done` | **禁止另写 `read_jd_batch.py`**；循环复用单岗命令，白赚真实光标 + 撞墙检查 + 解析 |
| 单岗书签（改状态） | `AUTHORIZED=1 bash scripts/process_job.sh --url <url> --bookmark` | 需批次授权；未授权 `exit 4` |
| 单岗发送（改状态） | `AUTHORIZED=1 bash scripts/process_job.sh --url <url> --send --msg 话术.txt` | 每岗授权 |
| 扫描聊天列表（只读） | `bash scripts/scan_chat.sh [--out .work/chat_scan.json]` | 调 `zhipin-chat.extract.js`，与库按 `(name,company,role)` 去重 |
| 话术自检 gate | `python3 scripts/audit_icebreaker.py .work/recruiter_jd.json 话术.md 事实库.md keys.json` | 要求 JD≥90% 且 事实≥90% |
| 后端闸门 / 撞墙 / 限速 | （由 `common.sh` 自动提供，脚本 `source` 即生效） | 不要绕过、不要自写冷却 |

---

## 二、检索 / 收集（已内置，直接复用）

- **多词检索**：`scripts/search_jobs.sh`（走 `bz_*` 契约、复用同 tab、只读、hosted 短路 emit_plan）。禁再写 `run_searches.sh` 等价物。
- **卡片解析**：`scripts/parse_search.py`（解析 `a.job-name` / `.boss-name` / `.company-location` / `.tag-list`；**不提取薪资**——卡片薪资被字体反爬混淆）。由 `search_jobs.sh` 内部调用。
- 选择器见 `references/boss_selectors.md`：搜索框 `.search-input-box .input` + `.search-btn`；卡片 `a.job-name`/`.boss-name`/`.company-location`/`.tag-list`。首次跑预飞 1 词校验。

---

## 三、反模式（违反 = 立即停用，改用内置）

> 🚫 **违规判定**：用 `Write` 创建对标已有内置脚本的文件（`run_searches.sh` / `parse_search.py` / `filter_candidates.py` / `read_jd_batch.py` / `search.py` / `run_search*.sh` 等）= **违反复用铁律**，必须立即停用并改用内置对应脚本。

- ❌ 写 `run_searches.sh` / `parse_search.py` 等价物 → 已内置，复用 `search_jobs.sh` + `parse_search.py`。
- ❌ 写 `filter_candidates.py` 重做去重 / 过滤 / 打分 → 复用 `filter_library.py`（只读省略 `--library`）。
- ❌ 写 `read_jd_batch.py` 重做批量读 JD → shell 循环 `process_job.sh --read-jd`。
- ❌ 从搜索卡片直读薪资 → 字体混淆，薪资须从 JD 详情页取。
- ❌ 裸 `node brs.js` / `cd agent-browser-runtime` 绕过后端抽象 → 一律走 `bz_*` 契约（`source common.sh`）。

---

## 四、复用发现问题怎么办（受控逃逸阀 · 见 SKILL.md ④）

1. **先用内置脚本跑**；若发现 bug / 局限 → **优先就地改**该脚本（fix-in-place），让所有未来运行受益。
2. 若需求**确实全新**、与现有脚本无重叠 → **新建**脚本，收编进 `scripts/`，并在本表登记精确命令。
3. 无论「改」还是「新建」，**未来同一需求一律复用该脚本，禁止每次重造**。

> ⚠️ **逃逸阀受控闸门**：新建脚本前，**必须在回复中显式列出「已审视的 `scripts/` 清单 + 为何现有脚本不适用」**；无法说清「为何不适用」时，**默认就地改现有脚本**，不得新建。新建后**必须**在本表登记精确命令，否则下次仍会被当「新需求」重造。

> 目的：skill 预建脚本就是为了消除「Agent 每次任务现写脚本」带来的误差与低效率。复用是第一原则；改/新建是受控的逃逸阀，且必须沉淀回 skill。
