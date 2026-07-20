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

// 用 DOM querySelector(All) + class 选择器提取（不依赖引号风格、不对 innerHTML 做正则）。
// 选择器沿用 references/boss_selectors.md 第四节：会话条目 .chat-item / .friend-content，
// 含 (name, company, role)。无真实 DOM 或取不到时返回 []，**绝不编造**。
function parseContacts() {
  const items = [];
  // 提取在页面上下文执行时 document 可用；否则无 DOM，安全返回空。
  if (typeof document === 'undefined' || !document) return items;
  const nodes = document.querySelectorAll('.friend-content, .chat-item');
  if (!nodes || nodes.length === 0) return items;
  nodes.forEach((node) => {
    const nameEl = node.querySelector('.name-text, .name');
    const name = nameEl ? cleanText(nameEl.textContent) : '';
    if (!name) return; // 跳过无名条目，不编造
    // company / role：取 item 内其余文本 span（排除 name / 时间 / 最后消息），按出现顺序
    const spans = Array.from(node.querySelectorAll('span'))
      .map((s) => cleanText(s.textContent))
      .filter((t) => t && t !== name);
    // 在 spans 中定位 name 之后的公司 / 角色（若有）
    const nameIdx = spans.indexOf(name);
    let company = '', role = '';
    if (nameIdx >= 0) {
      company = spans[nameIdx + 1] || '';
      role = spans[nameIdx + 2] || '';
    } else if (spans.length) {
      company = spans[0] || '';
      role = spans[1] || '';
    }
    items.push({ name, company, role });
  });
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

  const contacts = parseContacts();
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
