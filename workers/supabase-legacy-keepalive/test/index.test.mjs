import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import worker, { runKeepalive, TARGETS } from "../src/index.mjs";

const refs = ["kjdpmixlnhntmxjedpxh", "lwfpdjxsdmkfyrzqbrlk", "hvtsoseaywurkmhywdbd"];

test("targets exactly mirror the canonical migration source registry", () => {
  const registry = JSON.parse(fs.readFileSync(path.resolve(
    import.meta.dirname,
    "../../../automation/hetzner-supabase/merge/source-registry.json",
  ), "utf8"));
  assert.deepEqual(
    TARGETS,
    registry.sources.map(({ alias, project_ref }) => ({ alias, projectRef: project_ref })),
  );
});

function environment() {
  return { SUPABASE_LEGACY_ANON_KEYS: JSON.stringify(Object.fromEntries(refs.map((ref) => [ref, `key-${ref}`]))) };
}

test("performs one authenticated database query for every legacy project", async () => {
  const requests = [];
  const results = await runKeepalive(environment(), async (url, options) => {
    requests.push({ url, options });
    return new Response("[]", { status: 200 });
  });
  assert.equal(results.length, 3);
  assert.equal(requests.length, 3);
  for (const [index, request] of requests.entries()) {
    assert.match(request.url, new RegExp(`^https://${refs[index]}\\.supabase\\.co/rest/v1/occasions`));
    assert.equal(request.options.method, "GET");
    assert.equal(request.options.headers.apikey, `key-${refs[index]}`);
    assert.equal(request.options.headers.authorization, `Bearer key-${refs[index]}`);
  }
});

test("fails when a project does not accept the query", async () => {
  await assert.rejects(
    runKeepalive(environment(), async (url) => new Response("", {
      status: url.includes(refs[1]) ? 503 : 200,
    })),
    /failed for: a/,
  );
});

test("requires a key for every configured project", async () => {
  await assert.rejects(
    runKeepalive({ SUPABASE_LEGACY_ANON_KEYS: "{}" }, async () => new Response("[]")),
    /missing anon key/,
  );
});

test("does not expose a production HTTP trigger", async () => {
  const response = await worker.fetch();
  assert.equal(response.status, 404);
});
