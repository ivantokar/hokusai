#!/usr/bin/env bash
# Builds an exact libvips release from source into a prefix so CI tests a
# pinned native baseline instead of whatever the distro package happens to be.
#
# Usage: install-libvips.sh <version> <prefix>
# Build dependencies must already be installed. Re-running with an existing
# prefix (e.g. restored from cache) only re-verifies the version.
set -euo pipefail

version="$1"
prefix="$2"

if [ ! -f "$prefix/lib/pkgconfig/vips.pc" ]; then
    workdir="$(mktemp -d)"
    curl -fsSL "https://github.com/libvips/libvips/releases/download/v${version}/vips-${version}.tar.xz" \
        | tar -xJ -C "$workdir"
    cd "$workdir/vips-${version}"
    meson setup build \
        --prefix="$prefix" \
        --libdir=lib \
        --buildtype=release \
        -Dintrospection=disabled \
        -Dmodules=disabled \
        -Dexamples=false
    meson install -C build
    cd /
    rm -rf "$workdir"
fi

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
installed="$(pkg-config --modversion vips)"
if [ "$installed" != "$version" ]; then
    echo "expected libvips $version, pkg-config reports $installed" >&2
    exit 1
fi
