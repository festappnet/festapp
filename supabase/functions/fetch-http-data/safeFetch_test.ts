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
  ]) {
    try {
      parseSafeTarget(value);
      throw new Error(`accepted ${value}`);
    } catch (error) {
      assertEquals(error instanceof UnsafeTargetError, true);
    }
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
