// PostgreSQL accepts $$ and named dollar quotes; their contents remain opaque.
export function extractFunctionBody(sql) {
  const match = sql.match(/\bAS\s+(\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$)([\s\S]*?)\1/i);
  if (!match) throw new Error('SQL source has no complete dollar-quoted function body');
  return match[2].replace(/\s+/g, '');
}
