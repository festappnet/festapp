#!/usr/bin/env python3
"""Patch only the pinned upstream router's JWT condition, fail on drift."""
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
marker = '/* festapp-google-proof-v1 */'
if marker not in source:
    condition = re.compile(r"if \(req.method !== (['\"])OPTIONS\1 && VERIFY_JWT\)")
    match = condition.search(source)
    if match is None or not re.search(r'const service_name\s*=\s*path_parts\[1\]', source[match.end():]):
        raise SystemExit('upstream Function JWT routing contract changed')
    replacement = 'if (req.method !== "OPTIONS" && VERIFY_JWT && !["google-auth-start", "google-auth-callback", "google-auth-complete"].includes(new URL(req.url).pathname.split("/")[1])) ' + marker
    source = source[:match.start()] + replacement + source[match.end():]
    path.write_text(source)
