// Extract authored article text at build time. No third-party DOM or search service.
export const plainText = html => html.replace(/<!--[\s\S]*?-->/g, ' ')
  .replace(/<(script|style|noscript|figure|form)\b[^>]*>[\s\S]*?<\/\1>/gi, ' ')
  .replace(/<[^>]*>/g, ' ').replace(/&#(x[\da-f]+|\d+);/gi, (_, n) => String.fromCodePoint(n[0].toLowerCase() === 'x' ? parseInt(n.slice(1), 16) : Number(n)))
  .replace(/&(amp|lt|gt|quot|apos|nbsp|#39);/g, (_, n) => ({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'",nbsp:' ','#39':"'"}[n]))
  .replace(/\s+/g, ' ').trim();
export function articleSections(html) {
  const headings = [...html.matchAll(/<h2 id="([^"]+)">([\s\S]*?)<\/h2>/g)];
  return [{anchor:'',heading:'',text:plainText(html.slice(0,headings[0]?.index ?? html.length))},
    ...headings.map((h,i) => ({anchor:h[1],heading:plainText(h[2]),text:plainText(html.slice(h.index+h[0].length,headings[i+1]?.index ?? html.length))}))];
}
