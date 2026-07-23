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
# Windows Git Bash 下 win-native python 收不到 POSIX 路径（MSYS 把 C:/Users 错转成 C:\c\Users），
# 用 cygpath 转 Windows 原生路径给 python 用；带 fallback，非 Windows 不动。
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) SCRIPT_DIR_W="$(cygpath -w "$SCRIPT_DIR" 2>/dev/null || echo "$SCRIPT_DIR")";;
  *) SCRIPT_DIR_W="$SCRIPT_DIR";;
esac

# ---- 统一授权门控（最早执行，必须在 source common.sh / 加载后端之前）----
# F9/F10: 书签与发送均属「改账号状态动作」，需 AUTHORIZED=1 才放行。提到最前可保证
# 本地 brs（后端加载即探测 brs.js）与 hosted codex 在未授权时**统一 exit 4**，
# 不会因后端缺失先报 exit 1 而掩盖授权语义。
SEND_RAW=0; BOOKMARK_RAW=0
for _a in "$@"; do
  [ "$_a" = "--send" ] && SEND_RAW=1
  [ "$_a" = "--bookmark" ] && BOOKMARK_RAW=1
done
AUTHORIZED="${AUTHORIZED:-0}"
if { [ "$SEND_RAW" -eq 1 ] || [ "$BOOKMARK_RAW" -eq 1 ]; } && [ "$AUTHORIZED" != "1" ]; then
  echo "FAIL_LOUD: 未授权，禁止生成/执行书签或发送计划 (R5 每岗授权)。设置 AUTHORIZED=1 后重试。" >&2
  exit 4
fi

source "$SCRIPT_DIR/common.sh"

# hosted 模式：不实际驱动，生成外部 Agent 步骤提示词后退出
# （必须在参数解析前执行，以保留原始 argv 传给 bz_emit_plan）
if backend_is_hosted; then bz_emit_plan "$@"; exit 0; fi

BOOKMARK=0; READJD=0; SEND=0; KEEP=0
URL=""; LEASE=""; TAB=""; OUT_JSON="${WORK_DIR:-.work}/recruiter_jd.json"; MSG=""
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
  cooldown "${BOOKMARK_COOLDOWN:-${ACTION_INTERVAL_SECONDS:-5}}"
  bz_browse_start "$URL" enhanced || { echo "FAIL_LOUD: browse-start 失败" >&2; exit 1; }
  LEASE="$BZ_LEASE"; TAB="$BZ_TAB"
  cleanup(){ [ "$KEEP" -eq 0 ] && bz_browse_end "$LEASE" || true; }
  trap cleanup EXIT
fi

# ---- 复用模式：同 tab 导航到目标岗（自管模式 browse-start 已带 URL）----
if [ "$SELF_MANAGED" -eq 0 ]; then
  cooldown "${ACTION_INTERVAL_SECONDS:-5}"
  bz_browse_nav "$LEASE" "$TAB" "$URL" >/dev/null || { echo "FAIL_LOUD: browse-nav 失败" >&2; exit 1; }
  sleep 3
fi

# ---- 读取页面，撞墙检查 ----
HTML=$(bz_browse_html "$LEASE" "$TAB" 2>&1)
verify_wall "$HTML"

# ---- 书签（点「感兴趣」）----
if [ "$BOOKMARK" -eq 1 ]; then
  bump_daily_cap   # R3 日限额（改状态动作）
  [ "$SELF_MANAGED" -eq 0 ] && cooldown "${BOOKMARK_COOLDOWN:-${ACTION_INTERVAL_SECONDS:-5}}"
  WF=$(bz_ui "$TAB" wait-for --selector ".btn-interest" 2>&1) || true
  echo "$WF" | grep -qi "verify\|验证码" && { echo "FAIL_LOUD: 撞验证墙"; exit 3; }
  bz_ui "$TAB" click --selector ".btn-interest" 2>&1 || { echo "[warn] 选择器未命中(.btn-interest)，请人工核对" >&2; }
  HTML2=$(bz_browse_html "$LEASE" "$TAB" 2>&1)
  if echo "$HTML2" | grep -q "取消感兴趣"; then
    echo "[ok] 书签成功 (按钮已变 取消感兴趣)"
  else
    echo "[warn] 未确认书签成功, 请人工核对截图"
  fi
fi

# ---- 读 JD / 招聘方（真实招聘方来自 .job-boss-info .name，非 user-nav）----
if [ "$READJD" -eq 1 ]; then
  mkdir -p "$(dirname "$OUT_JSON")"
  PARSED=$(mktemp)
  # 用稳健的 DOM 解析（parse_job.py）替换脆弱正则；HTML 经 stdin 传入
  "$PYTHON" "$SCRIPT_DIR_W/parse_job.py" --url "$URL" >"$PARSED" <<<"$HTML" \
    || { echo "FAIL_LOUD: parse_job.py 解析 JD 失败" >&2; rm -f "$PARSED"; exit 1; }
  # 单 dict 包成单元素列表写入（满足 audit_icebreaker.py 的「列表」契约，见 C1）
  "$PYTHON" - "$OUT_JSON" "$PARSED" <<'PY'
import sys, json
out, src = sys.argv[1], sys.argv[2]
d = json.load(open(src, encoding="utf-8"))
if isinstance(d, dict):
    d = [d]
json.dump(d, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("OK ->", out)
PY
  rm -f "$PARSED"
fi

# ---- 发消息（授权门控，真实光标）----
if [ "$SEND" -eq 1 ]; then
  [ "${AUTHORIZED:-0}" = "1" ] || { echo "FAIL_LOUD: 未授权, 禁止发送 (需 AUTHORIZED=1)" >&2; exit 4; }
  [ -z "$MSG" ] && { echo "FAIL_LOUD: 缺少 --msg 消息文件" >&2; exit 1; }
  [ -f "$MSG" ] || { echo "FAIL_LOUD: 消息文件不存在: $MSG" >&2; exit 1; }
  TEXT=$(cat "$MSG")
  bump_daily_cap   # R3 日限额（改状态动作）
  cooldown "${SEND_COOLDOWN:-${ACTION_INTERVAL_SECONDS:-20}}"
  # 选择器为 2026-07-20 实战校准值（见 boss_selectors.md 三）
  # 岗位关闭（无 .btn-startchat 且页面含「职位已关闭」）→ 跳过不算撞墙
  if echo "$HTML" | grep -q "职位已关闭"; then
    echo "[skip] 该岗位已关闭，跳过发送（请在岗位库标记「岗位关闭」）"; exit 6
  fi
  WF=$(bz_ui "$TAB" wait-for --selector ".btn-startchat" 2>&1) || true
  echo "$WF" | grep -qi "verify\|验证码" && { echo "FAIL_LOUD: 撞验证墙"; exit 3; }
  bz_ui "$TAB" click --selector ".btn-startchat" 2>&1 || { echo "[warn] 选择器未命中(.btn-startchat)，请人工核对" >&2; }
  sleep 3
  # 输入框：聊天弹窗为 #chat-input(contenteditable)，旧版为 textarea.input-area，依次尝试
  if ! bz_ui "$TAB" click --selector "#chat-input" >/dev/null 2>&1; then
    bz_ui "$TAB" click --selector "textarea.input-area" 2>&1 || { echo "[warn] 输入框未命中(#chat-input / textarea.input-area)" >&2; }
  fi
  bz_ui "$TAB" type --text "$TEXT" 2>&1
  sleep 1
  if ! bz_ui "$TAB" click --selector ".btn-send" >/dev/null 2>&1; then
    bz_ui "$TAB" click --selector ".send-message" 2>&1 || { echo "[warn] 发送按钮未命中(.btn-send / .send-message)" >&2; }
  fi
  sleep 3
  HTML3=$(bz_browse_html "$LEASE" "$TAB" 2>&1)
  SNIPPET=$("$PYTHON" -c "import sys;d=sys.stdin.buffer.read().decode('utf-8','ignore');print(d[:20])" <<<"$TEXT")   # 取话术前 20 字符做固定串校验（字符级，避免 head -c 字节截断半字误判）
  # 严格送达判定：编辑框已清空(草稿不残留) 且 页面消息区含话术前缀（含 [送达] 更佳）
  # 注意：不能「管道 + heredoc」同喂 stdin（heredoc 抢占 stdin 致 SIGPIPE/141），改走临时文件
  HTML_TMP=$(mktemp); printf '%s' "$HTML3" > "$HTML_TMP"
  VERDICT=$("$PYTHON" - "$HTML_TMP" "$SNIPPET" <<'PY'
import sys, re
html = open(sys.argv[1], encoding="utf-8", errors="ignore").read(); snip = sys.argv[2]
m = re.search(r'id="chat-input"[^>]*>(.*?)</div>', html, re.S)
editor = (m.group(1).strip() if m else "")
in_editor = snip in editor
in_page = snip in html
delivered = 'status-delivery' in html
if in_page and not in_editor: print("SENT" + ("_DELIVERED" if delivered else ""))
elif in_editor: print("DRAFT_ONLY")
else: print("UNKNOWN")
PY
)
  rm -f "$HTML_TMP"
  case "$VERDICT" in
    SENT_DELIVERED) echo "[ok] 消息已发送并送达 ([送达] 标记确认)";;
    SENT)           echo "[ok] 消息已发送 (编辑框已清空, 消息区含话术)";;
    DRAFT_ONLY)     echo "FAIL_LOUD: 话术仍在输入框草稿态，未发送成功，请人工核对" >&2; exit 7;;
    *)              echo "[warn] 未确认发送, 请人工核对截图";;
  esac
fi
