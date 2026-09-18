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
# The browser starts NOW, on a holding screen, and never waits.
#
# It used to wait for the watch before launching, which meant the TV showed
# kernel boot messages and a login prompt until someone switched the TV link
# on — in a resuscitation bay. waiting.html says what is happening and
# navigates to the watch by itself when it appears.
HOLDING="file://$(cd "$(dirname "$0")" && pwd)/waiting.html"

# Ask to join, rather than waiting to be found.
#
# NetworkManager backs its scan interval off to about two minutes once it has
# been failing to find any network — which is exactly this Pi's life, sitting
# in a bay all day with the watch's access point off. Waiting passively meant
# the display could take that long to appear after the TV link was switched on.
# Nudging it needs NetworkManager permissions the kiosk user only has because
# of the polkit rule in this directory; without that this still works, just
# slowly, so the failure is graceful.
NETWORK="${CODERING_NETWORK:-codering-tv}"
(
    while :; do
        if ! nmcli -t -f NAME connection show --active 2>/dev/null | grep -qx "$NETWORK"; then
            nmcli device wifi rescan >/dev/null 2>&1
            nmcli connection up "$NETWORK" >/dev/null 2>&1
        fi
        sleep 5
    done
) &
nudge=$!
trap 'kill "$nudge" 2>/dev/null' EXIT INT TERM

# Not exec: the nudge above has to be cleaned up when this exits, and systemd
# restarting the unit should not leave an orphan looping on the radio.
cog --platform=drm "$HOLDING"
