#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="release"
UNIVERSAL=0
SIGN_IDENTITY="-"
SANDBOX=1

usage() {
    cat <<'EOF'
Usage: build.sh [options]

  --debug              Build the debug configuration (default: release)
  --universal          Build a universal arm64 + x86_64 binary
  --sign <identity>    codesign identity (default: "-" ad-hoc)
  --no-sandbox         Sign without the App Sandbox entitlement (local debugging only)
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG="debug"; shift ;;
        --universal) UNIVERSAL=1; shift ;;
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        --no-sandbox) SANDBOX=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

DEPLOYMENT_TARGET="14.0"   # keep in step with Package.swift platforms: .macOS(.v14)

# Compile one architecture in its own scratch dir and echo its bin path. The build's
# own output is sent to stderr so only the bin path is captured.
build_slice() {   # <arch> <scratch>
    local arch="$1" scratch="$2"
    local target="${arch}-apple-macos${DEPLOYMENT_TARGET}"
    swift build -c "$CONFIG" --scratch-path "$scratch" \
        -Xswiftc -target -Xswiftc "$target" 1>&2
    swift build -c "$CONFIG" --scratch-path "$scratch" \
        -Xswiftc -target -Xswiftc "$target" --show-bin-path
}

APP_DIR="$ROOT/build/SlideBrowser.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

if [[ $UNIVERSAL -eq 1 ]]; then
    # `swift build --arch a --arch b` routes through the Xcode build system, which
    # mis-handles .swiftLanguageMode(.v5) on some Xcode versions. Per-arch native
    # builds + lipo stay on the plain toolchain and work anywhere.
    echo "==> build universal (arm64 + x86_64)"
    ARM_BIN="$(build_slice arm64 "$ROOT/.build/arm64")/SlideBrowser"
    X86_BIN="$(build_slice x86_64 "$ROOT/.build/x86_64")/SlideBrowser"
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$CONTENTS/MacOS/SlideBrowser"
else
    echo "==> build $CONFIG"
    swift build -c "$CONFIG"
    cp "$(swift build -c "$CONFIG" --show-bin-path)/SlideBrowser" "$CONTENTS/MacOS/SlideBrowser"
fi

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
else
    echo "==> warning: Resources/AppIcon.icns missing, bundling without an icon"
fi

ENTITLEMENTS="$ROOT/Resources/SlideBrowser.entitlements"
if [[ $SANDBOX -eq 0 ]]; then
    ENTITLEMENTS="$ROOT/build/SlideBrowser-nosandbox.entitlements"
    /usr/libexec/PlistBuddy -c "Print" "$ROOT/Resources/SlideBrowser.entitlements" > /dev/null
    cp "$ROOT/Resources/SlideBrowser.entitlements" "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Set :com.apple.security.app-sandbox false" "$ENTITLEMENTS"
fi

echo "==> codesign (identity: $SIGN_IDENTITY, sandbox: $SANDBOX)"
codesign --force --options runtime --timestamp=none \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"

echo "==> built $APP_DIR"
