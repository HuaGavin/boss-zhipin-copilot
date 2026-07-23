#!/usr/bin/env bash
# backends/brs.sh - 默认后端：energypantry/agent-browser-runtime (brs.js)
# 实现 BrowserDriver 契约。这是当前唯一「已实现且默认」的本地后端。
# 安装: https://github.com/energypantry/agent-browser-runtime
set -euo pipefail

# ---- 解析 brs.js 路径 ----
# 探测顺序（优先显式覆盖，再按相对仓库路径/常见位置）：
#   1. $BRS_JS                 （显式覆盖，最高优先级）
#   2. $AGENT_BROWSER_RUNTIME_HOME/cli/brs.js
#   3. <repo>/../../agent-browser-runtime/cli/brs.js   （仓库的兄弟目录；repo = backends/.. = scripts/.. = 仓库根）
#   4. $HOME/agent-browser-runtime/cli/brs.js
#   5. $HOME/.agent-browser-runtime/cli/brs.js
# ⚠️ 本文件被 source 进调用方 shell——严禁用 SCRIPT_DIR 等通用变量名（会覆盖调用方同名变量，
#    曾致 search_jobs.sh 的 parse_search.py 路径错乱）。一律用 BRS_ 前缀。
BRS_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BRS_SH_DIR/../.." && pwd)"
resolve_brs() {
  if [ -n "${BRS_JS:-}" ]; then return 0; fi
  local candidates=(
    "${AGENT_BROWSER_RUNTIME_HOME:-}/cli/brs.js"
    "$REPO_ROOT/../../agent-browser-runtime/cli/brs.js"
    "$HOME/agent-browser-runtime/cli/brs.js"
    "$HOME/.agent-browser-runtime/cli/brs.js"
  )
  for c in "${candidates[@]}"; do
    if [ -n "$c" ] && [ -f "$c" ]; then BRS_JS="$c"; echo "[ok] 探测到 brs.js: $BRS_JS" >&2; return 0; fi
  done
  echo "FAIL_LOUD: 未设置 \$BRS_JS 且在常见路径找不到 brs.js。" >&2
  echo "  请先安装 agent-browser-runtime: https://github.com/energypantry/agent-browser-runtime" >&2
  echo "  并设置 BZC_BACKEND=brs（或默认），必要时导出 BRS_JS=/path/to/cli/brs.js" >&2
  exit 1
}
resolve_brs

brs() { "$NODE" "$BRS_JS" "$@"; }

# ---- 契约实现 ----
bz_mode() { echo local; }

bz_status() {
  local s
  s=$(brs status 2>&1) || { echo "FAIL_LOUD: brs status 执行失败, agent-browser-runtime 未运行 (docker compose up -d?)" >&2; exit 1; }
  echo "$s" | "$PYTHON" -c 'import sys,json
s=sys.stdin.read()
try:
    j=json.loads(s)
except Exception:
    print("FAIL_LOUD: status 输出无法解析:", s[:200], file=sys.stderr); sys.exit(2)
if not j.get("extensionConnected"):
    print("FAIL_LOUD: companion 扩展未连接, 禁止任何浏览器动作 (请先在 noVNC 登录 BOSS 并确认 extension 已连接)", file=sys.stderr); sys.exit(2)' || exit $?
  echo "[ok] runtime ready (brs extension connected)" >&2
}

bz_browse_start() {
  local url="$1"; local humanize="${2:-}"
  local extra=""; [ -n "$humanize" ] && extra="--humanize $humanize"
  local out
  if ! out=$(brs browse-start "$url" $extra 2>&1); then
    echo "FAIL_LOUD: brs browse-start 失败: $out" >&2
    return 1
  fi
  # 在父作用域导出 lease/tab（调用方直接在父作用域调用本函数，变量可直达）
  export BZ_LEASE BZ_TAB
  BZ_LEASE=$(echo "$out" | "$PYTHON" -c "import sys,json;print(json.load(sys.stdin)['lease']['id'])") \
    || { echo "FAIL_LOUD: 解析 lease 失败: $out" >&2; return 1; }
  BZ_TAB=$(echo "$out" | "$PYTHON" -c "import sys,json;print(json.load(sys.stdin)['tab']['id'])") \
    || { echo "FAIL_LOUD: 解析 tab 失败: $out" >&2; return 1; }
  echo "$out" >&2   # 调试日志（不污染 stdout）
}

bz_browse_html() {
  # brs browse-html 返回 artifact JSON（{"path":"artifacts/..."}），非 HTML 本体。
  # 这里解包：解析 path 并 cat 出真实 HTML，供调用方 grep（撞墙检查/送达校验依赖此语义）。
  local lease="$1" tab="$2" out p root
  out=$(brs browse-html "$lease" "$tab" 2>&1) || { echo "$out"; return 1; }
  p=$(printf '%s' "$out" | "$PYTHON" -c 'import sys,json
try:
    j=json.loads(sys.stdin.read()); print(j.get("path") or j.get("artifact",{}).get("path") or "")
except Exception:
    print("")') || true
  if [ -n "$p" ]; then
    root="$(cd "$(dirname "$BRS_JS")/.." && pwd)"   # brs.js 位于 <runtime>/cli/
    if [ -f "$root/$p" ]; then cat "$root/$p"; return 0; fi
    [ -f "$p" ] && { cat "$p"; return 0; }
    echo "FAIL_LOUD: artifact 文件不存在: $root/$p" >&2; return 1
  fi
  # 无 path 字段则按原样输出（兼容未来直接返回 HTML 的实现）
  printf '%s' "$out"
}

# 复用同一 lease/tab 导航到新 URL（不重开 tab，落实「禁止频繁开关 tab」）
bz_browse_nav() {
  local lease="$1" tab="$2" url="$3"
  brs browse-nav "$lease" "$tab" "$url" 2>&1
}

bz_browse_end() {
  local lease="$1"
  brs browse-end "$lease" >/dev/null 2>&1 || true
}

bz_ui() {
  local tab="$1"; shift
  brs ui "$tab" "$@" 2>&1
}

bz_extract() {
  local jsfile="$1" lease="$2" tab="$3" params="$4"
  brs extract "$jsfile" --lease-id "$lease" --tab-id "$tab" --params "$params" 2>&1
}

# hosted 模式专用（本后端为 local，不会进入；占位以防误调用）
bz_emit_plan() { echo "FAIL_LOUD: brs 是本地后端，不应调用 bz_emit_plan" >&2; exit 1; }
