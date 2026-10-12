#!/usr/bin/env bash
# Prints and asserts the toolchain/native versions a CI job actually tested.
# Runner image labels are not proof of dependency versions (#49).
set -euo pipefail

swift --version
echo "libvips $(pkg-config --modversion vips)"
echo "cairo   $(pkg-config --modversion cairo)"
vips --vips-config

pkg-config --atleast-version=8.16.0 vips || { echo "libvips < 8.16 is below the Hokusai baseline" >&2; exit 1; }
pkg-config --atleast-version=1.16.0 cairo || { echo "Cairo < 1.16 is below the Hokusai baseline" >&2; exit 1; }
pkg-config --exists cairo-pdf || { echo "Cairo was built without PDF surface support" >&2; exit 1; }

if [ -n "${EXPECTED_SWIFT:-}" ]; then
    swift --version 2>&1 | grep -q "Swift version ${EXPECTED_SWIFT}" \
        || { echo "expected Swift ${EXPECTED_SWIFT}" >&2; exit 1; }
fi
