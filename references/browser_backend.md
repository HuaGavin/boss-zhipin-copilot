# 浏览器后端（BrowserDriver）契约与兼容清单

本 skill 的所有「浏览器动作」都通过一套 **BrowserDriver 契约** 执行，而不是直接调用某个具体工具。
这样用户可以用自己已有的「仿真人浏览器」——只要它实现了下面的函数，就能即插即用。

代码入口：`scripts/common.sh` 读取环境变量 `BZC_BACKEND`（默认 `brs`），
`source scripts/backends/$BZC_BACKEND.sh`，随后所有脚本只调用下面定义的 `bz_*` 函数。

---

## 一、契约：每个后端必须实现的函数

> 约定：所有 `bz_*` 函数由 `backends/<name>.sh` 定义；`common.sh` 在 source 后调用它们。
> 任何「未就绪 / 撞验证墙 / 未授权」都必须 **fail-loud（非零退出 + 明确 stderr 信息）**。

| 函数 | 入参 | 行为 | 必须 |
|------|------|------|------|
| `bz_mode` | 无 | 打印 `local` 或 `hosted` 到 stdout。`hosted`=浏览器由外部 Agent（如 Codex）托管，本 skill 只生成步骤提示词，不实际驱动 | ✅ |
| `bz_status` | 无 | 运行时就绪闸门。不就绪则 fail-loud（exit≠0）。`hosted` 模式可只打印提示并正常退出 | ✅ |
| `bz_browse_start` | `<url> [humanize]` | 打开目标页、占用一个租约/标签页；**导出全局变量 `BZ_LEASE` / `BZ_TAB`**（调用方不再解析 stdout）；同时把原始 JSON 打到 stdout | ✅ |
| `bz_browse_html` | `<lease> <tab>` | 打印当前页 HTML 到 stdout（用于解析 JD / 招聘方 / 撞墙检查） | ✅ |
| `bz_browse_nav` | `<lease> <tab> <url>` | 复用同一 lease/tab 导航到新 URL（不重开 tab，落实「禁频繁开关」；检索多词复用） | ✅ |
| `bz_browse_end` | `<lease>` | 释放租约/关闭标签页 | ✅ |
| `bz_ui` | `<tab> <subcommand...>` | 真实光标 UI 原语：`wait-for --selector` / `click --selector` / `type --text` / `scroll` / `move`。**必须用真实光标，禁止合成点击** | ✅ |
| `bz_extract` | `<jsfile> <lease> <tab> <params-json>` | 运行页面内提取器（聊天列表扫描等），结果打印到 stdout | 条件（scan_chat 需要） |
| `bz_emit_plan` | `<原始 argv...>` | 仅 `hosted` 模式需要：把一次浏览器任务翻译成可粘贴到外部 Agent 的步骤提示词 | 条件（hosted 需要） |

通用助手（由 `common.sh` 提供，后端可调用）：
- `verify_wall <html>`：命中验证墙关键词即 fail-loud（exit 3）。
- `cooldown <secs>`：限速 sleep（含 ±`COOLDOWN_JITTER` 抖动）。
- `rate_backoff`：软限流指数退避（间隔按 2^(n-1) 拉长，封顶 `BACKOFF_MAX`），命中「操作频繁」时调用。
- `bz_wait <lease> <tab> <token> [timeout] [interval]`：轮询当前页直到 `token` 元素出现（就绪闸门），超时 fail-loud；hosted 直接 return 0。
- `backend_is_hosted`：返回 0 当且仅当 `bz_mode` 为 `hosted`。

**安全纪律（R1–R9，见 safety_rules.md）对一切后端生效**：真实光标、限速、撞墙停手≥24h、授权门控、合并打开复用 lease、预飞复制、单 lease。后端只是「手部」，纪律不变。

---

## 二、已知后端清单与支持矩阵

| 后端 | `BZC_BACKEND` | 模式 | 开源/免费 | 反检测路线 | 本仓库状态 | 安装/文档 |
|------|---------------|------|-----------|-----------|-----------|-----------|
| **agent-browser-runtime** | `brs` | local | 开源 MIT | 真实 Chromium + companion 扩展 + broker 租约 + 人性化限速（**首选，最贴合 BOSS 直聘**） | ✅ **已实现且默认** | https://github.com/energypantry/agent-browser-runtime |
| **OpenAI Codex** | `codex` | hosted | 需 ChatGPT Plus/Pro + Codex 桌面端 | 真实登录态 Chrome + 官方扩展 + Computer Use 光标 + 网站许可/黑名单 | ✅ **已实现（hosted：生成 @Chrome 提示词）** | https://developers.openai.com/codex/app/chrome-extension |
| **CloakBrowser** | `cloak` | local | 开源 MIT | 源码级改指纹隐身 Chromium + `humanize=True`（贝塞尔鼠标/逐字键入/惯性滚动）+ Playwright 直接替换 | 🔴 **status: not-implemented (skeleton only)** | https://github.com/CloakHQ/cloakbrowser |
| **agent-browser (Vercel)** | `agent_browser` | local | 开源 | 无障碍树 `@eX` 引用交互（轻量，非反检测路线） | ⚪ 文档候选（未实现） | https://github.com/vercel-labs/agent-browser |

> 选型建议：**本地全自动优先 `brs`**；已用 Codex 生态、愿意人工粘贴提示词的用 `codex`；
> 想要「免 Docker、源码级隐身」可等 `cloak` 驱动实现。

> ⚠️ **`cloak` 后端当前为「骨架（skeleton only），未实现驱动」**：`scripts/backends/cloak.sh` 仅做了 API 映射占位，
> 并未实现任何 `bz_*` 契约函数。任何动作都会 **fail-loud**（不要设置 `BZC_BACKEND=cloak`）。
> 若要实现，应在 `scripts/backends/cloak.sh` 中补齐第一节的全部「必须」函数（`bz_mode` / `bz_status` / `bz_browse_start` / `bz_browse_html` / `bz_browse_nav` / `bz_browse_end` / `bz_ui` / `bz_extract`），
> 并保证 `bz_status` 能真正探测隐身 Chromium 光标已就绪，否则宁可 fail-loud 也不要盲跑。

---

## 三、如何新增一个后端

1. 在 `scripts/backends/` 新建 `<name>.sh`，实现第一节的全部「必须」函数（hosted 再加 `bz_emit_plan`）。
2. 保持安全纪律：真实光标、限速、撞墙停手、授权门控。如后端不支持某原语，fail-loud 说明，不要降级成合成点击。
3. 在 README 的支持矩阵和本文件补一行。
4. 本地模式后端需保证 `bz_status` 能真正探测「扩展/光标已就绪」，否则宁可 fail-loud 也不要盲跑。

---

## 四、缺失/未知后端：fail-loud 示例

```
FAIL_LOUD: 未检测到可用的「仿真人浏览器」后端。
  本 skill 必须运行在仿真人浏览器之上（直接裸 CDP / 合成点击会触发 BOSS 反作弊，已多次导致封号）。
  请二选一：
    [本地全自动] 安装 agent-browser-runtime 并设 BZC_BACKEND=brs：
        https://github.com/energypantry/agent-browser-runtime
    [Codex 托管] 安装 OpenAI Codex 桌面端并启用 Chrome 插件，设 BZC_BACKEND=codex：
        https://developers.openai.com/codex/app/chrome-extension
  退出码 1。
```
