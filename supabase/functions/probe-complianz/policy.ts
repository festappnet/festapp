export const MAX_HTML_BYTES = 1024 * 1024;

/** WordPress wp_localize_script emits a JSON object, including on multisite.
 * Never evaluate site JavaScript. Ambiguous or non-JSON configs fail closed.
 */
export function extractPolicyId(html: string): string | null {
  if (new TextEncoder().encode(html).length > MAX_HTML_BYTES) return null;
  const ids: string[] = [];
  for (
    const script of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi)
  ) {
    const source = script[1];
    for (
      const match of source.matchAll(
        /\b(?:var|let|const)\s+complianz\s*=\s*(\{)/g,
      )
    ) {
      const start = match.index! + match[0].length - 1;
      let depth = 0, quoted = false, escaped = false;
      for (let i = start; i < source.length; i++) {
        const c = source[i];
        if (quoted) {
          if (escaped) escaped = false;
          else if (c === "\\") escaped = true;
          else if (c === '"') quoted = false;
        } else if (c === '"') quoted = true;
        else if (c === "{") depth++;
        else if (c === "}" && --depth === 0) {
          try {
            const config = JSON.parse(source.slice(start, i + 1));
            const id = config.current_policy_id;
            if (
              !(typeof id === "string" || Number.isSafeInteger(id)) ||
              !/^[1-9][0-9]{0,15}$/.test(String(id))
            ) return null;
            ids.push(String(id));
          } catch {
            return null;
          }
          break;
        }
      }
    }
  }
  return ids.length > 0 && ids.every((id) => id === ids[0]) ? ids[0] : null;
}
