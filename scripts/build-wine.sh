#!/bin/bash
# Configures and builds the patched CrossOver-26.3 Wine tree (src/wine) for an x86_64 host
# (it runs under Rosetta), with new WoW64 (i386 PE on the 64-bit host), and installs it into
# build/wine-install. The build itself runs natively and cross-compiles with -arch x86_64.
#
# Usage: scripts/build-wine.sh [--reconfigure]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src/wine"
DEPS="$ROOT/build/deps"
BUILD="$ROOT/build/wine-x86_64"
TOOLS="$ROOT/build/wine-tools"
INSTALL="$ROOT/build/wine-install"
JOBS="$(sysctl -n hw.ncpu)"

export MACOSX_DEPLOYMENT_TARGET=14.0
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
export PKG_CONFIG_PATH=""
export CCACHE_DIR="$ROOT/build/ccache"

# Wine 11.0 needs native build tools (winebuild, winegcc, widl, wrc, makedep...) to cross
# compile; build them from the same tree for the arm64 build machine first.
if [ ! -x "$TOOLS/tools/winebuild/winebuild" ] || ! grep -q '#define SONAME_LIBFREETYPE' "$TOOLS/include/config.h"; then
    mkdir -p "$TOOLS"
    # An aarch64 build machine must have a PE compiler even for a tools-only tree; LLVM's
    # clang + lld (Homebrew llvm, lld) serve as that.
    # sfnt2fon (the bitmap fonts) needs FreeType at build time: the native arm64 Homebrew one.
    (cd "$TOOLS" && PATH="/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:$PATH" \
        "$SRC/configure" --enable-archs=aarch64 --with-mingw=clang --disable-tests \
        --without-x --with-freetype --without-gnutls --without-sdl --without-vulkan \
        --without-gstreamer --without-ffmpeg --without-coreaudio --without-opencl \
        CC="/usr/bin/clang" CXX="/usr/bin/clang++" CFLAGS="-O2 -g0" \
        FREETYPE_CFLAGS="-I/opt/homebrew/opt/freetype/include/freetype2" \
        FREETYPE_LIBS="-L/opt/homebrew/opt/freetype/lib -lfreetype")
    make -C "$TOOLS" -j"$JOBS" __tooldeps__
fi
# wrc looks for locale.nls and the codepage tables next to its own build tree, but an
# out-of-tree tools build only has them in the source tree.
for f in "$SRC"/nls/*.nls; do ln -sf "$f" "$TOOLS/nls/${f##*/}"; done

mkdir -p "$BUILD"
cd "$BUILD"

if [ ! -f Makefile ] || [ "${1:-}" = "--reconfigure" ]; then
    # The unix .so files and the loader live in lib/wine/x86_64-unix; @loader_path/../.. is the
    # runner's lib/, where the bundled dylibs go. configure records leaf sonames only, and dyld
    # resolves a leaf-name dlopen through the caller's rpaths.
    "$SRC/configure" \
        --prefix="$INSTALL" \
        --host=x86_64-apple-darwin --build=aarch64-apple-darwin --with-wine-tools="$TOOLS" \
        --enable-archs=i386,x86_64 \
        --with-mingw \
        --disable-tests \
        --without-alsa --without-capi --with-coreaudio --without-cups --without-dbus \
        --without-fontconfig --with-freetype --with-gnutls --without-gphoto --without-gstreamer \
        --without-krb5 --without-netapi --without-oss --without-pulse --without-sane --with-sdl \
        --without-udev --without-usb --without-v4l2 --with-vulkan --without-x --without-wayland \
        --with-ffmpeg --without-inotify --without-pcap \
        CC="ccache clang -arch x86_64" CXX="ccache clang++ -arch x86_64" \
        OBJC="ccache clang -arch x86_64" \
        i386_CC="ccache i686-w64-mingw32-gcc" x86_64_CC="ccache x86_64-w64-mingw32-gcc" \
        CFLAGS="-O2 -g0" CROSSCFLAGS="-O2 -g0" \
        CPPFLAGS="-I$DEPS/include" \
        LDFLAGS="-L$DEPS/lib -Wl,-rpath,@loader_path/../.. -Wl,-headerpad_max_install_names" \
        ac_cv_lib_soname_MoltenVK=libMoltenVK.dylib \
        PKG_CONFIG=/opt/homebrew/bin/pkg-config \
        FREETYPE_CFLAGS="-I$DEPS/include/freetype2" FREETYPE_LIBS="-L$DEPS/lib -lfreetype" \
        SDL2_CFLAGS="-I$DEPS/include/SDL2 -D_THREAD_SAFE" SDL2_LIBS="-L$DEPS/lib -lSDL2" \
        GNUTLS_CFLAGS="-I$DEPS/include" GNUTLS_LIBS="-L$DEPS/lib -lgnutls" \
        FFMPEG_CFLAGS="-I$DEPS/include" FFMPEG_LIBS="-L$DEPS/lib -lavformat -lavcodec -lavutil"
fi

# configure turns optional features off silently; fail early if one we rely on is missing.
for need in SONAME_LIBFREETYPE SONAME_LIBGNUTLS SONAME_LIBSDL2 SONAME_LIBVULKAN; do
    grep -q "#define $need " include/config.h || { echo "missing $need in config.h" >&2; exit 1; }
done
grep -q '#define HAVE_FFMPEG 1' include/config.h || { echo "FFmpeg not enabled" >&2; exit 1; }
grep -E '#define SONAME_LIB(FREETYPE|GNUTLS|SDL2|VULKAN) ' include/config.h

# The generated Makefile does not depend on the module Makefile.in files; regenerate it so a
# change there (dlls/lsteamclient is laid in by fetch-steam-sources.sh) is picked up.
./config.status >/dev/null
make -j"$JOBS"
rm -rf "$INSTALL"
make install-lib
# install-lib installs the loader only as lib/wine/x86_64-unix/wine (what NotProton's run
# script calls); give bin/ the usual name too.
ln -sf ../lib/wine/x86_64-unix/wine "$INSTALL/bin/wine"
"$INSTALL/bin/wine" --version || true
