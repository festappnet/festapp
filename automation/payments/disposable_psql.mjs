/** Transaction-scoped local operator/test RPC bridge. Never accepts a remote DB. */
export async function disposableSql(databaseUrl) {
  const url = new URL(databaseUrl);
  if (!["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) {
    throw Error("local_disposable_database_required");
  }
  const child = new Deno.Command("psql", {
    args: [databaseUrl, "-X", "-qAt", "-v", "ON_ERROR_STOP=1"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter(),
    reader = child.stdout.getReader(),
    decoder = new TextDecoder();
  let buffer = "";
  const errors = (async () => {
    const chunks = [];
    for await (const c of child.stderr) chunks.push(c);
    return chunks.map((c) => new TextDecoder().decode(c)).join("");
  })();
  async function query(sql) {
    const marker = "__end_" + crypto.randomUUID().replaceAll("-", "");
    await writer.write(
      new TextEncoder().encode(sql + "\n\\echo " + marker + "\n"),
    );
    const lines = [];
    for (;;) {
      let newline = buffer.indexOf("\n");
      if (newline < 0) {
        const v = await reader.read();
        if (v.done) throw Error("disposable_sql_failed: " + await errors);
        buffer += decoder.decode(v.value, { stream: true });
        continue;
      }
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      if (line === marker) return lines;
      lines.push(line);
    }
  }
  try {
    await query(
      "BEGIN; DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment WHERE project='festapp-payment-provider-hardening') THEN RAISE EXCEPTION 'wrong disposable target'; END IF; END $$;",
    );
  } catch (error) {
    await writer.close().catch(() => {});
    await child.status;
    throw error;
  }
  return {
    query,
    async close() {
      try {
        await query("ROLLBACK;");
      } finally {
        await writer.close();
        reader.releaseLock();
        await child.status;
        await errors;
      }
    },
  };
}
export const sqlJson = (value) =>
  "'" + JSON.stringify(value).replaceAll("'", "''") + "'::jsonb";
