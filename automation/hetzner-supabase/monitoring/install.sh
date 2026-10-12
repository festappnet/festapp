#!/usr/bin/env bash
set -euo pipefail
# Run from an immutable staging directory with sdk.mjs and a protected token file.
[[ $EUID == 0 && $(hostname -s) == festapp-supabase-rehearsal-01 ]]
[[ $(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' /opt/festapp-supabase/docker/.env) == festapp_rehearsal_20260909220601 ]]
[[ $(node -p 'Number(process.versions.node.split(".")[0])') -ge 22 ]]
cd -- "$(dirname -- "$0")"
sha256sum --check --quiet SHA256SUMS
[[ -s token ]]
id festapp-host-monitor >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin festapp-host-monitor
install -d -m 0755 /opt/festapp-host-monitor
install -d -m 0750 -o root -g festapp-host-monitor /etc/festapp-host-monitor
install -m 0644 agent.mjs metrics.mjs sdk.mjs LICENSE /opt/festapp-host-monitor/
install -m 0640 -o root -g festapp-host-monitor token /etc/festapp-host-monitor/token
install -m 0644 festapp-host-monitor.service festapp-host-monitor.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now festapp-host-monitor.timer
systemctl start festapp-host-monitor.service
