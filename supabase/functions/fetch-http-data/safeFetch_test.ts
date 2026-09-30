import { assertEquals, assertRejects } from "jsr:@std/assert";
import { fetchPublicImage, parseSafeTarget, UnsafeTargetError } from "./safeFetch.ts";

Deno.test("target policy rejects local, private, credentialed and non-HTTPS URLs", () => {
  for (const value of [
    "http://example.com/a.png",
    "https://localhost/a.png",
    "https://127.0.0.1/a.png",
    "https://10.0.0.1/a.png",
    "https://[::1]/a.png",
    "https://user:pass@example.com/a.png",
    "https://image-api.festapp.net/private/image",
    "https://IMAGE-API.festapp.net./private/image",
  ]) {
    try {
      parseSafeTarget(value);
      throw new Error(`accepted ${value}`);
    } catch (error) {
      assertEquals(error instanceof UnsafeTargetError, true);
    }
  }
});

Deno.test("redirect limit is three and every external request has a timeout signal", async () => {
  let calls = 0;
  await assertRejects(() => fetchPublicImage("https://images.example/start", {
    resolveDns: () => Promise.resolve(["203.0.113.1"]),
    fetch: (_url, init) => {
      calls += 1;
      assertEquals(init.redirect, "manual");
      assertEquals(init.signal instanceof AbortSignal, true);
      return Promise.resolve(new Response(null, {
        status: 302, headers: { location: `/redirect-${calls}` },
      }));
    },
  }), UnsafeTargetError);
  assertEquals(calls, 4);
});

Deno.test("declared and streamed image sizes over 10 MiB are rejected", async () => {
  const max = 10 * 1024 * 1024;
  for (const response of [
    new Response(null, { headers: { "content-type": "image/png", "content-length": `${max + 1}` } }),
    new Response(new ReadableStream({
      start(controller) {
        controller.enqueue(new Uint8Array(max));
        controller.enqueue(new Uint8Array(1));
        controller.close();
      },
    }), { headers: { "content-type": "image/png" } }),
  ]) {
    await assertRejects(() => fetchPublicImage("https://images.example/large.png", {
      resolveDns: () => Promise.resolve(["203.0.113.1"]),
      fetch: () => Promise.resolve(response),
    }), UnsafeTargetError);
  }
});

Deno.test("redirect targets are revalidated before the next fetch", async () => {
  let calls = 0;
  await assertRejects(
    () => fetchPublicImage("https://images.example/start", {
      resolveDns: () => Promise.resolve(["203.0.113.1"]),
      fetch: () => {
        calls += 1;
        return Promise.resolve(new Response(null, {
          status: 302,
          headers: { location: "https://127.0.0.1/secret" },
        }));
      },
    }),
    UnsafeTargetError,
  );
  assertEquals(calls, 1);
});

Deno.test("public image response is bounded and returned with its media type", async () => {
  const result = await fetchPublicImage("https://images.example/photo.png", {
    resolveDns: () => Promise.resolve(["203.0.113.1"]),
    fetch: () => Promise.resolve(new Response(new Uint8Array([1, 2, 3]), {
      headers: { "content-type": "image/png" },
    })),
  });
  assertEquals([...result.bytes], [1, 2, 3]);
  assertEquals(result.contentType, "image/png");
});
