#!/usr/bin/env python3
"""Patch only the pinned upstream router's JWT condition, fail on drift."""
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
source = source.replace('"google-auth-complete"].includes', '"google-auth-complete", "auth-email-hook", "email-provider-events", "email-confirmation-status", "process-email-queue"].includes')
source = source.replace('"email-confirmation-status"].includes', '"email-confirmation-status", "process-email-queue"].includes')
marker = '/* festapp-google-proof-v1 */'
if marker not in source:
    condition = re.compile(r"if \(req.method !== (['\"])OPTIONS\1 && VERIFY_JWT\)")
    match = condition.search(source)
    if match is None or not re.search(r'const service_name\s*=\s*path_parts\[1\]', source[match.end():]):
        raise SystemExit('upstream Function JWT routing contract changed')
    replacement = 'if (req.method !== "OPTIONS" && VERIFY_JWT && !["google-auth-start", "google-auth-callback", "google-auth-complete", "auth-email-hook", "email-provider-events", "email-confirmation-status", "process-email-queue"].includes(new URL(req.url).pathname.split("/")[1])) ' + marker
    source = source[:match.start()] + replacement + source[match.end():]
    path.write_text(source)

private_marker = '/* festapp-email-gateway-private */'
if private_marker not in source:
    route = re.search(r'const service_name\s*=\s*path_parts\[1\][^\n]*', source)
    if route is None:
        raise SystemExit('upstream Function private routing contract changed')
    source = source[:route.end()] + '\n    if (service_name === "send-email-gateway") return new Response("Not found", {status: 404}); ' + private_marker + source[route.end():]
    path.write_text(source)

path.write_text(source)
