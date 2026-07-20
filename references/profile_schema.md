# 求职目标画像 Profile（profile.yaml）Schema

> 本文件定义 `boss-zhipin-copilot` 的**唯一输入契约**。
> 整个 skill（检索词、硬排除、评分门槛、破冰事实锚点）全部由本文件驱动，**零硬编码个人偏好**。
> 真实权威文件：用户提供的 `profile.yaml`（默认读取 `./profile.yaml` 或 `$PROFILE` 指向的文件）。

---

## 一、Profile 怎么来

两种入口，skill 都支持：

- **入口 A（推荐，最完整）**：用户提供 **简历/工作事实文件** + **一句话求职目标**。
  Agent 读取后用 `scripts/build_profile.py` 抽出草稿，再校验补全，产出 `profile.yaml`。
- **入口 B（最简）**：用户只给 **一个检索词**（如「产品经理」）或 **一句话目标**
  （如「我想找要求 5 年以上经验、月薪 4 万以上的策略产品经理岗位」）。
  Agent 从句子里尽量解析 `city / salary_floor / seniority_years / 目标角色`，
  解析不出的项保守留空（=不限），必要时向用户追问 1 个最关键的问题（城市？薪资下限？）。

> 无论哪条入口，**profile 必须由 Agent 显式生成并经用户确认**，不得凭空假设。

---

## 二、字段定义

```yaml
meta:
  candidate_name: "李明"        # 仅用于破冰话术称呼，可空
  generated_at: "2026-07-19"    # 生成日期，便于回溯
  notes: ""                     # 自由备注

# 原始目标句（保留以便回溯意图）
goal: "我想找要求 5 年以上经验、月薪 4 万以上的策略产品经理岗位（北京）"

search:
  city: "北京"                  # 检索/筛选期望城市；空字符串=不限
  queries:                      # 实际在 BOSS 搜索框输入的查询词列表
    - "策略产品经理 北京"
    - "产品经理 策略 北京"
    - "高级产品经理 北京"

thresholds:                     # 评分门槛：全部满足才「可收藏」
  city: "北京"                  # 期望城市；空=不限
  salary_floor: 40000           # 月薪下限（元）；0 或空=不限
  seniority_years: 5            # 经验年限下限；0 或空=不限
  stage_allow: []               # 公司阶段白名单，如 ["成长期","不需要融资","未融资"]；空=不限
  scale_max: 0                  # 公司规模上限（人）；0 或空=不限
  employment_type: ""           # 全职/兼职/实习；空=不限

hard_exclude:                   # 硬排除：命中任一关键词即「不入库不收藏」
  - category: "广告/IAA"
    keywords: ["IAA", "广告变现", "买量", "穿山甲", "AdMob"]
  - category: "金融资质"
    keywords: ["证券", "基金从业", "财富管理", "交易系统"]

boost_keywords:                 # 加分关键词：JD 命中越多评分越高（用于排序，非否决）
  - "增长"
  - "留存"
  - "付费转化"
  - "C端"
  - "0-1"
  - "Agent"
  - "会员"

fact_anchors:                   # 事实锚点：破冰话术匹配源 + 自检 gate 的事实字典
  - anchor: "用户增长"
    evidence: "某内容平台渠道增长，次留提升 3%，线索成本降 50%"
  - anchor: "0-1 产品"
    evidence: "主导某工具产品从 0 到 1 独立上线"
```

---

## 三、字段规则

| 字段 | 类型 | 说明 / 默认值 |
|---|---|---|
| `meta.candidate_name` | str | 仅话术称呼用；可空 |
| `goal` | str | 原始目标句，存档回溯 |
| `search.city` | str | 城市过滤；空=不限 |
| `search.queries` | list[str] | BOSS 搜索框实际输入词；至少 1 个 |
| `thresholds.*` | 见上 | 任一为空/0 = 该维度不限 |
| `hard_exclude[].category` | str | 排除类目名（仅给人看） |
| `hard_exclude[].keywords` | list[str] | 命中任一即否决；**用户按自身背景增减** |
| `boost_keywords` | list[str] | 评分加分项，越多越好 |
| `fact_anchors[].anchor` | str | 能力/经历主题 |
| `fact_anchors[].evidence` | str | 可溯源证据（公司+动作+数字），**严禁编造** |

---

## 四、生成纪律（Agent 必须遵守）

1. **硬排除来自用户背景，不是通用规则**：只有「用户明确无对应经验/资质」的类别才列入。
   不要预置任何平台的默认排除列表——那会误杀别人的机会。
2. **门槛保守**：解析不出的维度留空（=不限），宁漏勿错杀；不要替用户拍板薪资/城市。
3. **fact_anchors 必须真实可溯源**：每条 evidence 都能在用户简历/事实文件里找到依据；
   AI/AIGC 类经历只锚定具体场景，不暗示生产级大模型自研。
4. **profile 是本地文件**：生成后落地 `profile.yaml`，后续脚本全部读它，不二次询问。
