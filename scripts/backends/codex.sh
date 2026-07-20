#!/usr/bin/env bash
# backends/codex.sh - hosted 后端：OpenAI Codex + Chrome 扩展
# Codex 不是本地 CLI，而是由 Codex 桌面端通过 @Chrome 提示词驱动的真实登录态浏览器。
# 因此本后端不实际驱动浏览器，而是把一次任务翻译成可直接粘贴进 Codex 的步骤提示词；
# 本 skill 的非浏览器逻辑层（profile / filter / icebreaker / 库管理）仍全部本地运行。
# 安装: https://developers.openai.com/codex/app/chrome-extension
set -euo pipefail

bz_mode() { echo hosted; }

bz_status() {
  echo "[hosted] Codex 托管浏览器模式：跳过本地就绪检查。" >&2
  echo "[hosted] 请确保：① 已安装 OpenAI Codex 桌面端并启用 Chrome 插件；② 已在 Chrome 登录 BOSS 直聘；③ 在 Codex 允许 zhipin.com 域名。" >&2
}

# hosted 模式不需要真实驱动函数，调用即提示走 emit_plan
bz_browse_start() { bz_emit_plan "$@"; }
bz_browse_html()  { bz_emit_plan "$@"; }
bz_browse_end()   { bz_emit_plan "$@"; }
bz_ui()           { bz_emit_plan "$@"; }
bz_extract()      { bz_emit_plan "$@"; }

# 把一次 job 的 argv 翻译成 Codex @Chrome 提示词
# 入参即驱动脚本的原始 argv（如 process_job.sh 的 --url ... --bookmark --send --msg f）
bz_emit_plan() {
  local url="" bookmark=0 readjd=0 send=0 scan=0 msg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --url)   url="$2"; shift 2;;
      --bookmark) bookmark=1; shift;;
      --read-jd)  readjd=1; shift;;
      --send)  send=1; shift;;
      --scan-chat) scan=1; shift;;
      --msg)   msg="$2"; shift 2;;
      --out|--lease|--tab|--keep) shift 2 2>/dev/null || shift;;
      *) shift;;
    esac
  done

  echo "══════════════════════════════════════════════════════════════"
  echo " 把下面的内容粘贴到 Codex（@Chrome 会自动调用已登录的真实 Chrome）："
  echo "══════════════════════════════════════════════════════════════"
  echo ""
  echo "@Chrome 请在 BOSS 直聘执行以下任务（用真实光标与键鼠，不要走查询串捷径）："
  echo ""
  [ -n "$url" ] && echo "目标岗位页: $url"
  echo ""
  if [ "$scan" -eq 1 ]; then
    echo "1) 打开聊天列表页（https://www.zhipin.com/web/geek/chat），滚动加载全部会话；"
    echo "   提取每条会话的（招聘方名称 / 公司 / 岗位）三元组，原样以 JSON 数组返回给我（只读，不要改动任何状态）。"
  fi
  if [ "$bookmark" -eq 1 ]; then
    echo "1) 进入页面后，点击「感兴趣」按钮（选择器 .btn-interest）完成收藏；"
    echo "   收藏后确认按钮文案变为「取消感兴趣」即成功；"
  fi
  if [ "$readjd" -eq 1 ]; then
    echo "2) 读取完整 JD：提取 .job-sec-text 全文、招聘方 .job-boss-info .name（去「在线」）、公司 .sider-company；"
    echo "   把以上字段原样返回给我（不要改写）。"
  fi
  if [ "$send" -eq 1 ]; then
    echo "3) 点击「立即沟通」（.btn-chat）打开对话框，在 .chat-input 用真实键入粘贴下面这段话并发送（.btn-send）："
    echo "   ───── 破冰话术 ─────"
    if [ -n "$msg" ] && [ -f "$msg" ]; then cat "$msg"; else echo "（未提供 --msg 文件，请先由 audit_icebreaker 生成本地话术）"; fi
    echo "   ───────────────────"
  fi
  echo ""
  echo "安全约束（务必遵守）："
  echo " - 遇到任何验证墙（验证码/拖动滑块/「请完成」）立即停止，不要强行通过；"
  echo " - 每次点击/键入之间自然停顿，不要机械连点；"
  echo " - 仅做上面列出的动作，不要额外浏览或改动其他状态。"
  echo ""
  echo "执行后请把页面返回的关键文本（JD 字段 / 发送确认）贴回给我，以便本 skill 入库与自检。"
}
