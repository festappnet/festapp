# Controlled host alert delivery drill

Executed once on 2026-10-16 after explicit user approval. Both alert and
recovery were delivered; all application containers were preserved.
[Actual sanitized receipt](../../../docs/operations/security-remediation-20261016/host-alert-delivery-drill-result.json).
This procedure does not authorize another notification test.

The remaining proof requires a real notification to the configured recipients.
Use the existing host agent, checks, credentials and sender. Do not inject
synthetic production observations, change thresholds or register another check.

1. Read the four host checks, open host incidents, recent delivery state and
   existing project notification policy. Require all checks healthy, no open
   host incident, no host delivery in sending/unknown, and no maintenance window.
2. Verify canonical host identity, that the original host monitor timer is
   enabled/active, and that its last service execution succeeded. Record the
   initial state privately. Do not touch application containers or backup timers.
3. BEFORE stopping the timer, arm and verify an independent root systemd
   one-shot to start the original timer and service after 12 minutes. This is
   the fail-safe if workstation or SSH connectivity is lost. Keep it armed
   until recovery has actually been verified.
4. Stop only festapp-host-monitor.timer, allowing any current service execution
   to finish. The existing cadence=60s and grace=60s expire after 180s without
   a heartbeat. The monitoring scheduler should create heartbeat_missing for
   agent. Its parent relationship should inhibit subordinate CPU/memory/disk
   notifications. Observe through the existing read-only API, at most every
   30 seconds, without modifying incidents or delivery state.
5. As soon as the host incident has a delivered receipt, restart the original
   timer and trigger one normal service execution. If no delivery is proven
   within 10 minutes, restore monitoring anyway and report a failed proof.
   Accepted by the mail provider alone does not count as delivered.
6. Read back all four healthy checks and follow the natural incident recovery
   and any recovery delivery. Record exact incident/delivery IDs privately;
   publish only service/check, timestamps, state and delivery counts. Verify
   all application containers retain identity/health and backup timers remain
   active. Remove only this task-owned fail-safe after successful restoration.

The application stays available, but host resource sampling is temporarily
interrupted for at most 12 minutes plus service startup. External canaries and
backup jobs continue. The test can send an alert and a recovery email to the
existing recipients; explicit authorization is required before execution.
No automatic resend of unknown mail outcomes is permitted.
