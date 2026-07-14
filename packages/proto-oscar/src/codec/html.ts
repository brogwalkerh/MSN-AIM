/**
 * AIM messages are a small HTML subset ("aolrtf"). Inbound text is
 * sanitized to the tags classic AIM supports; everything else is escaped.
 * Plain text passes through unchanged (it is valid HTML).
 */

const ALLOWED_TAGS = new Set(['b', 'i', 'u', 's', 'sub', 'sup', 'br', 'a', 'font', 'html', 'body']);
const ALLOWED_ATTRS: Record<string, Set<string>> = {
  a: new Set(['href']),
  font: new Set(['color', 'face', 'size'])
};

const TAG_RE = /<\/?([a-zA-Z][a-zA-Z0-9]*)((?:\s+[a-zA-Z-]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*\/?>/g;
const ATTR_RE = /([a-zA-Z-]+)(?:\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+)))?/g;

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function sanitizeUrl(url: string): string {
  const trimmed = url.trim();
  if (/^(https?|mailto):/i.test(trimmed)) return trimmed;
  return '#';
}

/** Sanitize an incoming AIM HTML message for display. */
export function sanitizeAimHtml(input: string): string {
  let out = '';
  let last = 0;
  for (const match of input.matchAll(TAG_RE)) {
    const [whole, rawName, rawAttrs] = match;
    const index = match.index ?? 0;
    out += escapeHtml(input.slice(last, index));
    last = index + whole.length;

    const name = (rawName ?? '').toLowerCase();
    if (!ALLOWED_TAGS.has(name) || name === 'html' || name === 'body') {
      // <html>/<body> wrappers from classic clients are dropped silently;
      // unknown tags are removed (their inner text still shows).
      continue;
    }
    const closing = whole.startsWith('</');
    if (closing) {
      out += `</${name}>`;
      continue;
    }
    let attrs = '';
    const allowed = ALLOWED_ATTRS[name];
    if (allowed && rawAttrs) {
      for (const am of rawAttrs.matchAll(ATTR_RE)) {
        const attrName = (am[1] ?? '').toLowerCase();
        if (!allowed.has(attrName)) continue;
        const value = am[3] ?? am[4] ?? am[5] ?? '';
        const safe = attrName === 'href' ? sanitizeUrl(value) : value.replace(/["<>]/g, '');
        attrs += ` ${attrName}="${safe}"`;
      }
    }
    out += name === 'br' ? '<br/>' : `<${name}${attrs}>`;
  }
  out += escapeHtml(input.slice(last));
  return out;
}

/** Strip all tags — for notifications/log lines. */
export function htmlToPlainText(input: string): string {
  return input
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&');
}
