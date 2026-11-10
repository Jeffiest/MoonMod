#!/usr/bin/env bash
# Installs what an Ubuntu 24.04 host needs to build and test the Chronicle Two PC port without the
# Kazarov container: clang 22, Rust 1.99, SDL3, the Vulkan 1.4 headers and loader, Mesa's software
# Vulkan driver, and Kazarov's FFmpeg. Run as root, once per machine. It is safe to run again.
#
#   sudo ports/chronicle-two/setup-linux.sh <ChronicleTwo checkout>
#
# Everything built from source goes under $CT_PREFIX (default /opt/chronicletwo). The script ends by
# writing $CT_PREFIX/env.sh; source it, then configure with the pinned dependency sources:
#
#   . /opt/chronicletwo/env.sh
#   cmake --preset linux-x64 -C tools/ci/dependencies.cmake
#   cmake --build port/build/pc
#   ctest --test-dir port/build/pc -R MoonMod
set -euo pipefail

game=${1:?usage: setup-linux.sh <ChronicleTwo checkout>}
game=$(cd "$game" && pwd)
prefix=${CT_PREFIX:-/opt/chronicletwo}
llvm=22
rust=1.99.0
sdl=release-3.4.18
vulkan=vulkan-sdk-1.4.363.0
cxxbridge=1.0.205
jobs=$(nproc)
src=$prefix/src

[ -f "$game/tools/kazarov/tools/ffmpeg/kz-ffmpeg" ] || {
    echo "$game has no tools/kazarov; run git submodule update --init --recursive there first." >&2
    exit 1
}
mkdir -p "$src"
export DEBIAN_FRONTEND=noninteractive

if ! command -v "clang++-$llvm" >/dev/null; then
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates wget gnupg
    wget --tries=5 --retry-connrefused -qO /etc/apt/trusted.gpg.d/apt.llvm.org.asc https://apt.llvm.org/llvm-snapshot.gpg.key
    echo "deb https://apt.llvm.org/noble/ llvm-toolchain-noble-$llvm main" > /etc/apt/sources.list.d/llvm-$llvm.list
fi
apt-get update
# The port's C++26 code needs a newer standard library than Ubuntu 24.04's libstdc++ 14, so it builds
# against LLVM's libc++ (env.sh sets -stdlib=libc++).
apt-get install -y --no-install-recommends \
    build-essential "clang-$llvm" "lld-$llvm" "llvm-$llvm" "libclang-rt-$llvm-dev" \
    "libc++-$llvm-dev" "libc++abi-$llvm-dev" "libunwind-$llvm-dev" \
    cmake ninja-build ccache nasm git pkg-config python3 glslang-tools \
    mesa-vulkan-drivers vulkan-validationlayers \
    libxkbcommon-dev libwayland-dev libx11-dev libxext-dev libxcursor-dev libxi-dev libxrandr-dev \
    libxfixes-dev libxss-dev libxtst-dev libegl1-mesa-dev libasound2-dev libpulse-dev libdecor-0-dev

export PATH=/usr/lib/llvm-$llvm/bin:$PATH

fetch() { # fetch <url> <tag> <dir>: a shallow checkout of one tag
    if [ ! -d "$3/.git" ]; then
        git clone --quiet --depth 1 --branch "$2" "$1" "$3"
    fi
}

if [ ! -f "$prefix/include/vulkan/vulkan_core.h" ]; then
    fetch https://github.com/KhronosGroup/Vulkan-Headers "$vulkan" "$src/Vulkan-Headers"
    cmake -S "$src/Vulkan-Headers" -B "$src/Vulkan-Headers/build" -G Ninja -DCMAKE_INSTALL_PREFIX="$prefix"
    cmake --install "$src/Vulkan-Headers/build"
fi
if [ ! -f "$prefix/lib/libvulkan.so" ]; then
    fetch https://github.com/KhronosGroup/Vulkan-Loader "$vulkan" "$src/Vulkan-Loader"
    cmake -S "$src/Vulkan-Loader" -B "$src/Vulkan-Loader/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH="$prefix" \
        -DBUILD_WSI_XCB_SUPPORT=OFF -DBUILD_TESTS=OFF \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
    cmake --build "$src/Vulkan-Loader/build" --parallel "$jobs"
    cmake --install "$src/Vulkan-Loader/build"
fi
if [ ! -f "$prefix/lib/cmake/SDL3/SDL3Config.cmake" ]; then
    fetch https://github.com/libsdl-org/SDL "$sdl" "$src/SDL"
    cmake -S "$src/SDL" -B "$src/SDL/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
        -DCMAKE_C_COMPILER=clang
    cmake --build "$src/SDL/build" --parallel "$jobs"
    cmake --install "$src/SDL/build"
fi
if [ ! -f "$prefix/ffmpeg/include/libavcodec/avcodec.h" ]; then
    python3 "$game/tools/kazarov/tools/ffmpeg/kz-ffmpeg" --out "$prefix/ffmpeg" --jobs "$jobs"
fi

# The CMake dependencies (Tracy, Luau, GoogleTest and so on) are pinned in the build files as archive
# downloads. Fetch the same tags and commits with git instead, which also works where only git reaches
# GitHub, into the layout tools/ci/dependencies.cmake reads ($CT_DEPS_ROOT/sources and /vendor).
python3 - "$game" "$prefix/deps" <<'PY'
import pathlib, re, shutil, subprocess, sys
game, deps = map(pathlib.Path, sys.argv[1:])
def checkout(repo, ref, destination):
    if (destination / '.git').is_dir():
        if (destination / '.ref').is_file() and (destination / '.ref').read_text() == ref:
            return
        shutil.rmtree(destination)
    destination.mkdir(parents=True, exist_ok=True)
    git = ['git', '-C', str(destination)]
    subprocess.run(git + ['init', '--quiet'], check=True)
    subprocess.run(git + ['fetch', '--quiet', '--depth', '1', f'https://github.com/{repo}', ref], check=True)
    subprocess.run(git + ['checkout', '--quiet', '--detach', 'FETCH_HEAD'], check=True)
    (destination / '.ref').write_text(ref)
patterns = [r'https://codeload\.github\.com/([^/]+/[^/]+)/tar\.gz/(?:refs/tags/)?(\S+)',
            r'https://github\.com/([^/]+/[^/]+)/archive/(?:refs/tags/)?(\S+?)\.(?:tar\.gz|zip)',
            r'https://github\.com/([^/]+/[^/]+)/releases/download/([^/]+)/\S+']
files = [game / 'port/CMakeLists.txt', game / 'port/src/tests/CMakeLists.txt',
         *(game / 'port/cmake').glob('*.cmake'), *(game / 'tools/kazarov/cmake').glob('*.cmake')]
for file in files:
    text = file.read_text()
    for name, body in re.findall(r'FetchContent_Declare\((\w+)\s+(.*?)\)', text, re.S | re.I):
        url = re.search(r'\bURL\s+(https://\S+)', body)
        if not url or name.lower() == 'kz_vulkan_runtime':
            continue
        for pattern in patterns:
            if found := re.fullmatch(pattern, url[1]):
                checkout(found[1], found[2], deps / 'sources' / name.lower())
                break
        else:
            sys.exit(f'{file}: {name}: no git source known for {url[1]}')
    vendor = r'_kz_port_vendor\(\w+\s+(\S+)\s+https://raw\.githubusercontent\.com/([^/]+/[^/]+)/([0-9a-f]{40})/(\S+)\s'
    for name, repo, commit, path in re.findall(vendor, text):
        source = deps / 'vendor-src' / repo.replace('/', '-')
        checkout(repo, commit, source)
        (deps / 'vendor').mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / path, deps / 'vendor' / name)
PY

# An existing rustup keeps its own home; otherwise Rust is installed under the prefix.
if command -v rustup >/dev/null; then
    export RUSTUP_HOME=${RUSTUP_HOME:-$HOME/.rustup} CARGO_HOME=${CARGO_HOME:-$HOME/.cargo}
else
    export RUSTUP_HOME=${RUSTUP_HOME:-$prefix/rustup} CARGO_HOME=${CARGO_HOME:-$prefix/cargo}
    if [ ! -x "$CARGO_HOME/bin/rustup" ]; then
        wget --tries=5 --retry-connrefused -qO "$src/rustup-init.sh" https://sh.rustup.rs
        sh "$src/rustup-init.sh" -y --no-modify-path --profile minimal --default-toolchain none
    fi
fi
export PATH=$CARGO_HOME/bin:$PATH
rustup toolchain install "$rust" --profile minimal
[ -x "$CARGO_HOME/bin/cxxbridge" ] && "$CARGO_HOME/bin/cxxbridge" --version | grep -q "$cxxbridge" ||
    cargo "+$rust" install --locked cxxbridge-cmd --version "$cxxbridge"

cat > "$prefix/env.sh" <<EOF
# Source this before building or testing the Chronicle Two PC port. Written by setup-linux.sh.
export RUSTUP_HOME=$RUSTUP_HOME CARGO_HOME=$CARGO_HOME RUSTUP_TOOLCHAIN=$rust
export PATH=$CARGO_HOME/bin:/usr/lib/llvm-$llvm/bin:\$PATH
export CMAKE_PREFIX_PATH=$prefix\${CMAKE_PREFIX_PATH:+:\$CMAKE_PREFIX_PATH}
export KZ_FFMPEG_DIR=$prefix/ffmpeg CT_DEPS_ROOT=$prefix/deps
export CXXFLAGS="-stdlib=libc++\${CXXFLAGS:+ \$CXXFLAGS}" LDFLAGS="-stdlib=libc++\${LDFLAGS:+ \$LDFLAGS}"
export LD_LIBRARY_PATH=$prefix/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
# No GPU is needed: the tests render with Mesa's software driver.
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json
export SDL_VIDEODRIVER=\${SDL_VIDEODRIVER:-offscreen} SDL_AUDIODRIVER=\${SDL_AUDIODRIVER:-dummy}
EOF
echo "Done. Next: source $prefix/env.sh"
