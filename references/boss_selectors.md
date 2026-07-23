# BOSS 直聘选择器 / 页面 / 点位（需实况校验）

> 本文件是「选择器 / 页面 / 点位」三类资产的唯一权威索引，遵循 SKILL.md「🛑 优先复用与增量更新」原则：
> **复用优先**（已有条目直接用）、**发现错误就地改**（漂移 → 回本文件更新，**禁止绕过**）、**发现新内容补进对应节**（标「首次校验」）。
> 选择器来自社区实战提取，**BOSS 前端会改版，可能漂移**；每次大版本先预飞 1 岗确认字段非空再批量。

---

## 一、招聘方 / JD / 公司（读详情用，较稳）

| 用途 | 选择器 | 提取要点 |
|---|---|---|
| 招聘方姓名 | `.job-boss-info .name` | 取首行文本，去「在线」二字 |
| 招聘方职位 | `.boss-info-attr` | 取「·」分隔末段 |
| 完整 JD | `.job-sec-text` | 回退 `.job-detail-section` / `.text-desc` |
| 公司 | `.sider-company` | 公司名 + 规模 + 阶段 |
| ⚠️ 登录账号本人 | `.user-nav` | **严禁**当作招聘方（那是登录用户本人） |

---

## 二、书签按钮（较稳）

| 用途 | 选择器 | 核验 |
|---|---|---|
| 感兴趣 | `.btn-interest` | 点击后文本应变「取消感兴趣」；以此核验成功 |

---

## 三、沟通 / 发送（✅ 2026-07-23 实战校准；UI 有两个变体，按序 fallback）

| 用途 | 首选（2026-07-23 实测） | 回退（2026-07-20 变体） | 备注 |
|---|---|---|---|
| 立即沟通 | `.btn-startchat` | — | 详情页按钮；点击后进入聊天弹窗（可能自动聚焦输入框） |
| 输入框 | `#chat-input`（contenteditable div，class=`.chat-input`） | `textarea.input-area` | 两变体并存，先试 `#chat-input` |
| 发送 | `.btn-send`（`button.btn-v2.btn-sure-v2.btn-send`） | `.send-message` | 先试 `.btn-send` |

- **送达校验（严格）**：发送后重新取 HTML，要求 ①`#chat-input` 编辑框已清空（草稿不残留）②消息区含话术前缀；出现 `status-delivery`（`[送达]`）为最强确认。**仅 grep 页面含话术会误判**——键入未发送时草稿也在页面里。
- 「职位已关闭」页面无 `.btn-startchat` → 跳过该岗并记库（exit 6），**不算撞墙**，继续批次。

---

## 四、会话列表（✅ 2026-07-23 实测校准）

| 用途 | 选择器（实测） | 备注 |
|---|---|---|
| 会话条目 | `.chat-item` / `.friend-content` | 含 (name, company, role) 用于去重 |
| 滚动容器 | `.user-list` | 真实滚动容器（非外层面板）；提取器已用 `ui.move` 定位 |
| 最近消息预览 | `.last-msg-text` | 核对我方已发话术是否落盘 |
| 送达标记 | `status-delivery`（`message-status` 类，文案 `[送达]`） | **最强送达确认**；独立复核聊天列表时逐条确认 [送达] |

- 送达校验双保险：发送后除「编辑框清空 + 消息区含话术」（见三），再到 `/web/geek/chat` 列表核对 `status-delivery` 标记，逐条确认 [送达]（2026-07-23 已用此法独立复核 5 岗）。

---

## 五、搜索框 + 结果卡片（Step 2 检索，search_jobs.sh / parse_search.py）

| 用途 | 选择器 | 备注 |
|---|---|---|
| 岗位搜索页 | `https://www.zhipin.com/web/geek/job` | 复用同 tab 导航到此再检索 |
| 搜索输入 | `.search-input-box .input` | 真实光标点击 → `ui type` 查询词 |
| 搜索按钮 | `.search-btn` | 提交检索 |
| 岗位名 + 链接 | `a.job-name`（`href`） | href 形如 `/job_detail/XXX.html` |
| 公司名 | `.boss-name` | |
| 城市 | `.company-location` | 如「北京·朝阳区」 |
| 经验/学历 | `.tag-list li` | 限定卡内，防跨卡串扰 |
| 薪资 | `.job-salary` | ⚠️ 字体反爬混淆，**禁读**，须从 JD 详情页取 |

> skill 强制**真实 UI 搜索**（键入 + 点搜索），禁止拼接 `?query=&city=&page=` 捷径 URL。

### 结果页筛选器（✅ 2026-07-23 实测校准；hover 出下拉、复选、URL 侧证生效）

搜索提交后结果页 URL 变为 `/web/geek/jobs`，**搜索框正下方**一排筛选触发器（实测 y≈140）。下拉显隐是**纯 CSS `:hover`**（选项 `li` 常驻 DOM，无 open/active 状态类）→ **读选项无需 hover，但真实光标点选前必须先 `ui move` 悬停到触发器让下拉可见**。

| 结构 | 选择器 | 备注 |
|---|---|---|
| 筛选器容器 | `.condition-filter-select`（常规）/ `.condition-industry-select`（公司行业）/ `.condition-position-select`（职位类型） | 每个筛选一个容器 |
| 触发器（hover 点位） | 容器内 `.current-select` | ⚠️ **禁用 `--targetText "公司规模"` 定位**——实测命中页面中部其它文本（y=428 非筛选栏 y=142）致 `UI target not found`；须用结构选择器，如 `.condition-filter-select:has(li[ka="sel-job-rec-scale-0"]) .current-select` |
| 下拉面板 | `.filter-select-dropdown` → `ul.select-list` → `li[ka=...]` | `li` 的 `ka` 属性 = 唯一稳定点位 |

**全部筛选器与 `ka` 编码**（`ka="sel-job-rec-<域>-<code>"`；`0`=不限）：

| 筛选器 | 域 | 选项编码 | 复选 |
|---|---|---|---|
| 职位类型 | `sel-position-*` | 二级面板（互联网/AI、产品…） | — |
| 求职类型 | `jobType` | 1901全职 / 1903兼职 | 单选 |
| 薪资待遇 | `salary` | 402 3K以下 / 403 3-5K / 404 5-10K / 405 10-20K / 406 20-50K / 407 50K以上 | 单选 |
| 工作经验 | `exp` | 108在校生 / 102应届生 / 101经验不限 / 103 1年内 / 104 1-3年 / 105 3-5年 / 106 5-10年 / 107 10年以上 | 复选 |
| 学历要求 | `degree` | 209初中及以下 / 208中专中技 / 206高中 / 202大专 / 203本科 / 204硕士 / 205博士 | 复选 |
| 公司行业 | （二级面板） | 大类行 `li.clearfix` 内嵌子项，无单值 ka；首次点选前须再实测 | — |
| **公司规模** | `scale` | **301 0-20人 / 302 20-99人 / 303 100-499人 / 304 500-999人 / 305 1000-9999人 / 306 10000人以上** | **复选** |
| 融资阶段 | `stage` | 801未融资 / 802天使轮 / 803A轮 / 804B轮 / 805C轮 / 806 D轮及以上 / 807已上市 / 808不需要融资 | 复选 |

**实测操作配方（全程真实光标；6 维度通用）**：
- **通用触发器选择器**（每维复用，把 `<dim>` 换成 scale/stage/exp/degree/salary/jobType）：
  `ui move --selector '.condition-filter-select:has(li[ka="sel-job-rec-<dim>-0"]) .current-select'` → 悬停展开
  `ui click --selector 'li[ka="sel-job-rec-<dim>-<code>"]'` → 点目标档
- **每点一档后须重新 hover 一次**再点下一档（点选后下拉可能收起；复选维需逐档重复）。
- **生效核验**：tab URL 出现对应参数（复选=逗号分隔），结果自动刷新。实测 6 维点选后 URL：
  `.../jobs?city=...&jobType=1901&salary=406&experience=105&degree=203&scale=303&stage=804&query=...`
  即 URL 参数名映射：**scale→scale / stage→stage / exp→experience / degree→degree / salary→salary / jobType→jobType**（注意 exp 在 URL 里叫 `experience`，但 `ka` 域仍是 `exp`）。
- ⚠️ URL 参数**仅作生效核验，禁止直接拼 URL 导航**（R1 禁查询串捷径）；应用一律走真实光标 hover+click。

**6 维度选值速查（与上方编码表一致；`0`=不限永不点选）**：

| 维度 | 选值方式 | 常用编码 |
|---|---|---|
| 公司规模 scale | 复选 | 302 20-99人 / 303 100-499人 / 304 500-999人 |
| 融资阶段 stage | 复选 | 802 天使 / 803 A / 804 B / 805 C / 806 D轮及以上 / 807 已上市 / 808 不需要融资 |
| 工作经验 exp | 复选 | 102 应届 / 104 1-3年 / 105 3-5年 / 106 5-10年 / 107 10年以上 / 108 在校 |
| 学历要求 degree | 复选 | 202 大专 / 203 本科 / 204 硕士 / 205 博士 |
| 薪资待遇 salary | **单选** | 405 10-20K / 406 20-50K / 407 50K以上 |
| 求职类型 jobType | **单选** | 1901 全职 / 1903 兼职 |

- 筛选是本地搜索视图状态，不改账号状态（非收藏/沟通），属只读安全动作；换查询词重新搜索后筛选**是否保留未实测**，稳妥做法=每词搜索后重新应用（`search_jobs.sh` 已落实）。
- `search_jobs.sh` 现已内置**全 6 维度**筛选：`--intent "自由文本"`（自动解析意图）、或 `--scale/--stage/--exp/--degree/--salary/--jobtype` 逐维覆盖；未显式给的维度从 profile `thresholds` 推导（见 `intent_filters.py` 与 `script_catalog`）。

---

## 六、个人中心 / 已知页面（导航目标，防盲试）

| 页面 | URL | 进入方式 | 用途 |
|---|---|---|---|
| 个人中心 | `https://www.zhipin.com/web/geek/recommend` | 点击主页右上角**头像**进入 | 聚合查看本人所有状态 |
| 收藏列表（感兴趣） | 同上 URL 的「感兴趣」tab | 个人中心顶部第 4 个 tab | **只读**查看全部已收藏岗位 |
| 岗位详情页 | `https://www.zhipin.com/job_detail/<jid>.html` | 搜索卡 `a.job-name` 的 href 取 `<jid>` | 读 JD / 发消息起点 |

- ⚠️ **导航到 JD 详情页须去掉 `?securityId=...`**：带完整 securityId 的 URL 会变回通用页、JD 标记缺失（2026-07-23 实测踩坑）。只用 `https://www.zhipin.com/job_detail/<jid>.html` 即可。

- **术语映射**：BOSS 把"收藏"叫「感兴趣」。本 skill 的「已收藏(感兴趣)」状态、详情页 `.btn-interest` 按钮、此列表页——三者同义。
- **个人中心顶部 4 tab（从左到右）**：`沟通过` / `已投递` / `面试` / `感兴趣`。「感兴趣」= 岗位收藏列表。
- **只读用途**：核对 `target_library.csv` 的「已收藏(感兴趣)」是否与 BOSS 实际一致；**绝不在此页做改状态动作**（点错会触发取消收藏 / 重新沟通）。
- **「感兴趣」开关本体在详情页**：`.btn-interest`（见第二节），不在本列表页；列表页是聚合视图，但**每卡另有 `a.btn-startchat` 可发起沟通**（结构见上方「收藏列表卡片 DOM」）。
- ⚠️ URL 与 tab 文案可能随 BOSS 改版漂移；首次用先人工确认 tab 位置，勿硬编码路径盲跳。

### 收藏列表卡片 DOM（2026-07-23 实测；可从此页逐卡发起沟通）

| 用途 | 选择器 | 备注 |
|---|---|---|
| 卡片容器 | `ul.user-jobs-ul` → `li.item-boss` | 每个收藏岗一张卡（2026-07-23 实测解析确认） |
| 岗位名 | `.job-name-text` | |
| 城市/区域 | `.location` | 如「北京·海淀区·苏州桥」 |
| 薪资·经验·学历 | `.job-info p.gray` | 三段灰字；**薪资字体反爬禁读**，须进 JD 详情页取 |
| 招聘方 | `.info-header h3.name span` | 去「招聘者/HR/创始人」后缀；**容器不同于** JD 详情页的 `.job-boss-info .name` |
| 公司 | `.company-info b > a` | |
| 行业·阶段·规模 | `.company-info p.gray > span` | |
| 立即沟通（列表内） | `a.btn-startchat`（ka=`personal_interest_chat_xxx`） | 解析确认存在；点击预期同 JD 详情页 `.btn-startchat`（开聊），**本会话未实测点击，首次用先预飞 1 卡**；与 `.btn-interest`（感兴趣开关，见二）是不同按钮 |

- ⚠️ 列表页**每卡都有** `a.btn-startchat`，可不经详情页直接发消息；但严谨流程仍先 `--read-jd` 读 JD 再发（话术需 JD 洞察）。
- 滚动容器待核：实测一次性渲染 ~15 张卡（tab 计数 27，可能因虚拟滚动或含「公司收藏」子 tab 不全）；补全卡量时用 `ui.scroll` 加载更多，容器疑似 `.user-jobs-ul`（首次用先人工确认）。
- 解析/批量处理须用真实光标 + DOM 提取（无内置 `zhipin-bookmark.extract.js`，当前为临时 Python 解析 HTML）。

---

## 七、验证墙

- URL 含 `verify.html` 或页面文本含「验证码」「安全验证」「请完成」→
  **立即停手交人工，冷却 ≥24h**（见 `safety_rules.md` R4）。
