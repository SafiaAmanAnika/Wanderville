#!/usr/bin/env bash
#
# Builds the Opus decoder extension for the Godot client on macOS and Linux.
#
# Godot has no Opus decoder of its own, so the client needs one. This builds
# it from source: the official Xiph release of libopus and the official Godot
# bindings, both pinned, so nothing is taken on trust from a third party
# build.
#
# The libraries are written to bin/ under the names the .gdextension file
# expects, one for the editor and debug exports and one for release exports.
# The client never depends on them being there: it only asks the server for
# Opus when the decoder actually loaded, so a build without it keeps using raw
# PCM.
#
#   ./build.sh            # both variants
#   ./build.sh Release    # only the release variant

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="$here/bin"

configuration="${1:-Both}"

if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake was not found. Install it, or run: pip install cmake ninja" >&2
    exit 1
fi

case "$(uname -s)" in
    Darwin) platform="macos"; extension="dylib" ;;
    Linux) platform="linux"; extension="so" ;;
    *) echo "Unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    arm64|aarch64) architecture="arm64" ;;
    x86_64|amd64) architecture="x86_64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

case "$configuration" in
    Debug) targets=(template_debug) ;;
    Release) targets=(template_release) ;;
    Both) targets=(template_debug template_release) ;;
    *) echo "Usage: $0 [Debug|Release|Both]" >&2; exit 1 ;;
esac

mkdir -p "$bin"

for target in "${targets[@]}"; do
    build="$here/build/$target"
    echo "Configuring $target in $build"
    cmake -S "$here" -B "$build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DGODOTCPP_TARGET="$target" \
        -DOPUS_BUILD_TESTING=OFF \
        -DOPUS_INSTALL=OFF
    echo "Building $target"
    cmake --build "$build" -j "$(getconf _NPROCESSORS_ONLN)"

    source="$build/libwanderville_opus.$extension"
    if [ ! -f "$source" ]; then
        source="$(find "$build" -name "libwanderville_opus.$extension" -print -quit)"
    fi
    if [ -z "$source" ]; then
        echo "the build produced no library for $target" >&2
        exit 1
    fi
    if [ "$platform" = "macos" ]; then
        destination="$bin/libwanderville_opus.macos.$target.dylib"
    else
        destination="$bin/libwanderville_opus.linux.$target.$architecture.so"
    fi
    cp "$source" "$destination"
    echo "Wrote $destination"
done

echo "Done. The client picks the extension up from native/opus/bin."
