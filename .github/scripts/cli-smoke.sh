#!/usr/bin/env bash
# Smoke-tests the release CLI binary against the bundled fixtures.
set -euo pipefail

BIN=.build/release/hokusai
FIXTURE=Tests/HokusaiTests/Fixtures/landscape-asym.jpg
OUT="$(mktemp -d)"

$BIN info
$BIN thumbnail --input "$FIXTURE" --output "$OUT/thumb.jpg" --width 100 --height 100 --crop centre
$BIN resize --input "$FIXTURE" --output "$OUT/resize.webp" --width 100 --height 100 --fit cover
if $BIN thumbnail --input "$FIXTURE" --output "$OUT/bad.jpg" --width 0; then
    echo "expected non-zero exit for invalid width" >&2
    exit 1
fi
