#!/usr/bin/env python3
# intent_filters.py - 求职意图 -> BOSS 搜索页筛选器编码（6 维度全覆盖）
#
# 设计目标（长期能力，非一次性）：
#   1) 覆盖全面：公司规模 / 融资阶段 / 工作经验 / 学历要求 / 薪资待遇 / 求职类型 全部可映射到 BOSS ka 编码。
#   2) 主动识别意图：给定自由文本（如"想找一家B轮以上的中型公司做后端开发"），自动解析出
#      隐含的筛选条件并展开成编码；同时支持从 profile.yaml 推导默认筛选。
#   3) 筛选优先：search_jobs.sh 先按本模块产出的 spec 在搜索阶段应用筛选，再收集结果，
#      避免下游读大量不符岗的 JD。
#
# 本文件是「中文意图 <-> BOSS 编码」的唯一事实来源，与 references/boss_selectors.md 五 严格一致。
# CLI:
#   python intent_filters.py parse  "<自由文本>" [--profile p.yaml] [--query Q]
#       -> 自由文本 + profile 默认值合并后的 FilterSpec JSON（意图覆盖 profile）
#   python intent_filters.py from-profile --profile p.yaml
#       -> 仅从 profile 推导的 FilterSpec（无自由文本时）
#   python intent_filters.py codes  --json '<FilterSpec>'
#       -> 展开成可直接 click 的 {dim: [ka_option_selectors...]}（含触发器/选项选择器）
# FilterSpec 结构:
#   {"query":"", "city":"", "scale":[int...], "stage":[int...], "exp":[int...],
#    "degree":[int...], "salary":int|None, "jobType":int|None}
#   单选维度 salary/jobType 用单值(或 None=不限)；复选维度用列表。

import sys, json, re, argparse

# ---------- 编码表（与 boss_selectors.md 五 严格一致）----------
# (code, lower_bound, upper_bound) 边界左闭右开；单位：人
SCALE = [(301, 0, 20), (302, 20, 100), (303, 100, 500), (304, 500, 1000),
         (305, 1000, 10000), (306, 10000, 10**9)]
STAGE = {801: "未融资", 802: "天使轮", 803: "A轮", 804: "B轮", 805: "C轮",
         806: "D轮及以上", 807: "已上市", 808: "不需要融资"}
EXP = {101: "经验不限", 102: "应届生", 103: "1年以内", 104: "1-3年", 105: "3-5年",
       106: "5-10年", 107: "10年以上", 108: "在校生"}
DEGREE = {202: "大专", 203: "本科", 204: "硕士", 205: "博士", 206: "高中",
          208: "中专/中技", 209: "初中及以下"}
SALARY = {402: "3K以下", 403: "3-5K", 404: "5-10K", 405: "10-20K", 406: "20-50K", 407: "50K以上"}
JOBTYPE = {1901: "全职", 1903: "兼职"}

# 经验年限下界（用于 "X年以上" 映射；不限/应届/在校不自动纳入）
EXP_MIN = {102: 0, 103: 0, 104: 1, 105: 3, 106: 5, 107: 10, 108: 0}
# 学历层级（用于 "X以上" 映射）
DEGREE_LEVEL = {209: 0, 206: 1, 208: 1, 202: 2, 203: 3, 204: 4, 205: 5}
# 融资阶段层级（用于 "X轮以上" 映射；808 不需要融资不计入等级序列）
STAGE_LEVEL = {801: 0, 802: 1, 803: 2, 804: 3, 805: 4, 806: 5, 807: 6}

# ka 域后缀（对应 boss_selectors.md 五 的 sel-job-rec-<dim>-<code>）
DIM_KA = {"scale": "scale", "stage": "stage", "exp": "exp",
          "degree": "degree", "salary": "salary", "jobType": "jobType"}
# 单选维度（salary/jobType 只能选一档）；其余复选
SINGLE_SELECT = {"salary", "jobType"}

# 常见求职城市
CITIES = ["北京", "上海", "广州", "深圳", "杭州", "成都", "南京", "武汉",
          "西安", "苏州", "天津", "重庆", "远程", "长沙", "青岛"]
# 常见岗位角色关键词（长匹配优先）
ROLES = ["产品经理", "产品总监", "产品负责人", "产品运营", "后端开发", "后端工程师",
         "前端开发", "前端工程师", "全栈开发", "全栈工程师", "算法工程师", "数据分析",
         "数据工程师", "运维工程师", "测试开发", "测试工程师", "软件开发", "开发工程师",
         "架构师", "增长运营", "用户运营", "内容运营", "市场运营", "销售", "市场营销",
         "HR", "人力资源", "财务", "设计师", "UI设计", "UX设计"]


# ---------- 编码展开原语 ----------
def scale_codes(lo=None, hi=None):
    """返回与 [lo, hi) 有交集的规模档 code 列表（复选）。"""
    lo = 0 if lo is None else int(lo)
    hi = 10**9 if hi is None else int(hi)
    return [c for c, a, b in SCALE if a < hi and b > lo]


def stage_codes_ge(word):
    """'B轮以上' -> [804,805,806,807]；支持 天使/A/B/C/D/上市。"""
    table = {"天使": 802, "a": 803, "b": 804, "c": 805, "d": 806, "上市": 807}
    w = word.replace("轮", "").strip().lower()  # 归一化："B轮" -> "b"
    if w not in table:
        return []
    base = table[w]
    base_lvl = STAGE_LEVEL[base]
    return [c for c, lvl in STAGE_LEVEL.items() if lvl >= base_lvl and c != 808]


def exp_codes_min(years):
    """'X年以上' -> 经验下限 >= X 的档（不含 不限/应届/在校）。"""
    y = int(years)
    return sorted(c for c, ym in EXP_MIN.items() if c not in (101, 102, 108) and ym >= y)


def salary_code_floor(floor_yuan):
    """薪资下限(元) -> 单档编码（取 lower>=floor 的最低档；超最高档取最高）。"""
    bands = [(402, 0), (403, 3000), (404, 5000), (405, 10000), (406, 20000), (407, 50000)]
    cand = [c for c, lo in bands if lo >= int(floor_yuan)]
    return min(cand) if cand else 407


def degree_codes_min(word):
    """'本科以上' -> [203,204,205]。"""
    order = {"初中": 209, "高中": 206, "中专": 208, "大专": 202, "本科": 203, "硕士": 204, "博士": 205}
    target = order.get(word.strip())
    if target is None:
        return []
    lvl = DEGREE_LEVEL[target]
    return [c for c, l in DEGREE_LEVEL.items() if l >= lvl]


# ---------- 自由文本意图解析 ----------
def parse_intent(text, profile_spec=None):
    """解析自由文本 -> FilterSpec（意图覆盖 profile_spec 默认值）。"""
    spec = {"query": "", "city": "", "scale": [], "stage": [], "exp": [],
            "degree": [], "salary": None, "jobType": None}
    if profile_spec:
        for k, v in profile_spec.items():
            spec[k] = v if v is not None else spec[k]

    if not text:
        return spec

    # 城市
    for c in CITIES:
        if c in text:
            spec["city"] = c
            break
    # 求职类型（单选）
    if "兼职" in text:
        spec["jobType"] = 1903
    elif "全职" in text:
        spec["jobType"] = 1901
    # 岗位关键词（最长匹配优先）
    found = [r for r in sorted(ROLES, key=len, reverse=True) if r in text]
    if found:
        spec["query"] = " ".join(dict.fromkeys(found))  # 去重保序
    # 公司规模
    if any(w in text for w in ["小型", "初创", "创业公司", "小团队"]):
        spec["scale"] = scale_codes(0, 100)
    elif any(w in text for w in ["中型", "中型企业", "中厂"]):
        spec["scale"] = scale_codes(100, 1000)
    elif any(w in text for w in ["大型", "大厂", "大型企业"]):
        spec["scale"] = scale_codes(1000, 10**9)
    else:
        m = re.search(r"(\d+)\s*-\s*(\d+)\s*人", text)            # 100-499人
        if m:
            spec["scale"] = scale_codes(int(m.group(1)), int(m.group(2)) + 1)
        else:
            m = re.search(r"(\d+)\s*人\s*以内", text)
            if m:
                spec["scale"] = scale_codes(0, int(m.group(1)))
            else:
                m = re.search(r"(\d+)\s*人\s*以上", text)
                if m:
                    spec["scale"] = scale_codes(int(m.group(1)), 10**9)
    # 融资阶段（"X轮以上" 优先；否则命中具体阶段名）
    ge = re.search(r"(天使|A轮|B轮|C轮|D轮|上市)\s*(以上|及以上)", text)
    if ge:
        spec["stage"] = stage_codes_ge(ge.group(1))
    else:
        for code, name in STAGE.items():
            if name in text and code not in spec["stage"]:
                spec["stage"].append(code)
    # 工作经验
    m = re.search(r"(\d+)\s*-\s*(\d+)\s*年", text)                 # 3-5年
    if m:
        spec["exp"] = exp_codes_min(int(m.group(1)))
    else:
        m = re.search(r"(\d+)\s*年以上?", text)
        if m:
            spec["exp"] = exp_codes_min(int(m.group(1)))
        elif "应届" in text:
            spec["exp"] = [102]
        elif "在校" in text or "实习" in text:
            spec["exp"] = [108]
    # 学历
    ge = re.search(r"(初中|高中|中专|大专|本科|硕士|博士)\s*(以上|及以上)", text)
    if ge:
        spec["degree"] = degree_codes_min(ge.group(1))
    else:
        for w in ["博士", "硕士", "本科", "大专", "中专", "高中"]:
            if w in text:
                spec["degree"] = [{"博士": 205, "硕士": 204, "本科": 203,
                                   "大专": 202, "中专": 208, "高中": 206}[w]]
                break
    # 薪资（支持 X-YK / X万以上 / XK以上 / XK）
    m = re.search(r"(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s*[kK]", text)  # 20-50K
    if m:
        spec["salary"] = salary_code_floor(float(m.group(1)) * 1000)
    else:
        m = re.search(r"(\d+(?:\.\d+)?)\s*万\s*以上", text)
        if m:
            spec["salary"] = salary_code_floor(float(m.group(1)) * 10000)
        else:
            m = re.search(r"(\d+(?:\.\d+)?)\s*[kK]\s*以上", text)
            if m:
                spec["salary"] = salary_code_floor(float(m.group(1)) * 1000)
            else:
                m2 = re.search(r"(\d+(?:\.\d+)?)\s*[kK]", text)
                if m2:
                    spec["salary"] = salary_code_floor(float(m2.group(1)) * 1000)
    return spec


# ---------- 从 profile 推导默认 spec ----------
def spec_from_profile(profile_path):
    try:
        import yaml
    except ImportError:
        yaml = None
    spec = {"query": "", "city": "", "scale": [], "stage": [], "exp": [],
            "degree": [], "salary": None, "jobType": None}
    if not profile_path:
        return spec
    if yaml is None:
        sys.exit("FAIL_LOUD: 需要 PyYAML 才能解析 profile（pip install -r requirements.txt）")
    try:
        d = yaml.safe_load(open(profile_path, encoding="utf-8")) or {}
    except Exception:
        return spec
    th = (d.get("thresholds") or {})
    if "scale_min" in th or "scale_max" in th:
        spec["scale"] = scale_codes(th.get("scale_min"), th.get("scale_max"))
    if "salary_floor" in th:
        spec["salary"] = salary_code_floor(int(th.get("salary_floor") or 0))
    if "seniority_years" in th:
        spec["exp"] = exp_codes_min(int(th.get("seniority_years") or 0))
    if "stage_allow" in th:  # 兼容（用户已删，保留支持）
        allow = th["stage_allow"]
        rev = {v: k for k, v in STAGE.items()}
        spec["stage"] = [rev[a] for a in allow if a in rev]
    return spec


# ---------- 展开成可点击选择器 ----------
def spec_to_selectors(spec):
    """FilterSpec -> {dim: {"trigger": selector, "options": [selectors]}}。"""
    out = {}
    for dim, ka in DIM_KA.items():
        codes = spec.get(dim) or []
        if dim in SINGLE_SELECT:
            codes = [codes] if isinstance(codes, int) else (codes[:1] if codes else [])
        else:
            codes = [c for c in codes if c]
        if not codes:
            continue
        trigger = ('.condition-filter-select:has(li[ka="sel-job-rec-%s-0"]) '
                   '.current-select' % ka)
        opts = ['li[ka="sel-job-rec-%s-%s"]' % (ka, c) for c in codes]
        out[dim] = {"trigger": trigger, "options": opts,
                    "single": dim in SINGLE_SELECT}
    return out


def build_spec(profile_path=None, intent_text=None, overrides=None):
    """合并优先级：profile 默认 < 意图文本覆盖 < 显式 CLI 维度覆盖。"""
    spec = spec_from_profile(profile_path)
    if intent_text:
        spec = parse_intent(intent_text, spec)
    if overrides:
        for k, v in overrides.items():
            if v is not None:
                spec[k] = v
    return spec


def _parse_codes(s):
    """'302,303' -> [302,303]；'406' -> 406；'' -> None。"""
    s = (s or "").strip()
    if not s:
        return None
    if "," in s:
        return [int(x) for x in s.split(",") if x.strip()]
    return int(s)


def apply_plan_tsv(spec):
    """FilterSpec -> TSV 行 `dim\\tTRIGGER\\tOPTION_SELECTOR`（每选项一行，shell 可循环点击）。"""
    sel = spec_to_selectors(spec)
    lines = []
    for dim, info in sel.items():
        for opt in info["options"]:
            lines.append("%s\t%s\t%s" % (dim, info["trigger"], opt))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("parse")
    p.add_argument("text", nargs="?", default="")
    p.add_argument("--profile", default=None)
    p.add_argument("--query", default=None, help="覆盖解析出的 query（角色关键词）")
    fp = sub.add_parser("from-profile")
    fp.add_argument("--profile", default=None)
    fc = sub.add_parser("codes")
    fc.add_argument("--json", dest="json_str", required=True)
    # build: 合并 profile + 意图文本 + 显式维度覆盖 -> 最终 FilterSpec
    bld = sub.add_parser("build", help="合并 profile/意图/CLI 覆盖 -> FilterSpec")
    bld.add_argument("--profile", default=None)
    bld.add_argument("--intent", default=None, help="自由文本意图（覆盖 profile 同名维度）")
    bld.add_argument("--scale", default=None)
    bld.add_argument("--stage", default=None)
    bld.add_argument("--exp", default=None)
    bld.add_argument("--degree", default=None)
    bld.add_argument("--salary", default=None)
    bld.add_argument("--jobtype", default=None)
    bld.add_argument("--filters-json", default=None, help="显式 FilterSpec JSON（最高优先级）")
    # apply-plan: FilterSpec -> 可点击 TSV（dim<TAB>trigger<TAB>option）
    ap2 = sub.add_parser("apply-plan", help="FilterSpec -> shell 可循环点击的 TSV")
    ap2.add_argument("--json", dest="json_str", required=True)
    args = ap.parse_args()

    if args.cmd == "parse":
        base = spec_from_profile(args.profile) if args.profile else None
        spec = parse_intent(args.text, base)
        if args.query is not None:
            spec["query"] = args.query
        print(json.dumps(spec, ensure_ascii=False))
    elif args.cmd == "from-profile":
        print(json.dumps(spec_from_profile(args.profile), ensure_ascii=False))
    elif args.cmd == "codes":
        spec = json.loads(args.json_str)
        print(json.dumps(spec_to_selectors(spec), ensure_ascii=False, indent=2))
    elif args.cmd == "build":
        overrides = {}
        if args.scale is not None:
            overrides["scale"] = _parse_codes(args.scale)
        if args.stage is not None:
            overrides["stage"] = _parse_codes(args.stage)
        if args.exp is not None:
            overrides["exp"] = _parse_codes(args.exp)
        if args.degree is not None:
            overrides["degree"] = _parse_codes(args.degree)
        if args.salary is not None:
            overrides["salary"] = _parse_codes(args.salary)
        if args.jobtype is not None:
            overrides["jobType"] = _parse_codes(args.jobtype)
        if args.filters_json:
            overrides.update(json.loads(args.filters_json))
        spec = build_spec(args.profile, args.intent, overrides or None)
        print(json.dumps(spec, ensure_ascii=False))
    elif args.cmd == "apply-plan":
        spec = json.loads(args.json_str)
        print(apply_plan_tsv(spec))


if __name__ == "__main__":
    main()
