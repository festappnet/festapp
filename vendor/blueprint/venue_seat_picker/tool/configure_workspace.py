#!/usr/bin/env python3
"""Local-only resolution for unpublished core. Overrides never ship in archives."""
from pathlib import Path
root=Path(__file__).resolve().parent.parent
(root/'pubspec_overrides.yaml').write_text('dependency_overrides:\n  venue_layout_core:\n    path: packages/venue_layout_core\n')
(root/'example/pubspec_overrides.yaml').write_text('dependency_overrides:\n  venue_layout_core:\n    path: ../packages/venue_layout_core\n')
print('Local core resolution configured')
