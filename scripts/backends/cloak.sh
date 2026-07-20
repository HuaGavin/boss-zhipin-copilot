#!/usr/bin/env bash
# backends/cloak.sh - 候选本地后端：CloakBrowser (CloakHQ, MIT)
# 源码级改指纹的隐身 Chromium + humanize=True（贝塞尔鼠标/逐字键入/惯性滚动）+ Playwright 直接替换。
# 安装: https://github.com/CloakHQ/cloakbrowser
#
# ⚠️ 本文件为「骨架 + API 映射」，驱动尚未实现。设置 BZC_BACKEND=cloak 时所有驱动函数 fail-loud，
#    指向本文件与 references/browser_backend.md。欢迎按下方映射实现（用 Python + cloakbrowser 包）。
#
# ---- 待实现的 API 映射（对照 BrowserDriver 契约）----
#   bz_status       -> 校验 Chrome 已启动且 cloakbrowser 可连接（launch() 成功 / CDP 可达）；无 companion 概念，用 humanize=True 保证拟人
#   bz_browse_start -> from cloakbrowser import launch; browser=launch(humanize=True, headless=False); page=browser.new_page(); page.goto(url); 导出 BZ_LEASE=浏览器句柄 BZ_TAB=page
#   bz_browse_html  -> page.content()
#   bz_browse_end   -> browser.close()
#   bz_ui           -> page.click(selector) / page.type(selector, text) / page.mouse / page.scroll；humanize=True 已提供贝塞尔轨迹与逐字键入
#   bz_extract      -> page.evaluate(jsfile 内容) 或 page.add_script_tag；需把 zhipin-chat.extract.js 改为接收 page 而非 broker 上下文
#   注意：cloakbrowser 是 Playwright 路线，无 broker 租约；BZ_LEASE/BZ_TAB 改为浏览器/页面对象句柄。
set -euo pipefail

bz_mode() { echo local; }

bz_status() {
  echo "FAIL_LOUD: cloak 后端尚未实现驱动。" >&2
  echo "  见 scripts/backends/cloak.sh 顶部的 API 映射 与 references/browser_backend.md。" >&2
  echo "  安装 CloakBrowser: https://github.com/CloakHQ/cloakbrowser （pip install cloakbrowser）" >&2
  echo "  实现后可设 BZC_BACKEND=cloak 启用本地隐身路线。" >&2
  exit 1
}

bz_browse_start() { bz_status; }
bz_browse_html()  { bz_status; }
bz_browse_end()   { bz_status; }
bz_ui()           { bz_status; }
bz_extract()      { bz_status; }
bz_emit_plan()    { bz_status; }
