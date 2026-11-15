"""Keep the executable probe and native plugin on the same audited dependency."""
from pathlib import Path
import tomllib

ROOT = Path(__file__).resolve().parents[2]
SOURCE = "git+https://github.com/festappnet/gtk-rs-core.git?rev=5893f66e6385c2235982db0b2482aa86b46ea097#5893f66e6385c2235982db0b2482aa86b46ea097"
for name in ("packages/super_native_extensions/rust", "automation/native-security"):
    packages = tomllib.loads((ROOT / name / "Cargo.lock").read_text())["package"]
    assert not any(p["name"] == "atty" for p in packages), f"{name}: atty returned"
    glib = [p for p in packages if p["name"] == "glib"]
    assert len(glib) == 1 and glib[0].get("source") == SOURCE, f"{name}: GLib backport pin drift"
print("PASS native dependency locks: patched GLib revision matches; atty absent")
