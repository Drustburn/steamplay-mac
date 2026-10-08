#!/bin/bash
# Builds the x86_64 host libraries the Wine runner links or dlopens, into a private prefix.
# Runs natively on arm64 and cross-compiles with -arch x86_64: running the build itself under
# Rosetta would translate clang and every configure probe too, which is several times slower.
#
# Usage: scripts/build-deps.sh [component ...]   (default: all, in order)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CXSRC="$ROOT/sources/sources"
DL="$ROOT/downloads"
WORK="$ROOT/build/deps-work"
PREFIX="$ROOT/build/deps"
JOBS="$(sysctl -n hw.ncpu)"

export MACOSX_DEPLOYMENT_TARGET=14.0
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export CC="clang -arch x86_64" CXX="clang++ -arch x86_64"
export CFLAGS="-O2" CXXFLAGS="-O2"
export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib -Wl,-headerpad_max_install_names"
# Only our own x86_64 prefix; Homebrew's arm64 .pc files must never be picked up.
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH=""

mkdir -p "$WORK" "$PREFIX" "$DL"
log() { printf '\n==== %s\n' "$*"; }

fetch() { # url sha256 file
    local url="$1" sum="$2" out="$DL/$3"
    [ -f "$out" ] || curl -fsSL -o "$out.part" "$url" && { [ -f "$out" ] || mv "$out.part" "$out"; }
    echo "$sum  $out" | shasum -a 256 -c - >/dev/null
}

# Every dylib in the prefix gets an @rpath id and @rpath references to its siblings, so the
# runner can carry them in its lib/ next to each other.
fix_ids() {
    local f dep
    for f in "$PREFIX"/lib/*.dylib; do
        [ -L "$f" ] && continue
        install_name_tool -id "@rpath/${f##*/}" "$f"
        for dep in $(otool -L "$f" | awk 'NR>1{print $1}' | grep "^$PREFIX/lib/" || true); do
            install_name_tool -change "$dep" "@rpath/${dep##*/}" "$f"
        done
        install_name_tool -add_rpath @loader_path "$f" 2>/dev/null || true
        codesign -f -s - "$f" 2>/dev/null
    done
}

fresh() { # copy a pristine source dir into the work area
    # -p keeps mtimes: fresh ones make automake think configure is stale and rerun it
    rm -rf "$WORK/$1"; cp -Rp "$2" "$WORK/$1"; cd "$WORK/$1"
}

build_gmp() {
    log gmp
    fresh gmp "$CXSRC/gnutls/gmp"
    ./configure --prefix="$PREFIX" --host=x86_64-apple-darwin --build=aarch64-apple-darwin --enable-shared --disable-static \
        --disable-assembly
    make -j"$JOBS" && make install && fix_ids
}

build_nettle() {
    log nettle
    # The CrossOver drop of nettle lacks its Makefile.in files; use the release it is cut from.
    fetch https://ftpmirror.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz \
        fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5 nettle-3.10.2.tar.gz
    rm -rf "$WORK/nettle" && mkdir -p "$WORK/nettle" && tar -xzf "$DL/nettle-3.10.2.tar.gz" -C "$WORK/nettle" --strip-components=1
    cd "$WORK/nettle"
    ./configure --prefix="$PREFIX" --host=x86_64-apple-darwin --build=aarch64-apple-darwin --enable-shared --disable-static \
        --disable-documentation --disable-openssl --disable-assembler \
        --libdir="$PREFIX/lib"
    make -j"$JOBS" && make install && fix_ids
}

build_gnutls() {
    log gnutls
    fresh gnutls "$CXSRC/gnutls/gnutls"
    ./configure --prefix="$PREFIX" --host=x86_64-apple-darwin --build=aarch64-apple-darwin --enable-shared --disable-static \
        --with-included-libtasn1 --with-included-unistring --without-p11-kit --without-idn \
        --without-brotli --without-zstd --without-tpm --without-tpm2 --disable-doc \
        --disable-tests --disable-tools --disable-cxx --disable-nls --disable-guile \
        --disable-libdane --disable-full-test-suite --disable-gost \
        GMP_LIBS=-lgmp NETTLE_LIBS=-lnettle HOGWEED_LIBS=-lhogweed
    # (single words on purpose: CrossOver's m4/hooks.m4 tests x$NETTLE_LIBS unquoted, and a
    #  value with a space silently turns the nettle backend off; -L is in LDFLAGS already)
    make -j"$JOBS" && make install && fix_ids
}

build_freetype() {
    log freetype
    fresh freetype "$CXSRC/freetype"
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
        -DBUILD_SHARED_LIBS=ON -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_PNG=ON \
        -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON -DFT_REQUIRE_ZLIB=ON
    cmake --build build && cmake --install build && fix_ids
}

build_sdl2() {
    log SDL2
    fetch https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10.tar.gz \
        5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165 SDL2-2.32.10.tar.gz
    rm -rf "$WORK/SDL2" && mkdir -p "$WORK/SDL2" && tar -xzf "$DL/SDL2-2.32.10.tar.gz" -C "$WORK/SDL2" --strip-components=1
    cd "$WORK/SDL2"
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
        -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF
    cmake --build build && cmake --install build && fix_ids
}

build_moltenvk() {
    log MoltenVK
    fetch https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-macos.tar \
        f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e MoltenVK-1.4.2-macos.tar
    rm -rf "$WORK/moltenvk" && mkdir -p "$WORK/moltenvk" && tar -xf "$DL/MoltenVK-1.4.2-macos.tar" -C "$WORK/moltenvk"
    local dylib; dylib="$(find "$WORK/moltenvk" -path '*dynamic/dylib/macOS/libMoltenVK.dylib' | head -1)"
    [ -n "$dylib" ] || dylib="$(find "$WORK/moltenvk" -name libMoltenVK.dylib | head -1)"
    lipo "$dylib" -verify_arch x86_64
    install -m 0755 "$dylib" "$PREFIX/lib/libMoltenVK.dylib"
    install_name_tool -id @rpath/libMoltenVK.dylib "$PREFIX/lib/libMoltenVK.dylib"
    codesign -f -s - "$PREFIX/lib/libMoltenVK.dylib"
}

build_ffmpeg() {
    log FFmpeg
    # libavcodec/libavformat/libavutil for winedmo (Media Foundation video and audio decoding)
    fetch https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz \
        de668509caf9e35e3cd162473441fdb29538c6d96ed080292b3cf9e6fc5d558f ffmpeg-7.1.5.tar.xz
    rm -rf "$WORK/ffmpeg" && mkdir -p "$WORK/ffmpeg" && tar -xJf "$DL/ffmpeg-7.1.5.tar.xz" -C "$WORK/ffmpeg" --strip-components=1
    cd "$WORK/ffmpeg"
    ./configure --prefix="$PREFIX" --enable-cross-compile --arch=x86_64 --target-os=darwin \
        --cc="clang -arch x86_64" --cxx="clang++ -arch x86_64" --x86asmexe=/opt/homebrew/bin/nasm \
        --extra-cflags="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
        --extra-ldflags="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
        --enable-shared --disable-static --enable-pic --disable-programs --disable-doc \
        --disable-avdevice --disable-avfilter --disable-network --disable-debug \
        --disable-autodetect --enable-videotoolbox --enable-audiotoolbox \
        --install-name-dir=@rpath
    make -j"$JOBS" && make install && fix_ids
}

ALL=(gmp nettle gnutls freetype sdl2 moltenvk ffmpeg)
for c in "${@:-${ALL[@]}}"; do "build_$c"; done
log "done: $PREFIX"
find "$PREFIX/lib" -maxdepth 1 -name '*.dylib' -type f -exec sh -c 'printf "%s  %s\n" "$(lipo -archs "$1")" "$(basename "$1")"' _ {} \;
