#!/usr/bin/env -S deno run
import { preparedSandboxCase, reserveSandboxCase } from "./sandbox_intent.mjs";
/** Operator-only real sandbox probe. Keys stay in login Keychain/in memory.
 * A durable pre-dispatch intent prevents replay of an uncertain Start.
 */
import { createServer } from "node:http";
import { execFile, execFileSync, spawn } from "node:child_process";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { createInterface } from "node:readline";
import { BarionSandboxProvider } from "../../supabase/functions/_shared/barion/provider.ts";

const keychain = join(homedir(), "Library/Keychains/login.keychain-db");
const readSecret = (service) =>
  execFileSync("security", [
    "find-generic-password",
    "-s",
    service,
    "-a",
    "festapp-sandbox",
    "-w",
    keychain,
  ], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
if (!process.argv.includes("--dispatch-sandbox")) {
  throw new Error("explicit_sandbox_dispatch_required");
}
const shopId = process.env.FESTAPP_BARION_SANDBOX_SHOP_ID;
if (!/^[0-9a-f]{32}$/i.test(shopId ?? "")) {
  throw new Error("explicit_sandbox_shop_required");
}
const activePath = "/tmp/festapp-barion-sandbox-active.json";
const root = join(homedir(), ".local/share/festapp/barion-sandbox");
mkdirSync(root, { recursive: true, mode: 0o700 });
const windowSeconds=Number(process.argv.find(arg=>arg.startsWith("--window-seconds="))?.slice(17) ?? 1860);
if(!Number.isSafeInteger(windowSeconds) || windowSeconds<60 || windowSeconds>1860) throw Error("invalid_sandbox_window");
const caseId = process.argv.find((arg) => arg.startsWith("--case="))?.slice(7);
const independentOf = process.argv.find((arg) =>
  arg.startsWith("--independent-of=")
)?.slice(17);
const resumeId = process.argv.find((arg) =>
  arg.startsWith("--resume-prepared=")
)?.slice(18);
const previousPreparation = resumeId
  ? preparedSandboxCase({ root, attemptId: resumeId, caseId })
  : null;
const id = previousPreparation?.receipt.attemptId ?? randomUUID();
const directory = join(root, id);
mkdirSync(directory, { recursive: true, mode: 0o700 });
const receiptPath = join(directory, "receipt.json");
const caseEntry = previousPreparation
  ? {
    caseId,
    attemptId: id,
    receiptPath,
    independentOf: previousPreparation.receipt.independentOf,
    previousOutcomeRemainsUnresolved:
      previousPreparation.receipt.previousOutcomeRemainsUnresolved,
  }
  : reserveSandboxCase({
    root,
    caseId,
    attemptId: id,
    receiptPath,
    previousActive: activePath,
    independentOf,
  });
const receipt = {
  ...caseEntry,
  probeSourceSha256: createHash("sha256").update(
    readFileSync(new URL(import.meta.url)),
  ).digest("hex"),
  preparationHistory: [
    ...(previousPreparation?.receipt.preparationHistory ?? []),
    ...(previousPreparation
      ? [{
        sourceSha256: previousPreparation.receipt.probeSourceSha256,
        failure: previousPreparation.receipt.lastFailure,
        time: previousPreparation.receipt.createdAt,
      }]
      : []),
  ],
  version: 1,
  environment: "sandbox",
  attemptId: id,
  createdAt: new Date().toISOString(),
  disposition: "prepared",
  amountMinor: 100,
  currency: "CZK",
  keychainService: "festapp-barion-sandbox-poskey",
  observations: [],
  notifications: 0,
};
const persist = () => {
  writeFileSync(receiptPath + ".tmp", JSON.stringify(receipt, null, 2) + "\n", {
    mode: 0o600,
  });
  renameSync(receiptPath + ".tmp", receiptPath);
};
persist();
const callbackPath = "/callback/" + randomBytes(32).toString("hex");
let provider, snapshot, remoteId, tunnel, lastRead = 0, readBusy = false;
const guid =
  /^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i;
const redact = (state) => ({
  PaymentId: state.PaymentId,
  PaymentRequestId: state.PaymentRequestId,
  PaymentType: state.PaymentType,
  Status: state.Status,
  Total: state.Total,
  Currency: state.Currency,
  FundingSource: state.FundingSource,
  CompletedAt: state.CompletedAt,
  Transactions: state.Transactions.map((t) =>
    Object.fromEntries(
      [
        "TransactionId",
        "POSTransactionId",
        "TransactionTime",
        "Total",
        "Currency",
        "Status",
        "TransactionType",
        "RelatedId",
      ].filter((k) => k in t).map((k) => [k, t[k]]),
    )
  ),
});
async function observe(paymentId = remoteId) {
  if (!provider || !paymentId || readBusy) return;
  if (Date.now() - lastRead < 5500) return;
  readBusy = true;
  lastRead = Date.now();
  try {
    const state = await provider.paymentState(snapshot, paymentId);
    if (remoteId && paymentId.toLowerCase() !== remoteId.toLowerCase()) {
      throw new Error("foreign_payment");
    }
    remoteId = paymentId;
    receipt.paymentId = paymentId;
    receipt.observations.push({
      observedAt: new Date().toISOString(),
      state: redact(state),
    });
    persist();
    process.stdout.write(
      JSON.stringify({
        operation: "state",
        status: state.Status,
        transactions: state.Transactions.length,
      }) + "\n",
    );
  } catch (error) {
    receipt.lastFailure = error?.code ?? "barion_probe_state_failed";
    persist();
    process.stdout.write(
      JSON.stringify({ operation: "state", error: receipt.lastFailure }) + "\n",
    );
  } finally {
    readBusy = false;
  }
}
const server = createServer(async (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Referrer-Policy", "no-referrer");
  const url = new URL(req.url, "http://localhost");
  if (req.method === "GET" && url.pathname === "/return") {
    res.setHeader("Content-Type", "text/html;charset=utf-8");
    res.end(
      '<!doctype html><meta name="viewport" content="width=device-width"><title>Festapp - test platby</title><p>Testovací platba byla předána k ověření. Tato stránka sama nepotvrzuje zaplacení.</p>',
    );
    return;
  }
  if (req.method === "POST" && url.pathname === callbackPath) {
    const paymentId = url.searchParams.get("paymentId");
    if (!paymentId || !guid.test(paymentId)) {
      res.statusCode = 400;
      res.end();
      return;
    }
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 4096) {
        res.statusCode = 413;
        res.end();
        return;
      }
    }
    receipt.notifications++;
    persist();
    res.end("OK");
    // A callback is only a hint; current authenticated state is read separately.
    void observe(paymentId);
    return;
  }
  res.statusCode = 404;
  res.end();
});
process.on("SIGINT", () => {
  tunnel?.kill("SIGTERM");
  server.close();
  process.exit(130);
});
try {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  receipt.localPort = port;
  persist();
  tunnel = spawn("cloudflared", [
    "tunnel",
    "--url",
    `http://127.0.0.1:${port}`,
    "--no-autoupdate",
    "--protocol",
    "http2",
  ], { stdio: ["ignore", "ignore", "pipe"] });
  receipt.tunnelPid = tunnel.pid;
  persist();
  const origin = await new Promise((resolve, reject) => {
    let buffer = "";
    const timeout = setTimeout(
      () => reject(new Error("tunnel_unavailable")),
      30000,
    );
    tunnel.stderr.on("data", (chunk) => {
      appendFileSync(join(directory, "cloudflared.log"), chunk, {
        mode: 0o600,
      });
      buffer = (buffer + chunk).slice(-20000);
      const match = buffer.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
      if (match) {
        clearTimeout(timeout);
        resolve(match[0]);
      }
    });
    tunnel.on("error", () => {
      clearTimeout(timeout);
      reject(new Error("tunnel_unavailable"));
    });
  });
  receipt.tunnelOrigin = origin;
  persist();
  // A newly created tunnel can be negatively cached by the workstation resolver.
  // Query public DNS only for this ephemeral hostname and verify TLS with curl;
  // never change browser/system DNS or disable certificate verification.
  const hostname = new URL(origin).hostname;
  let address;
  for (let attempt = 0; attempt < 90 && !address; attempt++) {
    const dns = await (await fetch(
      "https://cloudflare-dns.com/dns-query?name=" +
        encodeURIComponent(hostname) + "&type=A",
      {
        headers: { accept: "application/dns-json" },
        signal: AbortSignal.timeout(10000),
      },
    )).json();
    receipt.dnsStatus = dns.Status;
    persist();
    address = dns.Answer?.find((answer) =>
      answer.type === 1 && /^\d+\.\d+\.\d+\.\d+$/.test(answer.data)
    )?.data;
    if (!address) await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  if (!address) throw new Error("tunnel_dns_unavailable");
  // An asynchronous subprocess is essential: the local HTTP server must remain
  // able to answer the request arriving through this same tunnel.
  const status = await new Promise((resolve, reject) =>
    execFile(
      "curl",
      [
        "--silent",
        "--show-error",
        "--max-time",
        "15",
        "--resolve",
        hostname + ":443:" + address,
        "-o",
        "/dev/null",
        "-w",
        "%{http_code}",
        origin + "/return",
      ],
      { encoding: "utf8" },
      (error, output) =>
        error ? reject(new Error("tunnel_probe_failed")) : resolve(output),
    )
  );
  receipt.lastTunnelStatus = Number(status);
  persist();
  if (status !== "200") throw new Error("tunnel_not_ready");
  receipt.lastTunnelStatus = 200;
  persist();
  const now = Math.floor(Date.now() / 1000);
  snapshot = {
    attemptId: id,
    accountId: shopId,
    livemode: false,
    amountMinor: 100,
    currency: "CZK",
    orderReference: "Festapp - " + caseId,
    createdAt: now,
    expiresAt: now + windowSeconds,
    idempotencyKey: id,
    returnUrl: origin + "/return",
    locale: "cs",
  };
  provider = new BarionSandboxProvider({
    accountId: snapshot.accountId,
    posKey: readSecret("festapp-barion-sandbox-poskey"),
    payee: readSecret("festapp-barion-sandbox-payee"),
    callbackUrl: origin + callbackPath,
    allowedReturnOrigins: [origin],
  });
  writeFileSync(
    activePath,
    JSON.stringify({
      directory,
      receiptPath,
      checkoutPath: join(directory, "checkout.json"),
    }) + "\n",
    { mode: 0o600 },
  );
  receipt.snapshot = snapshot;
  receipt.disposition = "dispatched";
  receipt.dispatchedAt = new Date().toISOString();
  persist();
  try {
    const checkout = await provider.createPayment(snapshot);
    remoteId = checkout.id;
    receipt.paymentId = checkout.id;
    receipt.disposition = "remote_created";
    receipt.initialStatus = checkout.status;
    persist();
    writeFileSync(
      join(directory, "checkout.json"),
      JSON.stringify({ url: checkout.url }) + "\n",
      { mode: 0o600 },
    );
    writeFileSync(
      activePath,
      JSON.stringify({
        directory,
        receiptPath,
        checkoutPath: join(directory, "checkout.json"),
      }) + "\n",
      { mode: 0o600 },
    );
    process.stdout.write(
      JSON.stringify({
        operation: "created",
        status: checkout.status,
        activeMetadata: activePath,
      }) + "\n",
    );
    await observe();
  } catch (error) {
    receipt.disposition = "uncertain";
    receipt.lastFailure = error?.code ?? "barion_probe_start_failed";
    receipt.httpStatus = error?.httpStatus ?? null;
    receipt.providerCode = error?.providerCode ?? null;
    persist();
    process.stdout.write(
      JSON.stringify({
        operation: "create",
        error: receipt.lastFailure,
        receiptPath,
      }) + "\n",
    );
    tunnel.kill("SIGTERM");
    server.close();
    process.exitCode = 1;
  }
  if (remoteId) {
    const lines = createInterface({ input: process.stdin });
    lines.on("line", async (line) => {
      if (line === "status") await observe();
      else if (line === "stop") {
        lines.close();
        tunnel.kill("SIGTERM");
        server.close();
      }
    });
    const cleanup = () => {
      tunnel.kill("SIGTERM");
      server.close();
      lines.close();
    };
    process.on("SIGINT", cleanup);
    process.on("SIGTERM", cleanup);
  }
} catch (error) {
  receipt.lastFailure = error?.code ??
    ([
        "tunnel_unavailable",
        "tunnel_dns_unavailable",
        "tunnel_not_ready",
        "tunnel_probe_failed",
      ].includes(error?.message)
      ? error.message
      : "probe_setup_failed");
  persist();
  process.stdout.write(
    JSON.stringify({
      operation: "setup",
      error: receipt.lastFailure,
      receiptPath,
    }) + "\n",
  );
  tunnel?.kill("SIGTERM");
  server.close();
  process.exitCode = 1;
}
