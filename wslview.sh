#!/bin/sh
# Stand-in for wslu's wslview, which isn't packaged for Ubuntu 26.04. Opens the
# target with its Windows default handler. Start-Process, not explorer.exe:
# explorer silently falls back to a File Explorer window on args it dislikes.
target=$1

# Windows apps can't see WSL paths; translate local files before handing over.
[ -e "$target" ] && target=$(wslpath -w "$target")

# Single-quote for PowerShell (embedded quotes double) so URL metacharacters
# like & and $ pass through literally.
escaped=$(printf %s "$target" | sed "s/'/''/g")
exec powershell.exe -NoProfile -NonInteractive -Command "Start-Process '$escaped'" >/dev/null 2>&1
