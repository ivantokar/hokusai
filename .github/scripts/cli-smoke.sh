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

# Typos fail loudly instead of falling back to a default.
for bad in "--fit bogus" "--kernel nope"; do
    if $BIN resize --input "$FIXTURE" --output "$OUT/bad.png" --width 50 $bad; then
        echo "expected non-zero exit for: $bad" >&2
        exit 1
    fi
done
if $BIN convert --input "$FIXTURE" --output "$OUT/mismatch.jpg" --format webp; then
    echo "expected non-zero exit for a format/extension mismatch" >&2
    exit 1
fi
test ! -e "$OUT/mismatch.jpg"

# The pipeline command: ordered steps, one decode and one encode, a typed result.
$BIN run "$FIXTURE" auto-orient resize --width 100 --height 60 blur --sigma 1 webp --quality 70 -o "$OUT/run.webp" --json | grep -q '"format":"webp"'
$BIN run "$FIXTURE" resize --width 50 png -o - > "$OUT/stdout.png"
head -c 4 "$OUT/stdout.png" | LC_ALL=C grep -aq PNG
if $BIN run "$FIXTURE" png --quality 10 -o "$OUT/bad.png"; then
    echo "expected non-zero exit for an option the step does not have" >&2
    exit 1
fi
$BIN inspect --input "$OUT/run.webp" --json | grep -q '"format":"webp"'

$BIN convert --input "$FIXTURE" --output "$OUT/converted.png"
$BIN inspect --input "$OUT/converted.png"

# The benchmark harness launches one fresh worker process per cell.
$BIN benchmark run --input "$FIXTURE" --workloads thumbnail-jpeg --evaluations 1,2 --vips-concurrency 1,auto \
    --json-output "$OUT/bench.json"
$BIN benchmark compare "$OUT/bench.json" "$OUT/bench.json"
grep -q '"schemaVersion" : 1' "$OUT/bench.json"
