// Clients can turn plain contact/payment text into links after delivery. Scope
// their link appearance to these spans, preserving the exact text
// (including copied bank details) and every explicitly authored link.
const marker = "data-festapp-plain-value-styles";
const css = "<style " + marker +
  ">\n.festapp-plain-value a {color:inherit!important;text-decoration:none!important;font:inherit!important;}\n</style>";
const tag =
  /<!--[\s\S]*?-->|<![^>]*>|<\/?[A-Za-z](?:[^<>"']|"[^"]*"|'[^']*')*>/g;
const detectableText =
  /https?:\/\/[^\s<>]+|www\.[^\s<>]+|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|\+?\d[\d .()+-]{5,}\d(?:\/\d{4})?/gi;

export function styleEmailPlainValues(html: string): string {
  if (html.includes(marker)) return html;
  let end = 0;
  let changed = false;
  const blocked: string[] = [];
  const fragments: string[] = [];
  const protect = (text: string) =>
    blocked.length ? text : text.replace(detectableText, (value) => {
      changed = true;
      return `<span class="festapp-plain-value">${value}</span>`;
    });
  for (const match of html.matchAll(tag)) {
    const offset = match.index!;
    fragments.push(protect(html.slice(end, offset)), match[0]);
    const name = /^<\/?([a-z][\w:-]*)/i.exec(match[0])?.[1].toLowerCase();
    if (
      name &&
      ["a", "head", "style", "script", "textarea", "title"].includes(name)
    ) {
      if (/^<\//.test(match[0])) {
        const index = blocked.lastIndexOf(name);
        if (index >= 0) blocked.splice(index);
      } else if (!/\/>$/.test(match[0])) {
        blocked.push(name);
      }
    }
    end = offset + match[0].length;
  }
  fragments.push(protect(html.slice(end)));
  if (!changed) return html;
  const result = fragments.join("");
  return /<\/head\s*>/i.test(result)
    ? result.replace(/<\/head\s*>/i, css + "$&")
    : css + result;
}
