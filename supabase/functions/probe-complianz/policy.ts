import { Parser } from "npm:htmlparser2@12.0.0";
import { parse } from "npm:acorn@8.15.0";

export const MAX_HTML_BYTES = 1024 * 1024;

/** Read only active, inline, top-level WordPress localized JSON declarations.
 * HTML and JavaScript parsers own syntax; no website code is ever evaluated.
 * Unsupported scripts and malformed or conflicting candidates fail closed.
 */
export function extractPolicyId(html: string): string | null {
  if (new TextEncoder().encode(html).length > MAX_HTML_BYTES) return null;
  let policyId: string | null = null;
  let invalid = false;
  let inertDepth = 0;
  let script: string | null = null;
  const parser = new Parser({
    onopentag(name, attributes) {
      if (name === "template" || name === "noscript") inertDepth++;
      if (name !== "script") return;
      const type = (attributes.type ?? "").trim().toLowerCase();
      script = inertDepth === 0 && !("src" in attributes) &&
          ["", "text/javascript", "application/javascript"].includes(type)
        ? ""
        : null;
    },
    ontext(text) {
      if (script !== null) script += text;
    },
    onclosetag(name) {
      if (name === "template" || name === "noscript") inertDepth--;
      if (name !== "script" || script === null) return;
      const source = script;
      script = null;
      // Most page scripts are unrelated. Parsing the candidate once also bounds
      // work for repeated unfinished declarations to the HTML byte ceiling.
      if (!/\bcomplianz\b/.test(source)) return;
      try {
        const program = parse(source, { ecmaVersion: "latest" });
        const declarations = program.body.flatMap((statement) =>
          statement.type === "VariableDeclaration" ? statement.declarations : []
        ).filter((declaration) =>
          declaration.id.type === "Identifier" &&
          declaration.id.name === "complianz"
        );
        if (declarations.length === 0) return;
        // A localized data script cannot also execute mutations or conditionals.
        if (
          program.body.some((statement) =>
            !["VariableDeclaration", "EmptyStatement"].includes(statement.type)
          )
        ) {
          invalid = true;
          return;
        }
        for (const declaration of declarations) {
          const init = declaration.init;
          if (!init || init.type !== "ObjectExpression") {
            invalid = true;
            return;
          }
          const config = JSON.parse(source.slice(init.start, init.end));
          const id = config.current_policy_id;
          if (
            !(typeof id === "string" || Number.isSafeInteger(id)) ||
            !/^[1-9][0-9]{0,15}$/.test(String(id)) ||
            (policyId !== null && policyId !== String(id))
          ) {
            invalid = true;
            return;
          }
          policyId = String(id);
        }
      } catch {
        invalid = true;
      }
    },
  }, { decodeEntities: false });
  parser.end(html);
  return invalid ? null : policyId;
}
