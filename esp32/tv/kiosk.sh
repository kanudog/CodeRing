#!/bin/sh
# kiosk.sh — the trauma-bay display, as an appliance.
#
# cog on its DRM platform talks straight to KMS: no compositor, no desktop, no
# window manager, no way out. That is not just tidiness on this board — a Pi
# Zero 2 W has 424 MB, and two Chromium instances were enough to drive the load
# average to 11 and stop it answering SSH. WebKit here is one process pair.
#
# Chromium remains installed and is the fallback if a page ever needs it; it
# runs under cage, which is why cage is still installed too.
set -eu

# Where the snapshot feed lives. Today an SSH reverse tunnel to a Mac running
# `make preview`; at M5 the watch itself, on its own access point.
URL="${CODERING_URL:-http://localhost:8765/tv}"

# The display is the whole point, so wait for it rather than failing at boot:
# systemd may start us before DRM has settled, and a unit that dies once and
# restarts five seconds later is a screen that flickers on every power-up.
i=0
while [ ! -e /dev/dri/card0 ] && [ "$i" -lt 30 ]; do i=$((i + 1)); sleep 1; done

exec cog --platform=drm "$URL"
