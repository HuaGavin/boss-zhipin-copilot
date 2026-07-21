#!/usr/bin/env bash
# search_jobs.sh - 多词检索 BOSS 岗位，复用同一 tab，只读收集结果卡 -> 待评估 CSV。
#
# 用法:
#   bash scripts/search_jobs.sh [--profile profile.yaml] [--queries "词1,词2"] \
#        [--out .work/candidates.csv] [--scrolls 3]
#
# 查询词来源：--queries 优先，否则读 profile.search.queries。
# 后端：经 common.sh 选 BrowserDriver（默认 brs）；hosted（codex）短路到 emit_plan 生成提示词。
# 红线：只读——仅检索+提取，绝不书签/发送/点开岗位；复用同 tab（禁频繁开关）；撞墙 exit 3。
# 产物 CSV 列：岗位名/公司名/城市/经验要求/URL（无薪资列——卡片薪资被反爬混淆，须从 JD 详情页取）。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PROFILE="${PROFILE:-./profile.yaml}"
QUERIES_CLI=""
OUT="${WORK_DIR:-.work}/candidates.csv"
SCROLLS=3
JOB_URL="https://www.zhipin.com/web/geek/job"
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2;;
    --queries) QUERIES_CLI="$2"; shift 2;;
    --out)     OUT="$2"; shift 2;;
    --scrolls) SCROLLS="$2"; shift 2;;
    *) echo "未知参数: $1" >&2; exit 1;;
  esac
done

# ---- 查询词：CLI 优先，否则 profile.search.queries ----
QUERIES=()
if [ -n "$QUERIES_CLI" ]; then
  IFS=',' read -ra QUERIES <<< "$QUERIES_CLI"
else
  while IFS= read -r line; do [ -n "$line" ] && QUERIES+=("$line"); done < <(
    "$PYTHON" -c "import sys,yaml;d=yaml.safe_load(open(sys.argv[1],encoding='utf-8')) or {};[print(q) for q in ((d.get('search',{}) or {}).get('queries',[]) or [])]" "$PROFILE"
  )
fi
[ "${#QUERIES[@]}" -eq 0 ] && { echo "FAIL_LOUD: 无查询词（--queries 或 profile.search.queries 均为空）" >&2; exit 1; }

# ---- hosted 短路：生成 Codex @Chrome 提示词 ----
if backend_is_hosted; then
  bz_emit_plan --search-queries "$(IFS=,; echo "${QUERIES[*]}")"
  exit 0
fi

fail_loud_if_down
WORK="${WORK_DIR:-.work}"; mkdir -p "$WORK" "$(dirname "$OUT")"
rm -f "$WORK"/_search_*.json "$WORK"/_search_*.html

# ---- 开一个 tab 全程复用（R8 单 lease 连续 tab；禁频繁开关）----
bz_browse_start "$JOB_URL" enhanced || { echo "FAIL_LOUD: browse-start 失败" >&2; exit 1; }
LEASE="$BZ_LEASE"; TAB="$BZ_TAB"
trap 'bz_browse_end "$LEASE"' EXIT

i=0
for q in "${QUERIES[@]}"; do
  q="$(echo "$q" | sed 's/^ *//;s/ *$//')"; [ -z "$q" ] && continue
  i=$((i + 1)); echo "===== [$i] 检索: $q =====" >&2
  bz_browse_nav "$LEASE" "$TAB" "$JOB_URL" >/dev/null 2>&1 || true   # 复用同 tab 回搜索页清空
  cooldown 3
  bz_ui "$TAB" click --selector ".search-input-box .input" >/dev/null 2>&1 || true
  cooldown 1
  bz_ui "$TAB" type --text "$q" >/dev/null 2>&1 || true
  cooldown 1
  bz_ui "$TAB" click --selector ".search-btn" >/dev/null 2>&1 || true
  cooldown 5
  for _ in $(seq 1 "$SCROLLS"); do
    bz_ui "$TAB" scroll --delta 1200 >/dev/null 2>&1 || true
    cooldown 2
  done
  HTML=$(bz_browse_html "$LEASE" "$TAB" 2>&1)
  verify_wall "$HTML"                       # 撞验证墙 -> exit 3 停手
  echo "$HTML" > "$WORK/_search_$i.html"
  "$PYTHON" "$SCRIPT_DIR/parse_search.py" "$WORK/_search_$i.html" "$WORK/_search_$i.json" || true
  cooldown "${ACTION_INTERVAL_SECONDS:-5}"
done

# ---- 合并所有卡片 -> 待评估 CSV（按 URL 去重）----
"$PYTHON" - "$OUT" "$WORK"/_search_*.json <<'PY'
import sys, json, csv
out, files = sys.argv[1], sys.argv[2:]
seen, rows = set(), []
for fp in files:
    try:
        cards = json.load(open(fp, encoding="utf-8"))
    except Exception:
        continue
    for c in cards:
        url = (c.get("url") or "").strip()
        if not url or url in seen:
            continue
        seen.add(url)
        rows.append({
            "岗位名": c.get("title", ""),
            "公司名": c.get("company", ""),
            "城市": c.get("city_raw", ""),
            "经验要求": " ".join(c.get("tags", []) or []),
            "URL": url,
        })
with open(out, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["岗位名", "公司名", "城市", "经验要求", "URL"])
    w.writeheader(); w.writerows(rows)
print(f"[ok] 合并 {len(rows)} 条去重候选 -> {out}")
PY
echo "[ok] 检索完成 -> $OUT（下一步：filter_library.py 过滤打分）" >&2
