import { escapeEmailHtml } from "./emailActionLink.ts";
import {
  emailVariableContract,
  emailVariablePattern,
} from "./emailVariables.ts";

const variables: Record<string, { html: boolean }> =
  emailVariableContract.variables;
const tokenAtStart = new RegExp(`^${emailVariableContract.tokenPattern}`);

export function substituteEmailSubject(
  subject: string,
  substitutions: Record<string, unknown>,
) {
  const values = substitutions;
  return subject.replace(
    emailVariablePattern,
    (token, code) =>
      Object.hasOwn(values, code) && variables[code]?.html !== true
        ? String(values[code] ?? "")
        : token,
  );
}

/** Scan authored HTML once. Inserted customer text is never parsed as a template. */
export function substituteEmailHtml(
  html: string,
  substitutions: Record<string, unknown>,
) {
  const values = substitutions;
  let out = "", offset = 0, inTag = false, quote = "", rawElement = "";
  while (offset < html.length) {
    if (!inTag && html.startsWith("<!--", offset)) {
      const end = html.indexOf("-->", offset + 4);
      const until = end < 0 ? html.length : end + 3;
      out += html.slice(offset, until);
      offset = until;
      continue;
    }
    if (!inTag && rawElement) {
      const closing = new RegExp(`^<\\s*/\\s*${rawElement}\\b`, "i");
      if (closing.test(html.slice(offset))) rawElement = "";
      else {
        out += html[offset++];
        continue;
      }
    }
    if (!inTag && html[offset] === "<") {
      const raw = /^<\s*(script|style)\b/i.exec(html.slice(offset));
      if (raw) rawElement = raw[1].toLowerCase();
      inTag = true;
    }
    if (!rawElement && html.startsWith("{{", offset)) {
      const match = tokenAtStart.exec(html.slice(offset));
      if (match) {
        const code = match[1], definition = variables[code];
        if (
          Object.hasOwn(values, code) &&
          (!inTag || (quote && definition?.html !== true))
        ) {
          const value = String(values[code] ?? "");
          // Uncatalogued internal producer values retain their existing wire contract.
          out += definition?.html === false ? escapeEmailHtml(value) : value;
        } else out += match[0];
        offset += match[0].length;
        continue;
      }
    }
    const char = html[offset++];
    out += char;
    if (inTag) {
      if (quote) { if (char === quote) quote = ""; }
      else if (char === '"' || char === "'") quote = char;
      else if (char === ">") inTag = false;
    }
  }
  return out;
}
