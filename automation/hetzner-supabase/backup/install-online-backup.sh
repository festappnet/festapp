#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_BACKUP_INSTALL_ACK:-}" == "install-encrypted-off-host-backup-without-cutover" ]] ||
  fail "set FESTAPP_BACKUP_INSTALL_ACK=install-encrypted-off-host-backup-without-cutover"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved Festapp host"
[[ -f /etc/festapp-backup/r2.env && "$(stat -c '%a' /etc/festapp-backup/r2.env)" == "600" ]] ||
  fail "root-only R2 backup config is missing"
for file in create-online-encrypted-backup.sh upload-encrypted-runtime-logs.sh \
  festapp-supabase-backup.service festapp-supabase-backup.timer \
  festapp-runtime-log-upload.service festapp-runtime-log-upload.timer; do
  [[ -f "$SCRIPT_DIR/$file" ]] || fail "missing $file"
done
install -d -o root -g root -m 0700 /opt/festapp-backup /var/backups/festapp-supabase \
  /var/backups/festapp-supabase-logs
install -o root -g root -m 0700 "$SCRIPT_DIR/create-online-encrypted-backup.sh" \
  /opt/festapp-backup/create-online-encrypted-backup.sh
install -o root -g root -m 0700 "$SCRIPT_DIR/upload-encrypted-runtime-logs.sh" \
  /opt/festapp-backup/upload-encrypted-runtime-logs.sh
install -o root -g root -m 0644 "$SCRIPT_DIR/festapp-supabase-backup.service" \
  /etc/systemd/system/festapp-supabase-backup.service
install -o root -g root -m 0644 "$SCRIPT_DIR/festapp-supabase-backup.timer" \
  /etc/systemd/system/festapp-supabase-backup.timer
install -o root -g root -m 0644 "$SCRIPT_DIR/festapp-runtime-log-upload.service" \
  /etc/systemd/system/festapp-runtime-log-upload.service
install -o root -g root -m 0644 "$SCRIPT_DIR/festapp-runtime-log-upload.timer" \
  /etc/systemd/system/festapp-runtime-log-upload.timer
systemctl daemon-reload
systemctl enable --now festapp-supabase-backup.timer
systemctl enable --now festapp-runtime-log-upload.timer
echo "Festapp encrypted off-host backup and log timers installed; no cutover action performed."
