import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { exchangeLoginCredential } from "./exchange.ts";

Deno.test("manual code ignores case, spaces, and separators before exchange", async () => {
  let resolvedHash: string | undefined;
  const admin = {
    rpc(name: string, params: Record<string, string>) {
      if (name === "resolve_reception_login_qr_v1") {
        resolvedHash = params.p_token_hash;
        return Promise.resolve({ data: null, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  } as unknown as SupabaseClient;
  const anon = {} as SupabaseClient;

  const result = await exchangeLoginCredential(
    { occasion: 42, manualCode: " k7m4-p9q2 " },
    admin,
    anon,
  );

  assertEquals(result, null);
  const expected = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode("K7M4P9Q2"),
  );
  assertEquals(
    resolvedHash,
    [...new Uint8Array(expected)].map((b) => b.toString(16).padStart(2, "0"))
      .join(""),
  );
});

Deno.test("valid login QR returns only a normal session after marking use", async () => {
  const calls: string[] = [];
  const admin = {
    rpc(name: string) {
      calls.push(name);
      if (name === "resolve_reception_login_qr_v1") {
        return Promise.resolve({
          data: { userId: "user-id", authEmail: "9+guest@test.local" },
          error: null,
        });
      }
      return Promise.resolve({ data: { userId: "user-id", authEmail: "9+guest@test.local" }, error: null });
    },
    auth: {
      admin: {
        generateLink() {
          calls.push("generateLink");
          return Promise.resolve({
            data: { user: { id: "user-id" }, properties: { hashed_token: "otp-proof" } },
            error: null,
          });
        },
      },
    },
  } as unknown as SupabaseClient;
  const anon = {
    auth: {
      verifyOtp() {
        calls.push("verifyOtp");
        return Promise.resolve({
          data: {
            session: {
              user: { id: "user-id" },
              access_token: "access",
              refresh_token: "refresh",
              expires_at: 123,
              token_type: "bearer",
            },
          },
          error: null,
        });
      },
    },
  } as unknown as SupabaseClient;

  const result = await exchangeLoginCredential(
    { payload: `festapp-login:v1:42:${"A".repeat(43)}` },
    admin,
    anon,
  );

  assertEquals(calls, [
    "resolve_reception_login_qr_v1",
    "acquire_existing_user_session_lease_v1",
    "resolve_reception_login_qr_v1",
    "generateLink",
    "verifyOtp",
    "check_existing_user_session_lease_v1",
    "resolve_reception_login_qr_v1",
    "check_existing_user_session_lease_v1",
    "resolve_reception_login_qr_v1",
    "release_existing_user_session_lease_v1",
    "mark_reception_login_qr_used_v1",
  ]);
  assertEquals(result, {
    access_token: "access",
    refresh_token: "refresh",
    expires_at: 123,
    token_type: "bearer",
  });
});
