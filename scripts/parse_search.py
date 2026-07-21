#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
parse_search.py - 解析 BOSS 搜索结果页 HTML，提取岗位卡片（仅标准库）。

用法:
  python3 scripts/parse_search.py <html_or_json> [out_json]
    - 入参可为「原始 HTML 文件」或「brs browse-html 的 {"path":...} JSON 包装」，自动解引用。
    - 输出每卡: {title, company, city_raw, tags, url}
    - ⚠️ 不提取薪资：BOSS 卡片 .job-salary 被字体反爬混淆，直读为乱码；薪资须从 JD 详情页取。

选择器: a.job-name(标题+href) / .boss-name(公司) / .company-location(城市) / .tag-list li(经验·学历)
"""
import sys, os, re, json, html

def _load_html(path):
    raw = open(path, encoding="utf-8", errors="replace").read()
    s = raw.lstrip()
    # 兼容 brs browse-html 的 JSON 包装 {"path": "/artifacts/x.html"}
    if s.startswith("{"):
        try:
            j = json.loads(raw)
            p = j.get("path") or j.get("file")
            if p:
                if not os.path.isabs(p):
                    home = os.environ.get("AGENT_BROWSER_RUNTIME_HOME", "")
                    for c in (home + p, home + "/" + p.lstrip("/")):
                        if home and os.path.exists(c):
                            p = c; break
                if os.path.exists(p):
                    return open(p, encoding="utf-8", errors="replace").read()
        except Exception:
            pass  # 不是 JSON 包装，按原始 HTML 处理
    return raw

def _text(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s).strip())

def extract_cards(path):
    t = _load_html(path)
    cards = []
    # 顺序无关 lookahead：href 与 class 前后皆可
    name_re = re.compile(
        r'<a\b(?=[^>]*\bclass="[^"]*\bjob-name\b)(?=[^>]*\bhref="([^"]+)")[^>]*>(.*?)</a>',
        re.S,
    )
    matches = list(name_re.finditer(t))
    for idx, m in enumerate(matches):
        href = m.group(1)
        title = _text(m.group(2))
        # 截到「下一个 job-name 锚点」边界：杜绝长卡(>1600字)字段静默丢失或跨卡串扰
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(t)
        seg = t[m.start():end]
        comp = city = ""
        cm = re.search(r'class="[^"]*\bboss-name\b[^"]*"[^>]*>(.*?)</span>', seg, re.S)
        if cm: comp = _text(cm.group(1))
        lm = re.search(r'class="[^"]*\bcompany-location\b[^"]*"[^>]*>(.*?)</span>', seg, re.S)
        if lm: city = _text(lm.group(1))
        tags = []
        tlm = re.search(r'class="[^"]*\btag-list\b[^"]*"[^>]*>(.*?)</ul>', seg, re.S)  # 限定卡内，防跨卡串扰
        if tlm:
            tags = [_text(x) for x in re.findall(r"<li[^>]*>(.*?)</li>", tlm.group(1))]
        # 协议相对 //www... -> https:；其余相对路径补域名
        if href.startswith("//"):
            url = "https:" + href
        elif href.startswith("http"):
            url = href
        else:
            url = "https://www.zhipin.com" + href
        cards.append({"title": title, "company": comp, "city_raw": city, "tags": tags, "url": url})
    return cards

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("用法: parse_search.py <html_or_json> [out_json]")
    cards = extract_cards(sys.argv[1])
    if len(sys.argv) > 2:
        json.dump(cards, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    else:
        for c in cards:
            print(c["title"], "|", c["company"], "|", c["city_raw"], "|", c["tags"], "|", c["url"][:60])
    print("TOTAL", len(cards), file=sys.stderr)
