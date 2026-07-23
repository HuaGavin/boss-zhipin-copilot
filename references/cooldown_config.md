# BOSS 限速配置（zhipin）

> **关键事实**：agent-browser-runtime 的 `platformCooldownSeconds()` 默认只覆盖
> `reddit / facebook / linkedin / instagram / manualChallenge`，**不含 zhipin**；对未知平台返回 `generic: 0`。
> 因此 BOSS 的限速**必须由本 skill 脚本显式实现**（脚本内 `sleep` + 日计数）。
> 项目一层保护都不给——这是安全底线，不可依赖运行时。

---

## 一、极简限速（安全底线，不可突破）

| 项 | 默认值 | 环境变量 | 说明 |
|---|---|---|---|
| 动作间隔 | 5s | `ACTION_INTERVAL_SECONDS` | 每次浏览器动作前 `sleep` |
| 日上限 | 100 | `DAILY_CAP` | 每日收藏 + 开聊总数硬上限；脚本内部计数，超限即停 |
| 撞墙冷却 | ≥24h | （不可覆盖） | 撞验证墙立即停手，期间仅真人使用 |

- 现已纯 UI 真实光标点击，基本无超时风险；以上为**不可突破的底线**。

---

## 二、验证墙冷却（最高优先级）

一旦撞 `verify.html` / 「验证码」：

1. 立即停手，截图留存。
2. 交人工（用户）通过验证码。
3. **冷却 ≥24h，期间仅真人正常使用，绝不恢复自动化**。
4. 脚本已内置 `FAIL_LOUD`：撞墙即 `exit 3`，不重试、不绕过。

---

## 三、环境变量覆盖

脚本读取以下环境变量（均有保守默认值）：

```bash
export ACTION_INTERVAL_SECONDS=5     # 动作间最小间隔秒数
export DAILY_CAP=100                 # 每日收藏 + 开聊总数硬上限
export BOOKMARK_COOLDOWN=8           # 书签动作间隔（覆盖 ACTION_INTERVAL_SECONDS）
export SEND_COOLDOWN=20              # 发送动作间隔（覆盖 ACTION_INTERVAL_SECONDS）
export WORK_DIR="./.work"            # 中间产物落盘目录
```

> 节奏宁可慢不可快。账号安全 > 效率。任何「提速」需求都先过 R3/R4 复核。

---

## 四、人体化节奏（防机器特征 · Item5）

固定节奏易被反作弊识别为脚本。两项细化：

- **抖动（jitter）**：`cooldown()` 在基础间隔上叠加 ±`COOLDOWN_JITTER` 随机秒，更接近真人操作。默认 `COOLDOWN_JITTER=3`（即 5s±3 → 2–8s）。
- **软限流退避（rate_backoff）**：一旦页面提示「操作频繁」或接近日上限，调用 `rate_backoff` 让间隔按 `2^(n-1)` 指数拉长（5→10→20→40→60 封顶），`BACKOFF_MAX` 控制上限。命中即退避、不再机械连点。

| 变量 | 默认 | 说明 |
|---|---|---|
| `COOLDOWN_JITTER` | `3` | 间隔随机抖动幅度（±秒）；设 0 退化为固定间隔 |
| `BACKOFF_MAX` | `60` | 软限流指数退避上限（秒） |

> 用法：正常动作走 `cooldown`；命中软限流信号时改调 `rate_backoff`（间隔自动递增）。会话内退避计数器持续累计，新会话自动清零。
