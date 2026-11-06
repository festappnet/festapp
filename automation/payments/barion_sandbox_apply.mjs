/** Real authenticated sandbox read -> registered adapter -> common engine ->
 * disposable SQL owner. Everything local is rolled back; no outbound mail.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { BarionSandboxProvider } from "../../supabase/functions/_shared/barion/provider.ts";
import { barionPaymentAdapter } from "../../supabase/functions/_shared/barion/adapter.ts";
import { recoverPaymentClaim } from "../../supabase/functions/_shared/payments/checkout.ts";
import { disposableSql, sqlJson } from "./disposable_psql.mjs";
const attempt = process.argv.find((a) => a.startsWith("--attempt="))?.slice(10);
if (!/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(attempt ?? "")) {
  throw Error("explicit_known_sandbox_attempt_required");
}
const meta = JSON.parse(
  readFileSync("/tmp/festapp-barion-sandbox-active.json", "utf8"),
);
const root = dirname(dirname(meta.receiptPath)),
  path = join(root, attempt, "receipt.json");
const receipt = JSON.parse(readFileSync(path, "utf8"));
const saved = receipt.snapshot;
if (
  receipt.disposition !== "remote_created" || saved?.livemode !== false ||
  !/^[a-f0-9]{32}$/.test(saved.accountId ?? "") ||
  !/^[a-f0-9]{32}$/.test(receipt.paymentId ?? "") ||
  !["CZK", "EUR", "USD"].includes(saved.currency) ||
  !Number.isSafeInteger(saved.amountMinor) || saved.amountMinor < 1 ||
  saved.amountMinor > 1000000000 ||
  !Number.isSafeInteger(saved.createdAt) ||
  !Number.isSafeInteger(saved.expiresAt) || saved.createdAt < 0 ||
  saved.expiresAt <= saved.createdAt
) {
  throw Error("known_sandbox_receipt_required");
}
const db = await disposableSql(Deno.env.get("BARION_DATABASE_URL") ?? "");
const secret = (service) =>
  execFileSync("security", [
    "find-generic-password",
    "-s",
    service,
    "-a",
    "festapp-sandbox",
    "-w",
  ], { stdio: ["ignore", "pipe", "pipe"] }).toString().trim();
try {
  await db.query(readFileSync("database/tests/scanning/fixture.sql", "utf8"));
  const fixture = JSON.parse(
    (await db.query("SELECT public.scanner_test_fixture(1);")).at(-1),
  );
  const snapshot = receipt.snapshot,
    stamp = new Date(snapshot.createdAt * 1000).toISOString(),
    expires = new Date(snapshot.expiresAt * 1000).toISOString();
  const ids = JSON.parse(
    (await db.query(
      `SET LOCAL request.jwt.claim.role='service_role'; SET LOCAL festapp.email_wake='scheduled';
 SELECT json_build_object('orderId',x."order",'org',oc.organization,'unit',oc.unit) FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order" JOIN public.occasions oc ON oc.id=o.occasion WHERE x.ticket=${
        Number(fixture.tickets[0])
      };`,
    )).at(-1),
  );
  const connection = crypto.randomUUID();
  await db.query(
    `INSERT INTO eshop.barion_connections(id,organization_id,unit_id,account_id,business_name) VALUES('${connection}',${
      Number(ids.org)
    },${Number(ids.unit)},'${snapshot.accountId}','Sandbox operator fixture');
 WITH pi AS (INSERT INTO eshop.payment_info(amount,currency_code,payment_method,barion_connection_id) VALUES(${
      snapshot.amountMinor / 100
    },'${snapshot.currency}','barion','${connection}') RETURNING id)
 UPDATE eshop.orders SET payment_info=(SELECT id FROM pi),price=${
      snapshot.amountMinor / 100
    },currency_code='${snapshot.currency}',state='ordered' WHERE id=${
      Number(ids.orderId)
    };
 UPDATE eshop.tickets SET state='ordered' WHERE id=${
      Number(fixture.tickets[0])
    };
 INSERT INTO eshop.barion_attempts(id,order_id,payment_info_id,organization_id,unit_id,connection_id,amount_minor,currency,created_at,reservation_expires_at,return_base_url,remote_id)
 SELECT '${attempt}',id,payment_info,${Number(ids.org)},${
      Number(ids.unit)
    },'${connection}',${snapshot.amountMinor},'${snapshot.currency}','${stamp}','${expires}','https://tickets.example.test/payments/barion/return','${receipt.paymentId}' FROM eshop.orders WHERE id=${
      Number(ids.orderId)
    };`,
  );
  const provider = new BarionSandboxProvider({
    accountId: snapshot.accountId,
    posKey: secret("festapp-barion-sandbox-poskey"),
    payee: secret("festapp-barion-sandbox-payee"),
    callbackUrl: "https://example.invalid/unused",
    allowedReturnOrigins: [],
  });
  const binding = barionPaymentAdapter({
    provider,
    allowedOrigins: [],
    verifyPlatform: async () => {},
    openSource: async () => {
      throw Error("creation_forbidden");
    },
    prepareSource: async () => {
      throw Error("creation_forbidden");
    },
    rpc: async (operation, args) =>
      JSON.parse(
        (await db.query(
          `SELECT public.barion_runtime_internal('${operation}',${
            sqlJson(args)
          });`,
        )).at(-1),
      ),
  });
  const claim = await binding.store.claimSync({
    attemptId: attempt,
    accountId: snapshot.accountId,
  });
  const result = await recoverPaymentClaim(claim, binding);
  const evidence = {
    attemptId: attempt,
    paymentId: receipt.paymentId,
    observedAt: new Date().toISOString(),
    payment: result,
    disposableOutcome: JSON.parse(
      (await db.query(
        `SELECT json_build_object('orderState',o.state,'paid',pi.paid,'returned',pi.returned,'ticketState',t.state) FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info JOIN eshop.tickets t ON t.id=${
          Number(fixture.tickets[0])
        } WHERE o.id=${Number(ids.orderId)};`,
      )).at(-1),
    ),
    rolledBack: true,
  };
  writeFileSync(
    join(dirname(path), "application-proof.json"),
    JSON.stringify(evidence, null, 2) + "\n",
    { mode: 0o600 },
  );
  console.log(
    JSON.stringify({
      operation: "sandbox_common_engine",
      status: result.status,
      ...evidence.disposableOutcome,
    }),
  );
} finally {
  await db.close();
}
