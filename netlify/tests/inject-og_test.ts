import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";
import injectOg from "./inject-og.js";

// Mock Context
const mockContext = {
  next: async (req: Request) => {
    return new Response("<html><head><title>Original Title</title></head><body>Original Content</body></html>", {
      headers: { "content-type": "text/html" }
    });
  },
  log: () => {},
  requestId: "test-req-id",
};

// Test 1: Fail Open on RPC Failure
Deno.test("Fail Open: Returns original page when RPC throw error", async () => {
  // Mock global fetch to throw
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () => Promise.reject(new Error("Network Failure"));

  // Mock Env (if needed, but script checks logic)
  Deno.env.set("SUPABASE_URL", "https://example.com");
  Deno.env.set("SUPABASE_ANON_KEY", "key");

  const req = new Request("https://example.com/form/posezeni2026");
  
  try {
      const res = await injectOg(req, mockContext);
      const text = await res.text();
      
      assertEquals(res.status, 200, "Should return 200 OK even on backend failure");
      assertStringIncludes(text, "Original Title", "Should return original content");
  } finally {
      globalThis.fetch = originalFetch; // Restore
  }
});

// Test 2: Fail Open on Missing Supabase Config
Deno.test("Fail Open: Returns original page when Config missing", async () => {
    Deno.env.delete("SUPABASE_URL");
    
    const req = new Request("https://example.com/form/posezeni2026");
    const res = await injectOg(req, mockContext);
    const text = await res.text();
    
    assertEquals(res.status, 200);
    assertStringIncludes(text, "Original Title");
});

// Test 3: Happy Path (Mocked RPC)
Deno.test("Happy Path: Injects Logic", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => new Response(JSON.stringify({
        title: "New Event Title",
        description: "New Desc",
        image: "image.jpg"
    }));

     Deno.env.set("SUPABASE_URL", "https://example.com");
     Deno.env.set("SUPABASE_ANON_KEY", "key");

     const req = new Request("https://example.com/form/posezeni2026");
     const res = await injectOg(req, mockContext);
     const text = await res.text();

     assertStringIncludes(text, "<title>New Event Title - Festapp</title>"); // Checks implementation details logic
     
     globalThis.fetch = originalFetch;
});
