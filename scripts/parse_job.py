#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
parse_job.py - 从 BOSS 直聘岗位详情页 HTML 稳健解析岗位信息（仅用标准库）。

用法:
  python3 scripts/parse_job.py [--url <岗位URL>] [<html_file>]
      - 不传 html_file 时从 stdin 读 HTML
      - 输出单条 JSON 到 stdout: {"id","title","jd","recruiter","company"}
        （process_job.sh 会把它包成单元素列表写入 jd_read.json）

解析策略（DOM / class 优先，非脆弱字符串正则）:
  - jd       : .job-sec-text 的**全部文本**（合并所有文本节点，不在首个 </ 截断）
  - recruiter : .job-boss-info .name 文本，去「在线」二字
  - company   : .sider-company（回退 .job-boss-info 整体文本）
  - title     : .job-name（回退 <title>）
  - id        : --url 的哈希；无 url 时取 title+company 的哈希
"""
import sys
import re
import json
import hashlib
import argparse
from html.parser import HTMLParser


class JobParser(HTMLParser):
    """追踪 class 祖先栈，按 class 提取目标字段（兼容多 class / 单双引号）。"""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.class_stack = []          # 每层元素的 class 集合
        self.jd_parts = []             # .job-sec-text 全部文本
        self.recruiter_buf = []        # .job-boss-info .name 文本
        self.company_buf = []          # .sider-company 文本
        self.boss_buf = []             # .job-boss-info 整体文本（company 回退）
        self.jobname_buf = []          # .job-name 文本
        self.title_buf = []            # <title> 文本
        self._title_active = False

    @staticmethod
    def _classes(attrs):
        d = dict(attrs)
        return set((d.get("class") or "").split())

    def _inside(self, cls):
        return any(cls in s for s in self.class_stack)

    def handle_starttag(self, tag, attrs):
        classes = self._classes(attrs)
        self.class_stack.append(classes)
        if tag == "title":
            self._title_active = True

    def handle_endtag(self, tag):
        if tag == "title":
            self._title_active = False
        if self.class_stack:
            self.class_stack.pop()

    def handle_data(self, data):
        t = data.strip()
        if not t:
            return
        top = self.class_stack[-1] if self.class_stack else set()

        # JD：在任意 .job-sec-text 内
        if self._inside("job-sec-text"):
            self.jd_parts.append(t)

        # 招聘方姓名：.job-boss-info 内、当前元素为 .name
        if "name" in top and self._inside("job-boss-info"):
            self.recruiter_buf.append(t)

        # 公司：.sider-company 内
        if "sider-company" in top:
            self.company_buf.append(t)

        # 公司回退：.job-boss-info 整体文本
        if self._inside("job-boss-info"):
            self.boss_buf.append(t)

        # 岗位名：.job-name 子树内
        if self._inside("job-name"):
            self.jobname_buf.append(t)

        # <title> 文本
        if self._title_active:
            self.title_buf.append(t)

    def result(self, url=""):
        jd = " ".join(self.jd_parts).strip()
        recruiter = re.sub(r"在线", "", " ".join(self.recruiter_buf)).strip()
        if self.company_buf:
            company = " ".join(self.company_buf).strip()
        else:
            company = " ".join(self.boss_buf).strip()
        title = " ".join(self.jobname_buf).strip() or " ".join(self.title_buf).strip()
        if url:
            id_ = "jd-" + hashlib.md5(url.encode("utf-8")).hexdigest()[:16]
        else:
            id_ = "jd-" + hashlib.md5((title + company).encode("utf-8")).hexdigest()[:16]
        return {
            "id": id_,
            "title": title,
            "jd": jd,
            "recruiter": recruiter,
            "company": company,
        }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="", help="岗位 URL（用于生成稳定 id 哈希）")
    ap.add_argument("html_file", nargs="?", help="HTML 文件；缺省读 stdin")
    args = ap.parse_args()

    if args.html_file:
        with open(args.html_file, encoding="utf-8", errors="replace") as f:
            html = f.read()
    else:
        html = sys.stdin.read()

    p = JobParser()
    try:
        p.feed(html)
    except Exception as e:  # 解析异常不应崩溃，返回尽可能多的信息
        sys.stderr.write(f"[warn] HTML 解析异常(部分字段可能缺失): {e}\n")
    data = p.result(args.url)
    json.dump(data, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
