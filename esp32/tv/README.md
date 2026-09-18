# The trauma-bay display

`index.html` is the TV mirror: the same code the wrist is running, sized for a
television across a resus bay. It is **one self-contained file** — at M5 the
watch serves it from its own flash over its own access point, and that access
point has no uplink, so a web font or a CDN script would simply never load in
the room where it matters.

It draws nothing it did not get from `cr_snapshot_json`. The panel and this
display are two consumers of one derived feed; deciding anything clinical here
would put a second source of truth in the room.

## Look at it now

```bash
cd esp32 && make preview      # then http://localhost:8765/tv
```

`http://localhost:8765` in another tab drives the engine, and this follows.

## What it shows

Four columns, because the log earns a full-height one: a horizontal strip
could only ever show the last few entries, and what the room asks is "what has
been done, in what order".

| Column | |
|---|---|
| ring | the countdown the current state is about — cycle during the arrest, hands-off during a check, vitals post-ROSC. One ring, one position, so the eye does not move when the outcome changes. |
| clocks | total code time, the biggest number on the screen, and the epi interval under it |
| time since last | everything given, with how many |
| timeline | the whole log, newest at TOP, colour-coded, doses included |

## After the code ends

The three live columns become a handoff summary — outcome, the numbers a
receiving team asks for, every drug with its count — and the timeline column is
left exactly as it is, because the full history already IS what a handoff
wants. It stays up for ten minutes, then the screen goes quiet.

The countdown is anchored to the moment the code **ended**, not to when the
page loaded, so a reload, a browser restart or a Pi reboot mid-window resumes
the same countdown instead of granting another ten minutes. Same discipline as
the engine: store the anchor, derive the rest.

Times here are offsets (`+m:ss` into the code), not wall-clock. The watch's
handoff card can say "ROSC at 14:32:06" because it has a real clock; this
board's is stamped in at build time until M5 brings up the RTC, and a
confidently wrong wall time on a handoff screen is worse than none.

Two behaviours worth keeping if this is ever rewritten:

- **It counts locally between polls.** The snapshot carries integer ms for
  exactly that reason. But it reproduces the engine's freezes honestly: the
  CPR cycle stops while paused, drug intervals keep running through pauses and
  pulse checks (invariant 7). Extrapolating through a pause would put this
  screen ahead of the wrist.
- **Overdue FILLS the ring.** Draining it to zero made the alarm state the one
  with the least on screen, which is backwards from twenty feet away.

## Running it on a Raspberry Pi

Measured on a Pi Zero 2 W (512 MB, of which 424 MB is usable):

| | used | free | processes |
|---|---|---|---|
| Chromium under cage | 310 MB | 114 MB | 12 |
| **cog on its DRM platform** | **244 MB** | **180 MB** | **7** |

`cog` talks straight to KMS — no compositor, no desktop. `kiosk.sh` launches
it. Two things that cost an hour each:

- **One browser at a time.** A kiosk plus a second headless browser for a
  screenshot drove the load average to 11 and stopped the board answering SSH
  for ~90 s.
- **With no TV attached, KMS reports the output disconnected and the kiosk has
  nothing to draw on.** Force it in `/boot/firmware/cmdline.txt`:
  `video=HDMI-A-1:1920x1080@60D` — the trailing `D` forces the digital output
  on. Worth keeping permanently: it is also what stops a Pi that boots before
  the TV is switched on coming up with no picture.

### Leave the boot messages visible

Tempting to add `quiet` and drop `console=tty1` so the TV shows nothing but the
app. Don't. We did, and the next unclean shutdown produced a Pi that sat at a
solid green LED with a completely black screen — indistinguishable from dead
hardware, because a filesystem check, a kernel panic and a failed root mount
all look the same when nothing is allowed to print.

It was none of those: the card was healthy, the boot partition passed a clean
check, and it simply needed a few minutes to fsck after the power was pulled.
Half an hour went into diagnosing that, and a re-image was nearly done for no
reason.

This device has no keyboard, no console and — when it is broken — no network.
Boot output is the only thing that can tell you what is happening, and a few
seconds of scrolling text before the holding screen appears is a cheap price.
Disable `getty@tty1` instead, so nobody ever sees a login prompt.

### Pull the power safely

The root filesystem is read-write, so an unclean shutdown means an fsck on the
next boot and, eventually, real corruption. Shut it down properly:

```bash
ssh <pi> 'sudo shutdown -h now'
```

That needs the Pi reachable, which it is NOT while it is on the watch's access
point — turn the TV link off at the wrist first and let it fall back. That
dependency is the weak point of this design; making the root filesystem
read-only would remove it, and is the right fix for something wall-mounted.

As a systemd unit (substitute your own user for `<user>`):

```ini
[Unit]
Description=CodeRing trauma-bay display
After=systemd-user-sessions.service seatd.service network-online.target
Wants=seatd.service

[Service]
Type=simple
User=<user>
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/home/<user>/kiosk.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

`RestartSec` is not decoration: on 424 MB a restart storm is how a recoverable
blip becomes a wedged box.

`CODERING_URL` overrides where it points. Until the watch serves the page, that
is a machine running `make preview` — reachable over an SSH reverse tunnel
(`ssh -N -R 8765:127.0.0.1:8765 <pi>`), which needs no code change and exposes
nothing to the network.
