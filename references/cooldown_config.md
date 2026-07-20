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
