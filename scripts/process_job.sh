#!/usr/bin/env bash
# process_job.sh - 单岗处理：书签 / 读JD / 发消息（可复用 lease，落实 R6/R8）
#
# 用法（自管模式，脚本自己开/关 tab）:
#   bash scripts/process_job.sh --url <url> [--bookmark] [--read-jd [--out f]] [--send --msg f] [--keep]
#
# 用法（复用模式，由调用方持有 lease/tab，批量连续不重开）:
#   bash scripts/process_job.sh --lease <id> --tab <id> --url <url> [--bookmark] [--read-jd ...] [--send ...]
#
# 后端：经 common.sh 选择 BrowserDriver（默认 brs）。hosted 模式（如 codex）自动短路到 bz_emit_plan，
#       生成可粘贴进外部 Agent 的步骤提示词，不实际驱动浏览器。
#
# 红线:
#   - 发消息需 AUTHORIZED=1，否则拒绝 (exit 4)
#   - 撞墙 exit 3 停手
#   - 仅真实光标 (ui click/type)，绝不合成点击
#   - 选择器见 references/boss_selectors.md（待校准项首次须复核）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# hosted 模式：不实际驱动，生成外部 Agent 步骤提示词后退出
# （必须在参数解析前执行，以保留原始 argv 传给 bz_emit_plan）
if backend_is_hosted; then bz_emit_plan "$@"; exit 0; fi

BOOKMARK=0; READJD=0; SEND=0; KEEP=0
URL=""; LEASE=""; TAB=""; OUT_JSON="${WORK_DIR:-.work}/jd_read.json"; MSG=""
SELF_MANAGED=1

while [ $# -gt 0 ]; do
  case "$1" in
    --url)   URL="$2"; shift 2;;
    --lease) LEASE="$2"; SELF_MANAGED=0; shift 2;;
    --tab)   TAB="$2"; SELF_MANAGED=0; shift 2;;
    --bookmark) BOOKMARK=1; shift;;
    --read-jd)  READJD=1; shift;;
    --out)   OUT_JSON="$2"; shift 2;;
    --send)  SEND=1; shift;;
    --msg)   MSG="$2"; shift 2;;
    --keep)  KEEP=1; shift;;
    *) echo "未知参数: $1" >&2; exit 1;;
  esac
done

[ -z "$URL" ] && { echo "用法: bash scripts/process_job.sh --url <url> [--bookmark] [--read-jd] [--send --msg f]" >&2; exit 1; }

fail_loud_if_down

# ---- 自管模式：开 lease + tab ----
if [ "$SELF_MANAGED" -eq 1 ]; then
  cooldown "${BOOKMARK_COOLDOWN:-$ACTION_INTERVAL_SECONDS}"
  bz_browse_start "$URL" enhanced || { echo "FAIL_LOUD: browse-start 失败" >&2; exit 1; }
  LEASE="$BZ_LEASE"; TAB="$BZ_TAB"
  cleanup(){ [ "$KEEP" -eq 0 ] && bz_browse_end "$LEASE" || true; }
  trap cleanup EXIT
fi

# ---- 读取页面，撞墙检查 ----
HTML=$(bz_browse_html "$LEASE" "$TAB" 2>&1)
verify_wall "$HTML"

# ---- 书签（点「感兴趣」）----
if [ "$BOOKMARK" -eq 1 ]; then
  [ "$SELF_MANAGED" -eq 0 ] && cooldown "${BOOKMARK_COOLDOWN:-$ACTION_INTERVAL_SECONDS}"
  WF=$(bz_ui "$TAB" wait-for --selector ".btn-interest" 2>&1) || true
  echo "$WF" | grep -qi "verify\|验证码" && { echo "FAIL_LOUD: 撞验证墙"; exit 3; }
  bz_ui "$TAB" click --selector ".btn-interest" 2>&1
  HTML2=$(bz_browse_html "$LEASE" "$TAB" 2>&1)
  if echo "$HTML2" | grep -q "取消感兴趣"; then
    echo "[ok] 书签成功 (按钮已变 取消感兴趣)"
  else
    echo "[warn] 未确认书签成功, 请人工核对截图"
  fi
fi

# ---- 读 JD / 招聘方（真实招聘方来自 .job-boss-info .name，非 user-nav）----
if [ "$READJD" -eq 1 ]; then
  "$PYTHON" - "$HTML" "$OUT_JSON" <<'PY'
import sys, re, json
html, out = sys.argv[1], sys.argv[2]
def block(cls):
    m = re.search(r'class="[^"]*' + re.escape(cls) + r'[^"]*"[^>]*>(.*?)</', html, re.S)
    return re.sub(r'<[^>]+>', '', m.group(1)).strip() if m else ""
data = {
    "recruiter": block("job-boss-info"),     # 真实招聘方（.job-boss-info .name 取首行去"在线"）
    "recruiter_name": block("name"),
    "jd": block("job-sec-text"),             # 完整 JD
    "company": block("sider-company"),
    "_note": "严禁用 user-nav 当招聘方(那是登录账号本人)"
}
json.dump(data, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("OK ->", out)
PY
fi

# ---- 发消息（授权门控，真实光标）----
if [ "$SEND" -eq 1 ]; then
  [ "${AUTHORIZED:-0}" = "1" ] || { echo "FAIL_LOUD: 未授权, 禁止发送 (需 AUTHORIZED=1)" >&2; exit 4; }
  [ -z "$MSG" ] && { echo "FAIL_LOUD: 缺少 --msg 消息文件" >&2; exit 1; }
  [ -f "$MSG" ] || { echo "FAIL_LOUD: 消息文件不存在: $MSG" >&2; exit 1; }
  TEXT=$(cat "$MSG")
  cooldown "${SEND_COOLDOWN:-$ACTION_INTERVAL_SECONDS}"
  WF=$(bz_ui "$TAB" wait-for --selector ".btn-chat" 2>&1) || true
  echo "$WF" | grep -qi "verify\|验证码" && { echo "FAIL_LOUD: 撞验证墙"; exit 3; }
  bz_ui "$TAB" click --selector ".btn-chat" 2>&1
  sleep 2
  bz_ui "$TAB" click --selector ".chat-input" 2>&1
  bz_ui "$TAB" type --text "$TEXT" 2>&1
  bz_ui "$TAB" click --selector ".btn-send" 2>&1
  HTML3=$(bz_browse_html "$LEASE" "$TAB" 2>&1)
  if echo "$HTML3" | grep -q "$TEXT"; then
    echo "[ok] 消息已发送 (页面含该文本)"
  else
    echo "[warn] 未确认发送, 请人工核对截图"
  fi
fi
