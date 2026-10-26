#!/usr/bin/env python3
"""Launch only task-owned headless Chrome with production backend DNS disabled.

Pass this executable to agent-browser. Constructing argv here preserves the comma
inside Chromium's resolver rule on CLI versions that split every --args comma.
"""
import os
import json
from pathlib import Path
import sys

chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
args = sys.argv[1:]
if args == ["--version"]:
    os.execv(chrome, [chrome, *args])
profile = next((arg.split("=", 1)[1] for arg in args if arg.startswith("--user-data-dir=")), "")
if not any(arg.startswith("--headless") for arg in args) or not Path(profile).name.startswith("agent-browser-chrome-"):
    raise SystemExit("A temporary agent-browser headless profile is required")
if any(arg.startswith(("--proxy-server", "--host-resolver-rules")) for arg in args):
    raise SystemExit("Conflicting network configuration refused")
if "--festapp-wix-block-storage=1" in args:
    # Native Chrome cookie/storage policy in the disposable profile only.
    preferences = Path(profile) / "Default" / "Preferences"
    preferences.parent.mkdir(parents=True, exist_ok=True)
    value = json.loads(preferences.read_text()) if preferences.exists() else {}
    value.setdefault("profile", {}).setdefault("default_content_setting_values", {})["cookies"] = 2
    preferences.write_text(json.dumps(value))
args.extend([
    "--festapp-wix-qa=20261025",
    "--enable-automation",
    "--no-proxy-server",
    "--host-resolver-rules=MAP api.festapp.net ~NOTFOUND, MAP *.supabase.co ~NOTFOUND",
])
os.execv(chrome, [chrome, *args])
