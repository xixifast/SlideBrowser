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

BUILD_ARGS=(-c "$CONFIG")
if [[ $UNIVERSAL -eq 1 ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "==> swift build ${BUILD_ARGS[*]}"
swift build "${BUILD_ARGS[@]}"
BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

APP_DIR="$ROOT/build/SlideBrowser.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH/SlideBrowser" "$CONTENTS/MacOS/SlideBrowser"
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
