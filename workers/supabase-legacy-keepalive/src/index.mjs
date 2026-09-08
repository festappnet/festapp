export const TARGETS = [
  { alias: "default", projectRef: "kjdpmixlnhntmxjedpxh" },
  { alias: "a", projectRef: "lwfpdjxsdmkfyrzqbrlk" },
  { alias: "slunovrat", projectRef: "hvtsoseaywurkmhywdbd" },
];

function readAnonKeys(encoded) {
  if (!encoded) throw new Error("SUPABASE_LEGACY_ANON_KEYS is not configured");
  const keys = JSON.parse(encoded);
  for (const { projectRef } of TARGETS) {
    if (typeof keys[projectRef] !== "string" || keys[projectRef].length === 0) {
      throw new Error(`missing anon key for ${projectRef}`);
    }
  }
  return keys;
}

async function ping(fetchImpl, target, anonKey) {
  const started = Date.now();
  const url = `https://${target.projectRef}.supabase.co/rest/v1/occasions?select=id&limit=1`;
  try {
    const response = await fetchImpl(url, {
      method: "GET",
      redirect: "manual",
      signal: AbortSignal.timeout(10_000),
      headers: {
        apikey: anonKey,
        authorization: `Bearer ${anonKey}`,
        "user-agent": "festapp-supabase-legacy-keepalive/1",
      },
    });
    return {
      alias: target.alias,
      project_ref: target.projectRef,
      status: response.status,
      duration_ms: Date.now() - started,
      pass: response.ok,
    };
  } catch (error) {
    return {
      alias: target.alias,
      project_ref: target.projectRef,
      status: null,
      duration_ms: Date.now() - started,
      pass: false,
      error_class: error instanceof Error ? error.name : "UnknownError",
    };
  }
}

export async function runKeepalive(env, fetchImpl = fetch) {
  const keys = readAnonKeys(env.SUPABASE_LEGACY_ANON_KEYS);
  const results = await Promise.all(TARGETS.map((target) =>
    ping(fetchImpl, target, keys[target.projectRef])));
  const failed = results.filter((result) => !result.pass);
  const event = {
    event: failed.length === 0
      ? "festapp_supabase_legacy_keepalive_passed"
      : "festapp_supabase_legacy_keepalive_failed",
    observed_at: new Date().toISOString(),
    results,
  };
  if (failed.length > 0) {
    console.error(JSON.stringify(event));
    throw new Error(`legacy Supabase keepalive failed for: ${failed.map(({ alias }) => alias).join(", ")}`);
  }
  console.log(JSON.stringify(event));
  return results;
}

export default {
  async fetch() {
    return new Response("Not Found", { status: 404 });
  },
  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(runKeepalive(env));
  },
};
