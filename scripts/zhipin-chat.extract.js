// BOSS 直聘聊天列表提取器：定位左侧联系人面板 -> 滚动 -> 取 HTML -> 解析会话。
// 在 broker 容器（Node.js）中执行，依赖 ui.* 与浏览器交互。
// 提取器在页面上下文用真实光标交互，比 browse-html 直读更稳。
export const schema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    action: { type: 'string', enum: ['read', 'scroll_down', 'scroll_up'], default: 'read' },
    scrollBy: { type: 'integer', default: 1200 },
    pauseMs: { type: 'integer', default: 1200 },
  },
};

function decodeHtml(value) {
  return String(value || '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code) => String.fromCodePoint(Number.parseInt(code, 16)));
}

function cleanText(value) {
  return decodeHtml(String(value || '')).replace(/\s+/g, ' ').trim();
}

function parseContacts(html) {
  const items = [];
  if (!html) return items;
  const blocks = html.split(/<div[^>]*class=["']friend-content[^"']*["'][^>]*>/);
  for (let i = 1; i < blocks.length; i += 1) {
    const block = blocks[i].split('</div><div class="friend-content')[0];
    const nameMatch = block.match(/<span class=["']name-text["']>([^<]+)<\/span>/);
    if (!nameMatch) continue;
    const name = cleanText(nameMatch[1]);
    const allSpans = Array.from(block.matchAll(/<span[^>]*>([^<]+)<\/span>/g)).map((m) => cleanText(m[1]));
    const nameIdx = allSpans.findIndex((t) => t === name);
    let company = '', role = '';
    if (nameIdx >= 0) {
      company = allSpans[nameIdx + 1] || '';
      role = allSpans[nameIdx + 2] || '';
    }
    const lastMsgMatch = block.match(/<span class=["']last-msg-text["']>([^<]*)<\/span>/);
    const lastMsg = lastMsgMatch ? cleanText(lastMsgMatch[1]) : '';
    const timeMatch = block.match(/<span class=["']message-time["']>([^<]*)<\/span>/);
    const time = timeMatch ? cleanText(timeMatch[1]) : '';
    items.push({ name, company, role, lastMsg, time });
  }
  return items;
}

export async function extract({ pageHtml, url, finalUrl, params = {}, ui }) {
  const action = params.action || 'read';
  const scrollBy = Number(params.scrollBy) || 1200;
  const pauseMs = Number(params.pauseMs) || 1200;

  // 真实滚动容器是 .user-list；回退 .user-list-content / .chat-user.v2
  const selectors = ['.user-list', '.user-list-content', '.chat-user.v2'];
  let lastMoveError = null;
  for (const selector of selectors) {
    try {
      await ui.move({ selector, durationMs: 260 });
      lastMoveError = null;
      break;
    } catch (error) {
      lastMoveError = error;
    }
  }
  if (lastMoveError) {
    return {
      ok: false,
      error: 'MOVE_TO_CHAT_PANEL_FAILED',
      details: lastMoveError?.message || String(lastMoveError),
      url: finalUrl || url,
      collectedAt: new Date().toISOString(),
    };
  }

  if (action === 'scroll_down') {
    await ui.scroll({ count: 2, deltaY: scrollBy, pauseMs: 500 });
  } else if (action === 'scroll_up') {
    await ui.scroll({ count: 2, deltaY: -scrollBy, pauseMs: 500 });
  }

  await new Promise((resolve) => setTimeout(resolve, pauseMs));

  let html = pageHtml || '';
  try {
    const refreshed = await ui.html({ timeoutMs: 30000 });
    if (refreshed?.html) html = refreshed.html;
  } catch (htmlError) { /* fallback to initial pageHtml */ }

  const contacts = parseContacts(html);
  return {
    ok: true,
    action,
    url: finalUrl || url,
    collectedAt: new Date().toISOString(),
    htmlLength: html.length,
    itemCount: contacts.length,
    firstVisible: contacts[0]?.name || null,
    lastVisible: contacts.length > 0 ? contacts[contacts.length - 1].name : null,
    contacts,
  };
}
