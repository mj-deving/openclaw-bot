#!/usr/bin/env bash
# install-wrappers.sh — root-side installer for the scoped sudo wrappers.
#
# RUN AS ROOT ON THE VPS. Do NOT run from the openclaw account.
#
# What this does:
#   1. Copies every script from ./sbin/ to /usr/local/sbin/ with mode 0755, owner root:root.
#   2. Replaces /etc/sudoers.d/openclaw-restricted-admin with the version in ./sudoers.d/.
#   3. Validates the new sudoers file with `visudo -c` BEFORE swapping it in.
#      If validation fails, the existing sudoers file is untouched.
#
# Idempotent. Safe to re-run after edits in the repo.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "error: must run as root" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SBIN_SRC="$SCRIPT_DIR/sbin"
SUDOERS_SRC="$SCRIPT_DIR/sudoers.d/openclaw-restricted-admin"
SUDOERS_DEST="/etc/sudoers.d/openclaw-restricted-admin"

if [[ ! -d "$SBIN_SRC" ]]; then
  echo "error: missing $SBIN_SRC" >&2
  exit 1
fi
if [[ ! -f "$SUDOERS_SRC" ]]; then
  echo "error: missing $SUDOERS_SRC" >&2
  exit 1
fi

echo "== Installing wrapper scripts to /usr/local/sbin/ =="
for src in "$SBIN_SRC"/openclaw-*; do
  [[ -f "$src" ]] || continue
  name=$(basename "$src")
  install -m 0755 -o root -g root "$src" "/usr/local/sbin/$name"
  echo "  installed: /usr/local/sbin/$name"
done

echo
echo "== Validating sudoers file =="
# Stage to a temp path and run visudo -c against it before replacing the live file.
TMP_SUDOERS=$(mktemp --tmpdir=/etc/sudoers.d .openclaw-restricted-admin.XXXXXX)
trap 'rm -f "$TMP_SUDOERS"' EXIT
install -m 0440 -o root -g root "$SUDOERS_SRC" "$TMP_SUDOERS"

if ! visudo -c -f "$TMP_SUDOERS"; then
  echo "error: visudo validation failed — leaving existing sudoers untouched" >&2
  exit 1
fi

echo
echo "== Installing sudoers drop-in =="
install -m 0440 -o root -g root "$SUDOERS_SRC" "$SUDOERS_DEST"
echo "  installed: $SUDOERS_DEST"

echo
echo "== Verifying live sudoers =="
visudo -c

echo
echo "== Final privilege listing for openclaw =="
sudo -l -U openclaw || true

echo
echo "done."
