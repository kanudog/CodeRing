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

# Wait for the server before launching the browser.
#
# cog exits when it cannot load its page, and systemd's Restart=always then
# brings it back every few seconds — a restart loop for as long as the watch's
# access point is off, which is most of the time, since the TV link is off by
# default to save the watch's battery. Waiting quietly is the same outcome
# without the churn, and it means the display comes up on its own the moment
# the watch starts serving, with nobody touching the Pi.
until curl -sf -o /dev/null --max-time 3 "$URL"; do
    sleep 3
done

exec cog --platform=drm "$URL"
