#!/bin/bash
#
# ci/build_ipa_macos.sh — 用 Xcode 自带的 clang 编译本工程，产出未签名 IPA。
#
# 与 build_ipa_linux.sh 做同一件事（同样的源文件清单、同样的框架/库），只是
# 把 Linux 上的 theos 交叉工具链换成 xcrun 的 iPhoneOS SDK。这样 GitHub 的
# macos runner 不需要装 theos 就能构建。
#
#   ./ci/build_ipa_macos.sh            -> dist/App.ipa
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
EXTRAS="$ROOT/extras"
BUILD="$ROOT/build"
APPDIR="$BUILD/Payload/AppDump.app"
DIST="$ROOT/dist"
IPA="$DIST/App.ipa"
ARCH="${ARCH:-arm64}"
MIN_IOS="${MIN_IOS:-15.0}"

echo "==> clean"
rm -rf "$BUILD" "$IPA"
mkdir -p "$APPDIR/Frameworks" "$DIST"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos -f clang)"

# ── 源文件（与 src/Makefile 的 blade_FILES 一致） ───────────────────────────
SRCS=()
while IFS= read -r f; do [ -n "$f" ] && SRCS+=("$SRC/$f"); done <<'LIST'
main.m
FileManager.m
Exploit.m
ProcessListViewController.m
kexploit/darksword.m
kexploit/offsets.m
kexploit/utils.m
kexploit/persistence.m
kexploit/decrypt.m
kexploit/cyvm.m
kexploit/cydecrypt.m
kexploit/cyremote.m
kexploit/kcblock.m
kexploit/TaskRop/RemoteCall.m
kexploit/TaskRop/thread.m
kexploit/TaskRop/vm.m
kexploit/TaskRop/pac.m
kexploit/TaskRop/exc.m
kexploit/TaskRop/findcachedataoff.m
kexploit/pe/sbx.m
kexploit/pe/vnode.m
kexploit/pe/vfs.m
kexploit/pe/apfs.m
LIST

# src/app/*.m（SKDiag.m 原构建脚本就排除）
while IFS= read -r f; do SRCS+=("$f"); done < <(find "$SRC/app" -name '*.m' ! -name 'SKDiag.m' | sort)

# ── 附加模块（本次新增，第三方源码原样不动） ───────────────────────────────
if [ -d "$EXTRAS" ]; then
  while IFS= read -r f; do SRCS+=("$f"); done < <(find "$EXTRAS" -name '*.m' -o -name '*.c' | sort)
fi

INCLUDES=(
  -I"$SRC"
  -I"$SRC/compat"
  -I"$SRC/kexploit"
  -I"$SRC/kexploit/cy"
  -I"$SRC/kexploit/pe"
  -I"$SRC/kexploit/TaskRop"
  -I"$SRC/kexploit/headers"
  -I"$SRC/kexploit/xpc"
  -I"$SRC/app"
)
[ -d "$EXTRAS" ] && INCLUDES+=(-I"$EXTRAS")

CFLAGS=(
  -target "${ARCH}-apple-ios${MIN_IOS}"
  -isysroot "$SDK"
  -miphoneos-version-min="$MIN_IOS"
  -fobjc-arc
  -fmodules
  -fobjc-legacy-dispatch
  -Wno-everything
)

FRAMEWORKS=(
  -framework UIKit -framework Foundation -framework CoreGraphics
  -framework QuartzCore -framework AVFoundation -framework AVKit -framework WebKit
  -framework CoreFoundation -framework Security -framework IOSurface
  -framework ImageIO -framework MobileCoreServices
)

LIBS=( -L"$SRC/kexploit/lib" -lgrabkernel2 -lxpf -lz )

echo "==> compile (${#SRCS[@]} files, $ARCH, iOS $MIN_IOS)"
OBJDIR="$BUILD/obj"; mkdir -p "$OBJDIR"
OBJS=()
i=0
for s in "${SRCS[@]}"; do
  i=$((i+1))
  rel="${s#$ROOT/}"
  o="$OBJDIR/$(printf '%03d' "$i")_$(echo "$rel" | tr '/ ' '__' | sed 's/\.\(m\|c\)$/.o/')"
  printf '    [%d/%d] %s\n' "$i" "${#SRCS[@]}" "$rel"
  "$CLANG" "${CFLAGS[@]}" "${INCLUDES[@]}" -c "$s" -o "$o"
  OBJS+=("$o")
done

echo "==> link"
"$CLANG" "${CFLAGS[@]}" \
  -o "$APPDIR/appdump" "${OBJS[@]}" \
  "${FRAMEWORKS[@]}" "${LIBS[@]}" \
  -Wl,-rpath,@executable_path/Frameworks

echo "==> assemble bundle"
cp "$SRC/Info.plist" "$APPDIR/Info.plist"
cp "$SRC/LaunchScreen.storyboard" "$APPDIR/LaunchScreen.storyboard"
printf 'APPL????' > "$APPDIR/PkgInfo"
for d in "$SRC"/locales/*.lproj; do cp -R "$d" "$APPDIR/"; done
# 图标：Info.plist 里引用了 AppIcon60x60 / Icon-20 / Icon-29 / Icon-40
cp "$SRC"/icons/*.png "$APPDIR/" 2>/dev/null || true
cp "$SRC/kexploit/lib/libgrabkernel2.dylib" "$APPDIR/Frameworks/"
cp "$SRC/kexploit/lib/libxpf.dylib"         "$APPDIR/Frameworks/"
chmod +x "$APPDIR/appdump" "$APPDIR/Frameworks/"*.dylib

echo "==> ad-hoc sign (entitlements embedded)"
if [ -f "$SRC/appdump.entitlements" ]; then
  codesign --force --sign - --entitlements "$SRC/appdump.entitlements" --timestamp=none "$APPDIR/appdump" || true
else
  codesign --force --sign - "$APPDIR/appdump" || true
fi
for dylib in "$APPDIR/Frameworks/"*.dylib; do
  codesign --force --sign - --timestamp=none "$dylib" || true
done

echo "==> package"
(cd "$BUILD" && zip -qry "$IPA" Payload)
echo "[*] done -> $IPA"
ls -l "$IPA"