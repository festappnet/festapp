#!/usr/bin/env python3
"""Patch the pinned router's proof routes and per-worker environment, fail on drift."""
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
source = source.replace('"google-auth-complete"].includes', '"google-auth-complete", "auth-email-hook", "email-provider-events", "email-confirmation-status", "process-email-queue", "bank-sync-webhook", "bank-sync-reconcile"].includes')
source = source.replace('"email-confirmation-status"].includes', '"email-confirmation-status", "process-email-queue", "bank-sync-webhook", "bank-sync-reconcile"].includes')
marker = '/* festapp-google-proof-v1 */'
if marker in source and '"bank-sync-webhook"' not in source:
    source=source.replace('"process-email-queue"].includes', '"process-email-queue", "bank-sync-webhook", "bank-sync-reconcile"].includes')
if marker not in source:
    condition = re.compile(r"if \(req.method !== (['\"])OPTIONS\1 && VERIFY_JWT\)")
    match = condition.search(source)
    if match is None or not re.search(r'const service_name\s*=\s*path_parts\[1\]', source[match.end():]):
        raise SystemExit('upstream Function JWT routing contract changed')
    replacement = 'if (req.method !== "OPTIONS" && VERIFY_JWT && !["google-auth-start", "google-auth-callback", "google-auth-complete", "auth-email-hook", "email-provider-events", "email-confirmation-status", "process-email-queue", "bank-sync-webhook", "bank-sync-reconcile"].includes(new URL(req.url).pathname.split("/")[1])) ' + marker
    source = source[:match.start()] + replacement + source[match.end():]

# Remove the former standalone sender route guard from an installed router.
source = re.sub(r'(?m)^\s*if \(service_name === "send-email-gateway"\) return new Response\("Not found", \{status: 404\}\); /\* festapp-email-gateway-private \*/\n', '\n', source)
if '/* festapp-email-gateway-private */' in source:
    raise SystemExit('old sender route guard has drifted')

environment_marker = '/* festapp-email-worker-env */'
if environment_marker not in source:
    environment = re.search(r'const envVars = Object.keys\(envVarsObj\).map\(\(k\) => \[k, envVarsObj\[k\]\]\);?', source)
    if environment is None:
        raise SystemExit('upstream Function environment propagation contract changed')
    source = source[:environment.start()] + 'const envVars = emailWorkerEnvironment(service_name, envVarsObj) ' + environment_marker + source[environment.end():]
    source = 'import { emailWorkerEnvironment } from "../_shared/emailWorkerEnvironment.ts";\n' + source
path.write_text(source)
