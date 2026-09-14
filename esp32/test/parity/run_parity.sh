#!/bin/sh
# run_parity.sh — run one scenario through BOTH engines and diff the traces.
# Any difference is a behavioural divergence between the watch and this port.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
esp32=$(cd "$here/../.." && pwd)
build="$esp32/build/parity"
mkdir -p "$build"

CC=${CC:-cc}
echo "building the C trace…"
# shellcheck disable=SC2046
$CC -std=c99 -Wall -Wextra -Werror -g -O1 \
    -I"$esp32/core/include" -I"$esp32/core/src" \
    $(ls "$esp32"/core/src/*.c) "$here/scenario.c" -lm -o "$build/scenario"

if ! command -v swift >/dev/null 2>&1; then
    echo "swift not found — skipping the parity diff (the C trace still built)."
    exit 0
fi

echo "building the Swift trace…"
swift build --package-path "$here/SwiftParity" -c release >/dev/null

"$build/scenario" > "$build/c.trace"
swift run --package-path "$here/SwiftParity" -c release parity > "$build/swift.trace" 2>/dev/null

if diff -u "$build/swift.trace" "$build/c.trace" > "$build/parity.diff"; then
    lines=$(wc -l < "$build/c.trace" | tr -d ' ')
    echo "parity: IDENTICAL — $lines trace lines match the Swift engine exactly"
    exit 0
fi

echo "parity: DIVERGED (- Swift, + C)"
cat "$build/parity.diff"
exit 1
