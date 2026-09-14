#!/bin/sh
# spec_coverage.sh — the Swift tests are the specification, so prove that
# every one of them is either ported or consciously deferred, and that the
# stable UUIDs still match Defaults.swift (invariant 1).
#
# Runs as part of `make test`. Needs no tools beyond awk/grep/sort/comm.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
swift_tests="$repo/CodeCore/Tests/CodeCoreTests/CodeCoreTests.swift"
swift_defaults="$repo/CodeCore/Sources/CodeCore/Defaults/Defaults.swift"
c_defaults="$here/../core/include/cr_defaults.h"

if [ ! -f "$swift_tests" ]; then
    echo "spec coverage: SKIPPED (no Swift sources at $swift_tests)"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Swift: "final class FooTests: XCTestCase" + "func testBar()" → FooTests.testBar
awk '
    /class [A-Za-z0-9_]+Tests/ {
        match($0, /class [A-Za-z0-9_]+Tests/)
        cls = substr($0, RSTART + 6, RLENGTH - 6)
    }
    /func test[A-Za-z0-9_]*\(/ {
        match($0, /test[A-Za-z0-9_]*/)
        if (cls != "") print cls "." substr($0, RSTART, RLENGTH)
    }
' "$swift_tests" | sort -u > "$tmp/swift"

# C: the names registered in the test tables.
grep -ho '"[A-Za-z0-9_]*Tests\.test[A-Za-z0-9_]*"' "$here"/*.c | tr -d '"' | sort -u > "$tmp/ported"
grep -v '^[[:space:]]*#' "$here/deferred_swift_tests.txt" | awk 'NF {print $1}' | sort -u > "$tmp/deferred"
sort -u "$tmp/ported" "$tmp/deferred" > "$tmp/accounted"

status=0

missing=$(comm -23 "$tmp/swift" "$tmp/accounted")
if [ -n "$missing" ]; then
    echo "spec coverage: FAIL — Swift tests neither ported nor deferred:"
    echo "$missing" | sed 's/^/    /'
    echo "    → port it, or add it to test/deferred_swift_tests.txt with a reason."
    status=1
fi

unknown=$(comm -13 "$tmp/swift" "$tmp/accounted")
if [ -n "$unknown" ]; then
    echo "spec coverage: FAIL — named here but not found in CodeCoreTests.swift (typo, or the Swift test was renamed):"
    echo "$unknown" | sed 's/^/    /'
    status=1
fi

both=$(comm -12 "$tmp/ported" "$tmp/deferred")
if [ -n "$both" ]; then
    echo "spec coverage: FAIL — both ported and listed as deferred:"
    echo "$both" | sed 's/^/    /'
    status=1
fi

# Invariant 1: the stable ids are permanent. Compare the C header with the
# Swift source that owns them.
if [ -f "$swift_defaults" ]; then
    grep -o 'C0DE0000-[0-9A-Fa-f-]*' "$swift_defaults" | tr 'a-f' 'A-F' | sort -u > "$tmp/swift_ids"
    grep -o 'C0DE0000-[0-9A-Fa-f-]*' "$c_defaults" | tr 'a-f' 'A-F' | sort -u > "$tmp/c_ids"
    if ! diff -u "$tmp/swift_ids" "$tmp/c_ids" > "$tmp/iddiff"; then
        echo "spec coverage: FAIL — stable UUIDs differ from Defaults.swift (invariant 1):"
        sed '1,2d' "$tmp/iddiff" | sed 's/^/    /'
        status=1
    fi
    ids=$(wc -l < "$tmp/c_ids" | tr -d ' ')
else
    ids=0
fi

if [ "$status" -eq 0 ]; then
    total=$(wc -l < "$tmp/swift" | tr -d ' ')
    ported=$(wc -l < "$tmp/ported" | tr -d ' ')
    deferred=$(wc -l < "$tmp/deferred" | tr -d ' ')
    echo "spec coverage: $total Swift tests — $ported ported, $deferred deferred; $ids stable ids match"
fi
exit $status
