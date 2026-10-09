import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { exchangeSignInCode } from "./exchange.ts";
import { generateSignInCode } from "../_shared/signInCode.ts";
Deno.test("malformed sign-in proofs never reach privileged RPC", async () => {
  const admin = {
    rpc() {
      throw new Error("must not call");
    },
  } as unknown as SupabaseClient;
  for (
    const input of [
      null,
      {},
      { email: "a@b.cz", organization: 1, code: "bad" },
      { email: "a@b.cz", organization: -1, code: "123456" },
    ]
  ) assertEquals(await exchangeSignInCode(input, admin, admin), null);
});
Deno.test("failed and consumed proofs never issue a session", async () => {
  let calls = 0;
  const admin = {
    rpc(name: string, args: Record<string, unknown>) {
      calls++;
      assertEquals(name, "consume_sign_in_code_v1");
      assertEquals(args.p_organization, 1);
      return Promise.resolve({ data: null, error: null });
    },
  } as unknown as SupabaseClient;
  assertEquals(
    await exchangeSignInCode(
      { email: "a@b.cz", organization: 1, code: "123456" },
      admin,
      admin,
    ),
    null,
  );
  assertEquals(calls, 1);
});
Deno.test("cryptographic invitation codes preserve six-digit UI contract", () => {
  for (let i = 0; i < 100; i++) {
    assertEquals(/^\d{6}$/.test(generateSignInCode()), true);
  }
});
Deno.test("valid proof is consumed before a session is minted", async () => {
  const calls: string[] = [];
  const target = { userId: "user-id", authEmail: "9+user@test.invalid" };
  const admin = {
    rpc(name: string) {
      calls.push(name);
      return Promise.resolve({ data: target, error: null });
    },
    auth: {
      admin: {
        generateLink() {
          calls.push("generateLink");
          return Promise.resolve({
            error: null,
            data: {
              user: { id: target.userId },
              properties: { hashed_token: "internal-proof" },
            },
          });
        },
      },
    },
  } as unknown as SupabaseClient;
  const anon = {
    auth: {
      verifyOtp() {
        return Promise.resolve({
          error: null,
          data: {
            session: {
              user: { id: target.userId },
              access_token: "access",
              refresh_token: "refresh",
            },
          },
        });
      },
    },
  } as unknown as SupabaseClient;
  assertEquals(
    await exchangeSignInCode(
      { email: "user@test.invalid", organization: 9, code: "123456" },
      admin,
      anon,
    ),
    { refresh_token: "refresh" },
  );
  assertEquals(calls[0], "consume_sign_in_code_v1");
  assertEquals(calls.indexOf("generateLink") > 0, true);
});
