#!/usr/bin/env bash
set -euo pipefail

python3 automation/ci/run.py install tools/festapp
pnpm --dir tools/festapp run pretest:postgres
