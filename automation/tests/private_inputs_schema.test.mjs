import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const schema = JSON.parse(readFileSync(
  new URL("../private-inputs.schema.json", import.meta.url),
  "utf8",
));

const consumedPrivateInputs = [
  "SUPABASE_ACCESS_TOKEN",
  "SUPABASE_DB_PASSWORD",
  "SUPABASE_SERVICE_ROLE_KEY",
  "DATABASE_URL",
  "CLOUDFLARE_API_TOKEN",
  "CLOUDFLARE_ACCOUNT_ID",
  "CF_ACCOUNT_ID",
  "R2_ACCESS_KEY_ID",
  "R2_SECRET_ACCESS_KEY",
  "R2_BUCKET_NAME",
  "GOOGLE_PLAY_JSON_KEY",
  "FESTAPP_RELEASE_MANIFEST",
  "APP_STORE_CONNECT_KEY_ID",
  "APP_STORE_CONNECT_ISSUER_ID",
  "APP_STORE_CONNECT_KEY_PATH",
  "FESTAPP_IOS_SIGNING_DIR",
  "APP_REVIEW_DEMO_PASSWORD",
  "MATCH_PASSWORD",
  "CLIENT_SYNC_PUBLISHER_WAKE_TOKEN",
  "CLIENT_SYNC_PUBLISHER_WAKE_URL",
  "FESTAPP_TEST_ACCESS_TOKEN",
  "AWS_SNS_TOPIC_ARN",
  "NOTIFY_WEBHOOK_TOKEN",
  "FESTAPP_PRODUCTION_RUNTIME_CONFIG",
  "FESTAPP_OPERATIONAL_READINESS_EVIDENCE",
  "FESTAPP_OPERATIONAL_READINESS_DECISION",
  "FESTAPP_FINAL_MARKER_DECISION",
  "FESTAPP_PROMOTION_BACKUP_MANIFEST",
  "FESTAPP_PROMOTION_RESTORE_RESULT",
  "FESTAPP_PRODUCTION_PROMOTION_RESULT",
  "FESTAPP_FUNCTION_BUNDLE_MANIFEST",
  "FESTAPP_BACKUP_RECIPIENT_FILE",
  "FESTAPP_BACKUP_IDENTITY_FILE",
  "SMTP_USER_PASSWORD",
  "QR_RATE_SALT",
];

test("public private-input schema uses the exact consumer names", () => {
  assert.deepEqual(Object.keys(schema.properties).sort(), consumedPrivateInputs.sort());
  for (const names of Object.values(schema["x-operationRequirements"])) {
    for (const name of names) assert.ok(schema.properties[name], `unknown input ${name}`);
  }
});

test("superseded aliases cannot hide missing release inputs", () => {
  assert.equal(schema.properties.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON, undefined);
  assert.equal(schema.properties.APP_STORE_CONNECT_API_KEY_PATH, undefined);
});

test("required environment names are derived from their consumers", () => {
  const consumerFiles = [
    "../release/configure_client_sync_publisher_schedule.mjs",
    "../image-migration/find-orphans.js",
    "../release/client_sync_private_load.mjs",
    "../release/ios_build_and_upload.sh",
    "../release/fastlane/Fastfile",
    "../release/play_release_readback.rb",
  ];
  const consumerText = consumerFiles.map((path) =>
    readFileSync(new URL(path, import.meta.url), "utf8")
  ).join("\n");
  const referenced = new Set([
    ...consumerText.matchAll(/process\.env\.([A-Z][A-Z0-9_]*)/g),
    ...consumerText.matchAll(/ENV(?:\.fetch)?\(['"]([A-Z][A-Z0-9_]*)['"]\)?/g),
    ...consumerText.matchAll(/^:\s*"\$\{([A-Z][A-Z0-9_]*)[:}]/gm),
    ...consumerText.matchAll(/['"]((?:DATABASE_URL|CF_ACCOUNT_ID|R2_[A-Z0-9_]+))['"]/g),
  ].map((match) => match[1]).filter(Boolean));
  const ignoredNonPrivateRuntimeNames = new Set([
    "PATH", "NODE_PATH", "VERSION", "IPA_PATH", "PLAY_AAB_PATH",
    "PLAY_CONFIRMATION", "PLAY_TARGET_TRACK", "CUTOVER_CONFIRMATION",
    "FASTLANE_ENABLE_BETA_DELIVER_SYNC_SCREENSHOTS", "READ_ONLY_TARGET_VERSION",
  ]);
  for (const name of referenced) {
    if (!ignoredNonPrivateRuntimeNames.has(name)) {
      assert.ok(schema.properties[name], `consumer input missing from schema: ${name}`);
    }
  }
});
