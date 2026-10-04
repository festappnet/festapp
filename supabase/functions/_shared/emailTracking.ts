/** Fail closed for bearer links. Only explicitly allowlisted public pages can be rewritten by SES. */
export function safeClickTracking(html: string, origins: string[]): boolean {
  const links = Array.from(
    html.matchAll(/\bhref\s*=\s*["']([^"']*)["']/gi),
    (m) => m[1],
  );
  if (!links.length || /\bhref\s*=\s*[^\s"']/i.test(html)) return false;
  return links.every((value) => {
    try {
      const link = new URL(value.replace(/&amp;/g, "&"));
      return link.protocol === "https:" && origins.includes(link.origin) &&
        !link.username && !link.password && !link.search && !link.hash &&
        ["/", "/privacy", "/terms"].includes(link.pathname);
    } catch {
      return false;
    }
  });
}
