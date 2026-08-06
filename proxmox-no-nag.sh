#!/bin/sh

# Strips the "No valid subscription" popup from the Proxmox VE web UI.
#
# Every community fix seds the body of Proxmox.Utils.checked_command() in
# proxmoxlib.js, which stops matching whenever upstream reformats the toolkit —
# a prettier pass in the 8.4.x line broke the widely copied one-liner. This
# matches no upstream text at all: it appends a marked block that reassigns
# checked_command. Proxmox.Utils is an ExtJS singleton whose methods are
# Ext.apply()'d onto the instance, so a plain reassignment after the class is
# built shadows the packaged one.
#
# proxmoxlib.js isn't a conffile, so every proxmox-widget-toolkit upgrade
# restores it without prompting — setup.sh installs an apt hook that re-runs
# this afterwards. Safe to run by hand any number of times.

set -e

# PROXMOXLIB exists so the script can be exercised against a fixture off-host.
LIB=${PROXMOXLIB:-/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js}
MARKER_BEGIN='/* >>> dotfiles no-nag >>> */'
MARKER_END='/* <<< dotfiles no-nag <<< */'

[ -f "$LIB" ] || exit 0

if [ ! -w "$LIB" ]; then
  echo "$LIB is not writable — run as root." >&2
  exit 1
fi

# Same-dir temp so the final rename is atomic — pveproxy may be serving the
# file, and rewriting it in place exposes a partial-read window. cp -p clones
# the packaged file's owner and mode onto the temp before it's filled.
tmp=$(mktemp "$LIB.XXXXXX")
trap 'rm -f "$tmp"' EXIT
# dash skips the EXIT trap on unhandled fatal signals; exiting from a handler runs it.
trap 'exit 1' INT TERM HUP
cp -p "$LIB" "$tmp"

# Markers rather than line numbers: an older block is dropped wherever it
# sits, and re-appending means an updated snippet propagates on the next run.
# Only the marked range is removed — content after the block is preserved.
awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
  index($0, begin) { skip = 1; next }
  skip { if (index($0, end)) skip = 0; next }
  { print }
' "$LIB" > "$tmp"

if [ "$1" != "--revert" ]; then
  {
    printf '%s\n' "$MARKER_BEGIN"
    cat <<'SNIPPET'
// checked_command() gates UI actions on an active subscription and shows the
// "No valid subscription" dialog when there isn't one.
(function () {
  function silence() {
    if (typeof Proxmox === 'undefined' || !Proxmox.Utils) {
      return false;
    }
    Proxmox.Utils.checked_command = function (orig_cmd) {
      orig_cmd();
    };
    return true;
  }
  // Utils.js is bundled well ahead of this; onReady only covers a future bundle
  // order that defers the singleton.
  if (!silence() && typeof Ext !== 'undefined' && Ext.onReady) {
    Ext.onReady(silence);
  }
})();
SNIPPET
    printf '%s\n' "$MARKER_END"
  } >> "$tmp"
fi

if cmp -s "$tmp" "$LIB"; then
  exit 0
fi

mv "$tmp" "$LIB"

if [ "$1" = "--revert" ]; then
  echo "Restored the Proxmox subscription notice."
else
  echo "Removed the Proxmox subscription notice."
fi

# No-op when pveproxy isn't running, e.g. partway through a dpkg run.
systemctl try-restart pveproxy.service 2>/dev/null || true
