# BOSS 直聘关键选择器（需实况校验）

> 选择器来自社区实战提取。**BOSS 前端会改版，选择器可能漂移**。
> 每次大版本运行时，先用 `process_job.sh --url <url> --read-jd` 对一个已知岗位跑通，确认字段非空再批量。
> 校验失败 → 回到本文件更新选择器，**不要绕过**（绕过=用错元素=误触/误判）。

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

## 三、沟通 / 发送（待校准，首次用须复核）

| 用途 | 选择器（待校验） | 备注 |
|---|---|---|
| 立即沟通 | `.btn-chat` | 打开对话框 |
| 输入框 | `.chat-input` | 真实光标点击后 `ui type` |
| 发送 | `.btn-send` | 真实光标点击发送 |

---

## 四、会话列表（待校准）

| 用途 | 选择器（待校验） | 备注 |
|---|---|---|
| 会话条目 | `.chat-item` / `.friend-content` | 含 (name, company, role) 用于去重 |
| 滚动容器 | `.user-list` | 真实滚动容器（非外层面板）；提取器已用 `ui.move` 定位 |

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

---

## 六、验证墙

- URL 含 `verify.html` 或页面文本含「验证码」「安全验证」「请完成」→
  **立即停手交人工，冷却 ≥24h**（见 `safety_rules.md` R4）。
