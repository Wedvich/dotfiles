#!/bin/sh
# Stand-in for wslu's wslview, which isn't packaged for Ubuntu 26.04. Hands URLs
# to the Windows default browser. explorer.exe exits non-zero even on success,
# so swallow the status or callers (gh, xdg-open probes) report a failure.
explorer.exe "$1" >/dev/null 2>&1
exit 0
