#!/usr/bin/env bash
# Build libghostty-vt + vendored deps for the current platform.
#
# Inputs:
#   ghostty-commit              # full SHA, one line
# Outputs:
#   out/lib/libghostty-vt.a
#   out/lib/libhighway.a
#   out/lib/libsimdutf.a
#   out/include/ghostty/*.h
#
# Requirements: zig 0.15.2, cmake, ninja, system ar+ranlib (macOS leg).
#
# CI uses this directly; humans can run it locally to reproduce a build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
GHOSTTY_REPO="https://github.com/ghostty-org/ghostty.git"
GHOSTTY_COMMIT="$(tr -d '[:space:]' <"${REPO_ROOT}/ghostty-commit")"

BUILD_DIR="${BUILD_DIR:-/tmp/ghostty-vt-static-build}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/out}"

# Repack archives for macOS linker alignment compatibility.
#
# Zig 0.15.x's `ar` produces archives where member objects aren't
# 8-byte aligned, which the current Apple linker rejects with:
#   ld: 64-bit mach-o member 'libhighway_zcu.o' not 8-byte aligned
#       in 'lib/libhighway.a'
# The fix landed in Zig master post-0.15 but is not backported to any
# 0.15.x release. We're stuck on 0.15.x because ghostty pins
# minimum_zig_version = "0.15.2"; once that bumps, this becomes dead
# weight (see "Removal of the workaround" in the plan).
#
# System `ar` correctly aligns members, so extract + re-archive fixes
# all archives. Idempotent.
repack_archives_for_macos() {
    if [ "$(uname)" != "Darwin" ]; then
        return 0
    fi
    echo "Repacking archives for macOS linker alignment compatibility..."
    for ar_file in "${OUT_DIR}/lib/"*.a; do
        [ -f "$ar_file" ] || continue
        echo "  $(basename "$ar_file")"
        extract_dir=$(mktemp -d)
        # Extract, drop the symbol-table index, and fix permissions —
        # Zig's archives embed mode 0 in member headers, which `ar -x`
        # honors.
        (cd "$extract_dir" && ar -x "$ar_file" 2>/dev/null && rm -f __.SYMDEF && chmod u+rw *.o)
        ar -rc "${ar_file}.tmp" "$extract_dir"/*.o
        ranlib "${ar_file}.tmp"
        mv "${ar_file}.tmp" "$ar_file"
        rm -rf "$extract_dir"
    done
}

# Guard: once upstream adopts Zig 0.16+ the repack becomes dead weight.
# Fail loudly so we notice and remove it rather than silently shipping
# a no-op step indefinitely.
check_repack_still_needed() {
    if [ "$(uname)" != "Darwin" ]; then
        return 0
    fi
    local zon_file="${BUILD_DIR}/ghostty/build.zig.zon"
    if [ ! -f "$zon_file" ]; then
        return 0
    fi
    local min_zig
    min_zig=$(grep -E 'minimum_zig_version' "$zon_file" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [ -z "$min_zig" ]; then
        return 0
    fi
    # Compare major.minor only. If minor >= 16 (or major > 0) the
    # archive alignment fix should be available and the repack is no
    # longer needed.
    local major minor
    major=$(echo "$min_zig" | cut -d. -f1)
    minor=$(echo "$min_zig" | cut -d. -f2)
    if [ "$major" -gt 0 ] || [ "$minor" -ge 16 ]; then
        echo "ERROR: upstream ghostty now requires Zig >= ${min_zig}." >&2
        echo "The macOS archive repack step in build.sh should no longer be needed." >&2
        echo "Verify with a build that omits repack_archives_for_macos, then remove" >&2
        echo "the function and this guard." >&2
        exit 1
    fi
}

for cmd in zig cmake ninja git tar; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd not found in PATH" >&2
        exit 1
    fi
done

# Clone (shallow) if not already present
if [ ! -d "${BUILD_DIR}/ghostty" ]; then
    echo "Cloning ghostty at ${GHOSTTY_COMMIT}..."
    mkdir -p "${BUILD_DIR}"
    git clone --depth 1 "${GHOSTTY_REPO}" "${BUILD_DIR}/ghostty"
    cd "${BUILD_DIR}/ghostty"
    git fetch --depth 1 origin "${GHOSTTY_COMMIT}"
    git checkout "${GHOSTTY_COMMIT}"
else
    cd "${BUILD_DIR}/ghostty"
    if [ "$(git rev-parse HEAD)" != "${GHOSTTY_COMMIT}" ]; then
        echo "Fetching ${GHOSTTY_COMMIT}..."
        git fetch --depth 1 origin "${GHOSTTY_COMMIT}"
        git checkout "${GHOSTTY_COMMIT}"
    fi
fi

check_repack_still_needed

# Build via cmake (delegates to zig build internally). Disable
# xcframework emission — it auto-enables on macOS when xcodebuild is
# present, but we don't need it and the install step has been flaky.
#
# Force ZIG_LOCAL_CACHE_DIR to a known project-local path so the SIMD
# dep harvest below finds vendored archives reliably.
cd "${BUILD_DIR}/ghostty"
export ZIG_LOCAL_CACHE_DIR="${BUILD_DIR}/ghostty/.zig-cache"

echo "Configuring..."
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DGHOSTTY_ZIG_BUILD_FLAGS="-Demit-xcframework=false"
echo "Compiling..."
cmake --build build

# Collect outputs
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/lib" "${OUT_DIR}/include"

GHOSTTY_SRC="${BUILD_DIR}/ghostty"

cp "${GHOSTTY_SRC}/zig-out/lib/libghostty-vt.a" "${OUT_DIR}/lib/"

# Vendored deps live in the zig content-addressed cache; find by name
# so we don't hardcode hash paths.
find "${GHOSTTY_SRC}/.zig-cache" -name "libhighway.a" -exec cp {} "${OUT_DIR}/lib/" \;
find "${GHOSTTY_SRC}/.zig-cache" -name "libsimdutf.a" -exec cp {} "${OUT_DIR}/lib/" \;

cp -R "${GHOSTTY_SRC}/zig-out/include/ghostty" "${OUT_DIR}/include/"

repack_archives_for_macos

echo ""
echo "libghostty-vt installed to ${OUT_DIR}/"
ls -la "${OUT_DIR}/lib/"
