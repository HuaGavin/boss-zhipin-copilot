#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
audit_icebreaker.py - 破冰话术自检 gate（两用版，通用化）
用法:
  python3 scripts/audit_icebreaker.py <recruiter_jd.json> <话术.md> [<事实库.md>] [<keys.json>]

模式 A（权威，推荐）: 提供 keys.json = {岗位id: {jd:[...], fact:[...]}}
  -> 逐岗检查话术是否含 JD 原文关键词 + 事实库凭据，要求
     JD命中率>=90% 且 事实命中率>=90%，否则列为未达标需重写。
  -> 写字典的过程本身即「强制逐岗精读 JD」的纪律。

模式 B（兜底粗筛，无 keys 时）: 自动抽词，仅把「JD关键词命中=0 且 事实实体<2」
  的岗标为需复查（抓真正空白/跳步的岗），不用于判定达标，避免误伤转述型好话术。

⚠️ 话术必须引用 JD 具体业务词 + 匹配用户真实事实；严禁编造、严禁套模板。
"""
import json, re, sys, os

STOP = set("""岗位职责 任职要求 加分项 熟悉 了解 负责 设计 优化 提升 搭建 推动 具备 年以上 及以上
产品 用户 业务 数据 增长 经验 能力 团队 公司 我们 需要 通过 进行 基于 结合 能够 可以 以及
对于 相关 其他 包括 根据 完成 实现 支持 分析 管理 开发 运营 使用 提供 维度 场景 平台
的一 的是 并且 或者 这种 那种 一个 一种 这个 那个 主要 关键 核心 重点 不同 各种 职责 要求
""".split())

def split_blocks(md):
    # N2: 接受 1~3 级标题（# / ## / ###），单 # 编号标题也能分块。
    headings = list(re.finditer(r"^#{1,3}\s+(.*)$", md, re.M))
    # 先算每个标题的候选 key：显式前缀数字（### 1. / ### 1、 / ## 1 等）优先，否则用位置序号。
    items = []
    for idx, m in enumerate(headings):
        text = m.group(1).strip()
        nm = re.match(r"^(\d+)", text)
        key = int(nm.group(1)) if nm else (idx + 1)
        explicit = bool(nm)
        start = m.end()
        end = headings[idx + 1].start() if idx + 1 < len(headings) else len(md)
        body = (text + "\n" + md[start:end]).strip()
        items.append((key, explicit, body))
    # N3: 组装时「显式编号优先」，避免无编号标题的位置序号与某显式编号碰撞后互相覆盖
    #     （如前置 `## 通用背景`(位置1) 不再覆盖 `## 1. 岗位A`）。无编号且撞到显式编号者视作
    #     前言/补充，不占岗位槽（消费方只按岗位正整数索引取块）。
    # F2: 重复「显式编号」(如 `## 1. A` 与 `## 1. B`)不再静默覆盖第一块，改用 `key_dupN`
    #     后缀保留，避免第一块话术在权威模式被丢弃致误判「未达标」。
    explicit_keys = {k for k, e, _ in items if e}
    seen = {}
    blocks = {}
    for key, explicit, body in items:
        if not explicit and key in explicit_keys:
            continue
        if key in blocks and not explicit:
            continue
        if key in blocks:
            # 显式编号碰撞：累计重复次数，生成不丢块的 key
            seen[key] = seen.get(key, 0) + 1
            new_key = f"{key}_dup{seen[key]}"
            sys.stderr.write(
                f"[warn] audit_icebreaker: 显式编号 {key} 重复出现，第二块存为 {new_key}（避免覆盖丢失）\n"
            )
            blocks[new_key] = body
        else:
            blocks[key] = body
    return blocks

def auto_keys(jd_text, top=10):
    toks = re.findall(r'[A-Za-z]{2,}|[\u4e00-\u9fa5]{3,}', jd_text or "")
    out = []
    for t in toks:
        tl = t.strip()
        if not tl:
            continue
        if re.match(r'^[A-Za-z]{2,}$', tl):
            out.append(tl); continue
        if tl in STOP:
            continue
        if any(c in '岗位职责职要求加分熟悉了解负责设计优化提升搭建推动' for c in tl):
            continue
        if len(tl) >= 3:
            out.append(tl)
    seen, res = set(), []
    for t in out:
        if t not in seen:
            seen.add(t); res.append(t)
    return res[:top]

def fact_entities(fact_md):
    comps = set(re.findall(r'[\u4e00-\u9fa5]{2,8}(?:科技|网络|教育|传媒|文化|信息|智能|互娱|学堂|外卖|编程|星光|博望|立方|宇宙|四方)?', fact_md))
    nums = set(re.findall(r'\d+(?:\.\d+)?\s?%', fact_md))
    return comps, nums

def main():
    if len(sys.argv) < 3:
        print("用法: python3 scripts/audit_icebreaker.py <jd_json> <话术md> [<事实库md>] [<keys_json>]")
        sys.exit(1)
    jd = json.load(open(sys.argv[1], encoding="utf-8"))
    # 止血（C1）：read-jd 偶发输出单 dict 时，视作单元素列表，避免 enumerate 遍历 key 崩溃
    if isinstance(jd, dict):
        jd = [jd]
    md = open(sys.argv[2], encoding="utf-8").read()
    fact_md = open(sys.argv[3], encoding="utf-8").read() if len(sys.argv) > 3 and os.path.exists(sys.argv[3]) else ""
    keys_path = sys.argv[4] if len(sys.argv) > 4 else ""
    if not keys_path or not os.path.exists(keys_path):
        cand = os.path.join(os.path.dirname(os.path.abspath(__file__)), "audit_keys.json")
        keys_path = cand if os.path.exists(cand) else ""
    keys = json.load(open(keys_path, encoding="utf-8")) if keys_path else None
    blocks = split_blocks(md)

    if keys:
        # F8: keys 的键须为 recruiter_jd.json 中每岗的 `id`（与话术块按位置序号 1..N 对齐）；
        #     写 keys 时务必用 process_job --read-jd 产物的 id 作键，否则无法对上话术块。
        print(f"[权威模式] keys={os.path.basename(keys_path)}（键=recruiter_jd.json 的 id）  要求: JD>=90% 且 事实>=90%\n")
        print("| # | 岗位 | JD命中 | 事实命中 | 招聘方 | 判定 |")
        print("|---|------|------|------|------|------|")
        tj = th = tf = fh = 0; fail = []
        for i, x in enumerate(jd, 1):
            blk = blocks.get(i, ""); pid = x.get("id", "")
            k = keys.get(pid, {})
            jk = k.get("jd", []); fk = k.get("fact", [])
            jh = [w for w in jk if w.lower() in blk.lower()]
            fh_ = [w for w in fk if w.lower() in blk.lower()]
            tj += len(jk); th += len(jh); tf += len(fk); fh += len(fh_)
            ok = (len(jk) == 0 or len(jh) / len(jk) >= 0.9) and (len(fk) == 0 or len(fh_) / len(fk) >= 0.9)
            if not ok:
                fail.append((i, pid, x.get('title', '')[:16], f"JD{len(jh)}/{len(jk)} 事实{len(fh_)}/{len(fk)}"))
            print(f"| {i} | {x.get('title','')[:18]} | {len(jh)}/{len(jk)} | {len(fh_)}/{len(fk)} | {x.get('recruiter','')} | {'✅' if ok else '❌'} |")
        print()
        print(f"JD 关键词总命中率: {th}/{tj} = {100*th/tj:.1f}%" if tj else "JD 无字典")
        print(f"事实库凭据总命中率: {fh}/{tf} = {100*fh/tf:.1f}%" if tf else "事实无字典")
        print(f"未达标岗: {fail if fail else '无'}")
        print("GATE 判定:", "通过 ✅" if not fail else "未通过 ❌ → 回写话术重写未达标岗")
        sys.exit(0 if not fail else 2)
    else:
        print("[兜底粗筛] 无 keys 字典，仅抓完全空白/跳步岗（JD命中=0 且 事实实体<2）\n")
        print("| # | 岗位 | JD自动命中 | 事实实体 | 招聘方 |")
        print("|---|------|------|------|------|")
        fcomps, fnums = fact_entities(fact_md) if fact_md else (set(), set())
        blank = []
        for i, x in enumerate(jd, 1):
            blk = blocks.get(i, "")
            keys_ = auto_keys(x.get("jd", ""))
            jh = [k for k in keys_ if k.lower() in blk.lower()]
            fhit = [c for c in fcomps if c and c in blk] + [n for n in fnums if n in blk]
            flag = ""
            if (len(keys_) and len(jh) == 0) and (fact_md and len(fhit) < 2):
                flag = "  ⚠️完全空白"; blank.append(i)
            print(f"| {i} | {x.get('title','')[:18]} | {len(jh)}/{len(keys_)} | {len(fhit)} | {x.get('recruiter','')} |{flag}")
        print("\n完全空白岗(需重点复查):", blank if blank else "无")

if __name__ == "__main__":
    main()
