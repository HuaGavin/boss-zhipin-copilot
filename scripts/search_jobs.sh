#!/usr/bin/env bash
# search_jobs.sh - 多词检索 BOSS 岗位，复用同一 tab，只读收集结果卡 -> candidates.csv。
#
# 用法:
#   bash scripts/search_jobs.sh [--profile profile.yaml] [--queries "词1,词2"] \
#        [--out .work/candidates.csv] [--scrolls 3] \
#        [--intent "自由文本求职意图"] \
#        [--scale 302,303] [--stage 804,805] [--exp 106] [--degree 203] [--salary 406] [--jobtype 1901]
#
# 筛选优先级（全程在「搜索结果页」源头应用，先于收集，避免下游读不符岗 JD）：
#   1) profile.thresholds 默认（scale_min/max, salary_floor, seniority_years 自动推导）
#   2) --intent "文本" 自动解析隐含条件（如"B轮以上中型公司"）覆盖同名维度
#   3) 显式 --scale/--stage/--exp/--degree/--salary/--jobtype 最高优先级覆盖
#   六维度全覆盖：公司规模/融资阶段/工作经验/学历要求/薪资待遇/求职类型（编码见 boss_selectors.md 五）。
#   不传任何筛选参数 = 仅按 profile 默认；profile 也无限制 = 不过滤。
# 后端：经 common.sh 选 BrowserDriver（默认 brs）；hosted（codex）短路到 emit_plan 生成提示词。
# 红线：只读——仅检索+提取，绝不书签/发送/点开岗位；复用同 tab（禁频繁开关）；撞墙 exit 3。
# 产物 CSV 列：岗位名/公司名/城市/经验要求/URL（无薪资列——卡片薪资被反爬混淆，须从 JD 详情页取）。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# run_py: <script.py> [args...] —— 以 Windows 盘符形式定位脚本（cygpath -w），
#         规避 Git Bash 把 /c/... POSIX 路径误转为 K:\c\... 的 MSYS 参数转换问题；
#         不 cd，故调用方的相对路径参数（如 .work/__search_1.html）仍按原 cwd 正确解析。
run_py() {
  local script="$1"; shift
  local win_script
  if command -v cygpath >/dev/null 2>&1; then
    win_script="$(cygpath -w "$SCRIPT_DIR/$script" 2>/dev/null || echo "$SCRIPT_DIR/$script")"
  else
    win_script="$SCRIPT_DIR/$script"
  fi
  "$PYTHON" "$win_script" "$@"
}

PROFILE="${PROFILE:-./profile.yaml}"
QUERIES_CLI=""
OUT="${WORK_DIR:-.work}/candidates.csv"
SCROLLS=3
SCALE_CLI=""; STAGE_CLI=""; EXP_CLI=""; DEGREE_CLI=""; SALARY_CLI=""; JOBTYPE_CLI=""; INTENT=""
JOB_URL="https://www.zhipin.com/web/geek/job"
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2;;
    --queries) QUERIES_CLI="$2"; shift 2;;
    --out)     OUT="$2"; shift 2;;
    --scrolls) SCROLLS="$2"; shift 2;;
    --intent)  INTENT="$2"; shift 2;;
    --scale)   SCALE_CLI="$2"; shift 2;;
    --stage)   STAGE_CLI="$2"; shift 2;;
    --exp)     EXP_CLI="$2"; shift 2;;
    --degree)  DEGREE_CLI="$2"; shift 2;;
    --salary)  SALARY_CLI="$2"; shift 2;;
    --jobtype) JOBTYPE_CLI="$2"; shift 2;;
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

# ---- 构建筛选规格（6 维度全覆盖）----
# 优先级：profile 默认 < --intent 文本解析 < 显式 --scale/--stage/... 覆盖
# 编码映射与选择器点位见 references/boss_selectors.md 五 + scripts/intent_filters.py（唯一事实来源）。
BUILD_ARGS=(--profile "$PROFILE")
[ -n "$INTENT" ]      && BUILD_ARGS+=(--intent "$INTENT")
[ -n "$SCALE_CLI" ]   && BUILD_ARGS+=(--scale "$SCALE_CLI")
[ -n "$STAGE_CLI" ]   && BUILD_ARGS+=(--stage "$STAGE_CLI")
[ -n "$EXP_CLI" ]     && BUILD_ARGS+=(--exp "$EXP_CLI")
[ -n "$DEGREE_CLI" ]  && BUILD_ARGS+=(--degree "$DEGREE_CLI")
[ -n "$SALARY_CLI" ]  && BUILD_ARGS+=(--salary "$SALARY_CLI")
[ -n "$JOBTYPE_CLI" ] && BUILD_ARGS+=(--jobtype "$JOBTYPE_CLI")

FILTER_SPEC=$(run_py intent_filters.py build "${BUILD_ARGS[@]}")
echo "[filters] 最终筛选规格: $FILTER_SPEC" >&2
# 展开成可点击计划（TSV: dim<TAB>trigger<TAB>option，每选项一行）
FILTER_PLAN=$(run_py intent_filters.py apply-plan --json "$FILTER_SPEC")
if [ -n "$FILTER_PLAN" ]; then
  echo "[filters] 将点击以下筛选项:" >&2
  echo "$FILTER_PLAN" | while IFS=$'\t' read -r d t o; do echo "   - $d: $o" >&2; done
fi

# 在结果页应用全部维度筛选（hover 触发器 -> 逐档点选；每点一档后须重新 hover）。
# 纯 CSS :hover 显隐，选项 li 常驻 DOM；点位实测见 boss_selectors.md 五。
apply_all_filters() {
  local tab="$1"
  [ -z "$FILTER_PLAN" ] && return 0
  while IFS=$'\t' read -r dim trigger opt; do
    [ -z "$opt" ] && continue
    bz_ui "$tab" move --selector "$trigger" >/dev/null 2>&1 || true
    cooldown 1
    bz_ui "$tab" click --selector "$opt" >/dev/null 2>&1 || true
    cooldown 2
  done <<< "$FILTER_PLAN"
}

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
  apply_all_filters "$TAB"                 # 每词搜索后重新应用全部维度筛选（换词后是否保留未实测，稳妥重放）
  for _ in $(seq 1 "$SCROLLS"); do
    bz_ui "$TAB" scroll --delta 1200 >/dev/null 2>&1 || true
    cooldown 2
  done
  HTML=$(bz_browse_html "$LEASE" "$TAB" 2>&1)
  verify_wall "$HTML"                       # 撞验证墙 -> exit 3 停手
  echo "$HTML" > "$WORK/_search_$i.html"
  run_py parse_search.py "$WORK/_search_$i.html" "$WORK/_search_$i.json" || true
  cooldown "${ACTION_INTERVAL_SECONDS:-5}"
done

# ---- 合并所有卡片 -> candidates.csv（按 URL 去重）----
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
