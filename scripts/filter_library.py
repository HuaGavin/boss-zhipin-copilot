#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
filter_library.py - profile 驱动的岗位过滤 + 评分 + （可选）入库。
用法:
  python3 scripts/filter_library.py --profile profile.yaml --input 待评估.csv \
      [--out 评估结果.json] [--library target_library.csv] [--id-prefix BJ]

说明:
  - input: 待评估岗位 CSV（搜索结果导出，或现有库）。按表头字典映射，列名灵活。
  - profile: 驱动硬排除 / 门槛 / 加分关键词（见 references/profile_schema.md）。
  - 若给 --library，则把「通过」且库中无同 URL 的岗位追加进库（状态=已收藏(感兴趣)）。
  - 输出 JSON: {passed:[...], rejected:[...], summary:{...}}
"""
import argparse, csv, json, re, sys, datetime

try:
    import yaml
except ImportError:
    sys.exit("FAIL_LOUD: 需要 pyyaml，请先 `pip install pyyaml`")

def parse_salary(s):
    m = re.search(r"(\d+(?:\.\d+)?)\s*[Kk]", s)
    if m:
        return int(float(m.group(1)) * 1000)
    m = re.search(r"(\d+(?:\.\d+)?)\s*万", s)
    if m:
        return int(float(m.group(1)) * 10000)
    return None

def parse_seniority(s):
    m = re.search(r"(\d+)\s*年", s)
    return int(m.group(1)) if m else None

def parse_scale(s):
    m = re.search(r"(\d+)", s)
    return int(m.group(1)) if m else None

def evaluate(row, profile):
    reasons = []
    blob = " ".join(str(v) for v in row.values())

    # 硬排除
    for cat in profile.get("hard_exclude", []) or []:
        hits = [k for k in (cat.get("keywords", []) or []) if k and k in blob]
        if hits:
            reasons.append(f"硬排除[{cat.get('category','')}]:{','.join(hits)}")

    th = profile.get("thresholds", {}) or {}
    city = (th.get("city") or "").strip()
    if city and city not in str(row.get("城市", "")):
        reasons.append(f"城市不符(期望{city})")

    floor = int(th.get("salary_floor", 0) or 0)
    sal = parse_salary(str(row.get("薪资", "")))
    if floor and (sal is None or sal < floor):
        reasons.append(f"薪资低于{floor}(实测:{sal})")

    sy = int(th.get("seniority_years", 0) or 0)
    yrs = parse_seniority(str(row.get("经验要求", "")))
    if sy and (yrs is None or yrs < sy):
        reasons.append(f"经验不足{sy}年(实测:{yrs})")

    allow = th.get("stage_allow", []) or []
    if allow and str(row.get("公司阶段", "")).strip() not in allow:
        reasons.append(f"阶段不在白名单{allow}")

    smax = int(th.get("scale_max", 0) or 0)
    if smax:
        scl = parse_scale(str(row.get("公司规模", "")))
        if scl and scl > smax:
            reasons.append(f"规模>{smax}(实测:{scl})")

    et = (th.get("employment_type") or "").strip()
    if et and et not in str(row.get("类型", "")) and et not in blob:
        reasons.append(f"雇佣类型不符(期望{et})")

    # 评分
    score = 50
    hits = []
    if not reasons:
        boost = profile.get("boost_keywords", []) or []
        hits = [k for k in boost if k and k in blob]
        score += len(hits) * 5
        if city and city in str(row.get("城市", "")):
            score += 10
        if floor and sal and sal >= floor:
            score += 10
        if sy and yrs and yrs >= sy:
            score += 10
    score = min(score, 100)

    decision = "reject" if reasons else "collect"
    return decision, score, reasons, hits

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default="profile.yaml")
    ap.add_argument("--input", required=True, help="待评估 CSV")
    ap.add_argument("--out", default=".work/eval_result.json")
    ap.add_argument("--library", help="可选：通过项追加进此库 CSV")
    ap.add_argument("--id-prefix", default="BJ")
    args = ap.parse_args()

    with open(args.profile, encoding="utf-8") as f:
        profile = yaml.safe_load(f)
    rows = list(csv.DictReader(open(args.input, encoding="utf-8-sig")))

    passed, rejected = [], []
    for r in rows:
        decision, score, reasons, hits = evaluate(r, profile)
        rec = {k: r.get(k, "") for k in r}
        rec["评分"] = score
        rec["排除原因"] = "; ".join(reasons)
        rec["命中加分词"] = ",".join(hits)
        if decision == "collect":
            passed.append(rec)
        else:
            rejected.append(rec)

    out = {
        "summary": {
            "total": len(rows), "passed": len(passed), "rejected": len(rejected),
            "evaluated_at": datetime.datetime.now().isoformat(),
        },
        "passed": passed,
        "rejected": rejected,
    }
    import os
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    json.dump(out, open(args.out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

    # 入库
    if args.library:
        lib_rows = []
        fieldnames = None
        existing_urls = set()
        if os.path.exists(args.library):
            with open(args.library, encoding="utf-8-sig") as f:
                rd = csv.DictReader(f)
                fieldnames = rd.fieldnames
                for lr in rd:
                    lib_rows.append(lr)
                    existing_urls.add((lr.get("URL", "") or "").strip())
        if not fieldnames:
            fieldnames = ["岗位ID", "岗位名", "公司名", "公司规模", "公司阶段",
                          "行业", "城市", "薪资", "经验要求", "类型", "状态", "URL"]
        # 确保有扩展列（含入库必须的 岗位ID / 状态）
        for col in ["岗位ID", "状态", "评分", "排除原因", "招聘方", "更新时间"]:
            if col not in fieldnames:
                fieldnames.append(col)
        max_id = 0
        for lr in lib_rows:
            m = re.search(r"(\d+)", str(lr.get("岗位ID", "")))
            if m:
                max_id = max(max_id, int(m.group(1)))
        added = 0
        for p in passed:
            url = (p.get("URL", "") or "").strip()
            if url and url in existing_urls:
                continue
            max_id += 1
            new = {c: p.get(c, "") for c in fieldnames}
            new["岗位ID"] = f"{args.id_prefix}-{max_id:04d}"
            new["状态"] = "已收藏(感兴趣)"
            new["更新时间"] = datetime.date.today().isoformat()
            lib_rows.append(new)
            existing_urls.add(url)
            added += 1
        with open(args.library, "w", encoding="utf-8-sig", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fieldnames)
            w.writeheader()
            w.writerows(lib_rows)
        print(f"[ok] 追加 {added} 岗进库 -> {args.library}")

    print(f"[ok] 评估完成 total={len(rows)} passed={len(passed)} rejected={len(rejected)} -> {args.out}")

if __name__ == "__main__":
    main()
