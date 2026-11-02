#!/usr/bin/env python3
"""Read-only Wix native proof probe using an isolated local agent-browser."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import uuid

SITES = {
    "harmony": "https://info9468674.wixsite.com/my-site-3",
    "studio": "https://dev-sitex1642529107.wix-development-sites.org/",
    "editor": "https://dev-sitex-1268240078.wix-dev-sites.org/",
}
FENCES = (
    "https://vstupenky.online/**",
    "https://api.festapp.net/rest/**",
    "https://api.festapp.net/auth/**",
    "https://api.festapp.net/functions/v1/send-ticket-order*",
    "https://api.festapp.net/functions/v1/*hold*",
)
ENV_DENY = re.compile(r"^AGENT_BROWSER_(PROVIDER|CDP|PROFILE|STATE|RESTORE|CONFIG|SESSION|NAMESPACE|AUTO_CONNECT|ARGS|HEADED)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", choices=SITES, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--live", action="store_true",
                        help="Verify deployed bytes without overriding the registered script")
    parser.add_argument("--form", default="new-form2026-test")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.form):
        parser.error("--form must be a public form slug")
    bundle = args.bundle.read_text(encoding="utf-8")
    env = {k: v for k, v in os.environ.items() if not ENV_DENY.match(k)}
    session = "wix-probe-" + uuid.uuid4().hex[:12]
    result = {"site": args.site, "form": args.form, "status": "error"}
    with tempfile.TemporaryDirectory(prefix="wix-probe-") as directory:
        config = Path(directory) / "browser.json"
        config.write_text("{}", encoding="utf-8")
        prefix = ["agent-browser", "--config", str(config), "--namespace", session,
                  "--session", session, "--headed", "false", "--args", "--mute-audio"]

        def run(*command, timeout=30):
            return subprocess.run(prefix + list(command), env=env, capture_output=True,
                                  text=True, timeout=timeout, check=True).stdout

        def evaluate(script):
            return json.loads(run("eval", script, "--json"))["data"]["result"]

        try:
            if not args.live:
                run("network", "route", "https://festapp-wix.pages.dev/widget.js*", "--body", bundle)
            for pattern in FENCES:
                run("network", "route", pattern, "--abort")
            run("open", SITES[args.site])
            run("wait", "--fn", "!!customElements.get('vstupenky-online-form')")
            slug = json.dumps(args.form)
            evaluate("(()=>{const e=document.querySelector('vstupenky-online-form');"
                     "if(!e)throw Error('missing widget');const c=e.cloneNode(false);"
                     f"c.setAttribute('form-url','https://vstupenky.online/form/'+{slug});"
                     "c.dataset.wixProbe='true';document.body.append(c);return true})()")
            deadline = time.monotonic() + 75
            while time.monotonic() < deadline:
                state = evaluate("(()=>{const e=document.querySelector('[data-wix-probe]');"
                    "const f=e?.querySelector('iframe'),a=e?.querySelector('a[href*=\"/form/\"]');"
                    "return {visibility:document.visibilityState,mode:e?.mode||null,"
                    "context:!!e?.checkoutOrigin,iframe:!!f,"
                    "iframeContext:!!f&&new URL(f.src).searchParams.has('checkout_origin'),"
                    "linkContext:!!a&&new URL(a.href).searchParams.has('checkout_origin')}})()")
                if state["context"] or state["mode"] == "Unavailable":
                    break
                time.sleep(2)
            requests = json.loads(run("network", "requests", "--filter", "wix-checkout-context", "--json"))
            statuses = []
            for request in requests.get("data", {}).get("requests", []):
                if request.get("method") != "POST":
                    continue
                detail = json.loads(run("network", "request", request["requestId"], "--json"))["data"]
                try:
                    body = json.loads(detail.get("postData") or "{}")
                except (TypeError, ValueError):
                    continue
                if body.get("formLink") == args.form:
                    statuses.append(detail.get("status"))
            scripts = json.loads(run("network", "requests", "--filter", "widget.js", "--json"))
            served = False
            expected = hashlib.sha256(bundle.encode("utf-8")).hexdigest()
            for request in scripts.get("data", {}).get("requests", []):
                if request.get("resourceType") != "Script":
                    continue
                detail = json.loads(run("network", "request", request["requestId"], "--json"))["data"]
                body = detail.get("responseBody")
                if isinstance(body, str) and hashlib.sha256(body.encode("utf-8")).hexdigest() == expected:
                    served = True
            result["bundleSha256"] = expected
            result["bundleResponseMatched"] = served
            result.update(state)
            result["proofPostStatuses"] = statuses
            result["status"] = "pass" if served and state["context"] and state["iframeContext"] and state["linkContext"] and 200 in statuses else ("unavailable" if state["mode"] == "Unavailable" else "pending")
        except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
            result["status"] = "probe-error"
        finally:
            try:
                run("close", timeout=15)
            except (OSError, subprocess.SubprocessError):
                result["cleanup"] = "close-failed"
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
