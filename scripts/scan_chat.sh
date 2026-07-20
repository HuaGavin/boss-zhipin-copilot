#!/usr/bin/env bash
# scan_chat.sh - 增量扫描 BOSS 聊天列表，落盘 contacts JSON（只读，不改状态）
# 用法: bash scripts/scan_chat.sh [--out f] [--lease id --tab id]
# 复用模式由调用方持有 lease/tab，便于与 process_job.sh 串在同一会话。
# 后端：经 common.sh 选择 BrowserDriver。hosted 模式短路到 bz_emit_plan。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# hosted 模式：生成外部 Agent 步骤提示词后退出（保留原始 argv）
if backend_is_hosted; then bz_emit_plan --scan-chat "$@"; exit 0; fi

OUT_JSON="${WORK_DIR:-.work}/chat_scan.json"
CHAT_URL="https://www.zhipin.com/web/geek/chat"
SELF_MANAGED=1; LEASE=""; TAB=""

while [ $# -gt 0 ]; do
  case "$1" in
    --out)   OUT_JSON="$2"; shift 2;;
    --lease) LEASE="$2"; SELF_MANAGED=0; shift 2;;
    --tab)   TAB="$2"; SELF_MANAGED=0; shift 2;;
    *) echo "未知参数: $1" >&2; exit 1;;
  esac
done

fail_loud_if_down

if [ "$SELF_MANAGED" -eq 1 ]; then
  bz_browse_start "$CHAT_URL" || { echo "FAIL_LOUD: browse-start 失败" >&2; exit 1; }
  LEASE="$BZ_LEASE"; TAB="$BZ_TAB"
  cleanup(){ bz_browse_end "$LEASE" || true; }; trap cleanup EXIT
fi

RESULT=$(bz_extract "$SCRIPT_DIR/zhipin-chat.extract.js" "$LEASE" "$TAB" '{"action":"read"}' 2>&1)
# 校验 extract 返回的 ok 字段：ok 非 true 视为失败，打印错误并 exit 1（不静默吞掉）
if ! echo "$RESULT" | "$PYTHON" -c "import sys, json
d = json.load(sys.stdin)
if not d.get('ok'):
    sys.stderr.write('[error] extract 失败: ' + str(d.get('error', d.get('details', 'unknown'))) + '\n')
    sys.exit(1)
print('[ok] 解析到会话数:', len(d.get('contacts', [])))"; then
  echo "$RESULT" >&2
  exit 1
fi
mkdir -p "$(dirname "$OUT_JSON")"
echo "$RESULT" > "$OUT_JSON"
echo "[ok] 聊天快照 -> $OUT_JSON"
