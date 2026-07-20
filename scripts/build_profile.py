#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_profile.py - 从「一句目标 + 可选简历」生成 profile.yaml 草稿。
用法:
  python3 scripts/build_profile.py --goal "我想找5年以上经验、月薪4万以上的策略产品经理(北京)" \
                                   [--resume 简历.md] [--out profile.yaml]

⚠️ 本脚本只做启发式抽取，产出 DRAFT。Agent 必须复核补全（尤其 hard_exclude / fact_anchors）后再使用。
   不预置任何平台的默认排除列表——硬排除只来自用户真实背景，由 Agent 填充。
"""
import argparse, re, sys, datetime

try:
    import yaml
except ImportError:
    sys.exit("FAIL_LOUD: 需要 pyyaml，请先 `pip install pyyaml`（见 requirements.txt）")

CITIES = ["北京", "上海", "广州", "深圳", "杭州", "成都", "南京", "武汉", "西安",
          "苏州", "重庆", "天津", "长沙", "青岛", "厦门", "宁波", "合肥", "东莞"]

def extract_salary(text):
    # 4万 -> 40000 ; 4万以上 -> 40000 ; 25K -> 25000 ; 40-60K -> 40000(取下限)
    m = re.search(r"(\d+(?:\.\d+)?)\s*万", text)
    if m:
        return int(float(m.group(1)) * 10000)
    m = re.search(r"(\d+)\s*[Kk]", text)
    if m:
        return int(m.group(1)) * 1000
    return 0

def extract_seniority(text):
    # 限制为 1-2 位数字（排除「2026年」这类 4 位年份），且前后不得紧贴数字（C13）
    m = re.search(r"(?<!\d)(\d{1,2})\s*年以上", text) \
        or re.search(r"(?<!\d)(\d{1,2})\s*年(?![\d])", text)
    return int(m.group(1)) if m else 0

def extract_city(text):
    for c in CITIES:
        if c in text:
            return c
    return ""

def extract_role(text):
    # 去掉括号及其中内容（城市注释等）
    t = re.sub(r"[（(].*?[)）]", "", text).strip()
    # 角色词的引导字符排除 数字/元/万/以上/空白/虚词，避免把「月薪4万元以上的」吞进角色名
    m = re.search(
        r"[^0-9元万以上\s的个这那该此其]{0,6}?"
        r"(?:策略|高级|资深|初级|产品|运营|增长|开发|算法|测试|前端|后端|全栈|数据|项目)?"
        r"(?:经理|总监|专家|工程师|负责人|主管|leader)",
        t,
    )
    return (m.group(0).strip() if m else t)[:20]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--goal", required=True, help="一句求职目标")
    ap.add_argument("--resume", help="可选简历/工作事实文件路径")
    ap.add_argument("--out", default="profile.yaml", help="输出 profile.yaml 路径")
    args = ap.parse_args()

    goal = args.goal
    city = extract_city(goal)
    salary = extract_salary(goal)
    seniority = extract_seniority(goal)
    role = extract_role(goal)

    queries = []
    for q in [f"{role} {city}".strip(), f"{city} {role}".strip(), role]:
        if q and q not in queries:
            queries.append(q)

    profile = {
        "meta": {
            "candidate_name": "",
            "generated_at": datetime.date.today().isoformat(),
            "notes": "由 build_profile.py 启发式抽取，DRAFT，Agent 须复核补全",
        },
        "goal": goal,
        "search": {
            "city": city,
            "queries": queries,
        },
        "thresholds": {
            "city": city,
            "salary_floor": salary,
            "seniority_years": seniority,
            "stage_allow": [],
            "scale_max": 0,
            "employment_type": "",
        },
        "hard_exclude": [],   # Agent 必须按用户真实背景填充
        "boost_keywords": [], # Agent 按目标方向填充
        "fact_anchors": [],   # Agent 从简历/事实文件提取，必须真实可溯源
    }

    if args.resume:
        profile["meta"]["notes"] += f"；简历输入: {args.resume}"

    with open(args.out, "w", encoding="utf-8") as f:
        yaml.safe_dump(profile, f, allow_unicode=True, sort_keys=False)

    print(f"[ok] 草稿 profile -> {args.out}")
    print(f"      解析: city={city or '不限'} salary_floor={salary or '不限'} "
          f"seniority_years={seniority or '不限'} role={role}")
    print("      ⚠️ 请 Agent 复核并补全 hard_exclude / boost_keywords / fact_anchors 后再使用。")

if __name__ == "__main__":
    main()
