#!/usr/bin/env bash
# common.sh - 被其他脚本 source，提供跨平台通用能力 + 浏览器后端(BrowserDriver)分发。
# 设计原则（遵循 OpenClaw 脚本约定）：用环境变量而非硬编码路径；fail loud；幂等。
#
# 浏览器后端抽象：
#   本 skill 不直接调用某个具体浏览器工具，而是对 references/browser_backend.md 定义的
#   BrowserDriver 契约（bz_* 函数）编程。BZC_BACKEND 选择后端（默认 brs），
#   common.sh 负责探测/加载后端并实现 fail-loud；缺失任何仿真人浏览器即拒绝启动。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backends"

# node / python 可执行：默认用 PATH 上的 node / python3，可用 NODE / PYTHON 覆盖
NODE="${NODE:-node}"
PYTHON="${PYTHON:-python3}"

# ---- 浏览器后端探测 + 加载 ----
BZC_BACKEND="${BZC_BACKEND:-brs}"
if [ ! -f "$BACKEND_DIR/$BZC_BACKEND.sh" ]; then
  echo "FAIL_LOUD: 未检测到可用的「仿真人浏览器」后端 '$BZC_BACKEND'。" >&2
  echo "  本 skill 必须运行在仿真人浏览器之上（直接裸 CDP / 合成点击会触发 BOSS 反作弊，曾导致封号）。" >&2
  echo "  请二选一：" >&2
  echo "    [本地全自动] 安装 agent-browser-runtime 并设 BZC_BACKEND=brs：" >&2
  echo "        https://github.com/energypantry/agent-browser-runtime" >&2
  echo "    [Codex 托管] 安装 OpenAI Codex 桌面端并启用 Chrome 插件，设 BZC_BACKEND=codex：" >&2
  echo "        https://developers.openai.com/codex/app/chrome-extension" >&2
  echo "  可用后端: $(ls "$BACKEND_DIR" 2>/dev/null | sed 's/\.sh$//' | tr '\n' ' ')" >&2
  exit 1
fi
# 加载后端实现（bz_mode / bz_status / bz_browse_* / bz_ui / bz_extract / bz_emit_plan）
# shellcheck source=/dev/null
source "$BACKEND_DIR/$BZC_BACKEND.sh"

# ---- 后端模式助手 ----
backend_is_hosted() { [ "$(bz_mode 2>/dev/null || echo local)" = "hosted" ]; }

# ---- 运行时就绪闸门：委托给后端 bz_status（不就绪时后端内部 fail-loud）----
fail_loud_if_down() { bz_status; }

# ---- 撞墙检查：传入 HTML 文本，命中即停手 ----
verify_wall() {
  local html="$1"
  if echo "$html" | grep -qi "verify\|验证码\|安全验证\|请完成\|拖动滑块"; then
    echo "FAIL_LOUD: 撞验证墙, 立即停手交人工, 冷却>=24h" >&2
    exit 3
  fi
}

# ---- 冷却 sleep ----
cooldown() {
  local secs="${1:-${ACTION_INTERVAL_SECONDS:-5}}"
  sleep "$secs"
}
