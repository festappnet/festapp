"""Ignored local capture/replay paths; historical inputs are never recaptured."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def evidence_dir(*required):
    folder = Path(os.environ.get('FESTAPP_AUTHORIZATION_EVIDENCE_DIR',
                                 ROOT / '.codex-artifacts/authorization/run')).expanduser().resolve()
    missing = [name for name in required if not (folder / name).is_file()]
    if missing:
        raise SystemExit('Missing authorization replay inputs in ' + str(folder) + ': ' +
                         ', '.join(missing) + '. Restore the paired immutable captures using ' +
                         'docs/archive/canonical-authorization-evidence-2026-10-20.md; ' +
                         'never derive a historical baseline from current SQL.')
    folder.mkdir(parents=True, exist_ok=True)
    return folder
