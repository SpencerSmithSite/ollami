#!/bin/bash
# Ollami desktop build & run script.
# Builds the Swift app, installs it to /Applications/, and opens it.
# The Python backend is started separately via: bash scripts/start.sh
#
# Usage:
#   ./run.sh                         # build as "Ollami Dev" (default)
#   OMI_APP_NAME="Ollami" ./run.sh   # build as "Ollami" → /Applications/Ollami.app
set -e

# ── Timing utilities ──────────────────────────────────────────────────────────
SCRIPT_START_TIME=$(date +%s.%N)
STEP_START_TIME=$SCRIPT_START_TIME

step() {
    local now; now=$(date +%s.%N)
    local step_elapsed; step_elapsed=$(echo "$now - $STEP_START_TIME" | bc)
    local total_elapsed; total_elapsed=$(echo "$now - $SCRIPT_START_TIME" | bc)
    if [ "$STEP_START_TIME" != "$SCRIPT_START_TIME" ]; then
        printf "  └─ done (%.2fs)\n" "$step_elapsed"
    fi
    STEP_START_TIME=$now
    printf "[%6.1fs] %s\n" "$total_elapsed" "$1"
}

substep() {
    local now; now=$(date +%s.%N)
    local total_elapsed; total_elapsed=$(echo "$now - $SCRIPT_START_TIME" | bc)
    printf "[%6.1fs]   ├─ %s\n" "$total_elapsed" "$1"
}

# ── App naming ────────────────────────────────────────────────────────────────
BINARY_NAME="Omi Computer"
APP_NAME="${OMI_APP_NAME:-Ollami Dev}"

slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }

APP_SLUG="$(slugify "$APP_NAME")"
BUNDLE_ID="${OMI_BUNDLE_ID:-com.omi.$APP_SLUG}"
URL_SCHEME="omi-$APP_SLUG"

BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_PATH="/Applications/$APP_NAME.app"

echo ""
echo "  ┌─────────────────────────────────────┐"
echo "  │  Ollami — build & run               │"
echo "  │  App:      $APP_NAME"
echo "  │  Bundle:   $BUNDLE_ID"
echo "  └─────────────────────────────────────┘"
echo ""

# ── Kill existing instance ────────────────────────────────────────────────────
step "Stopping any running instance..."
pkill -f "$APP_NAME.app" 2>/dev/null || true
sleep 0.3

# ── Build ─────────────────────────────────────────────────────────────────────
step "Building Swift app..."
# xcrun is required to match the correct SDK version
xcrun swift build -c debug --package-path Desktop

# ── Assemble app bundle ───────────────────────────────────────────────────────
step "Creating app bundle..."

substep "Directories"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

substep "Binary"
cp -f "Desktop/.build/debug/$BINARY_NAME" "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME" 2>/dev/null || true

# Sparkle (auto-update framework — optional)
SPARKLE_FRAMEWORK="Desktop/.build/arm64-apple-macosx/debug/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    substep "Sparkle framework"
    rm -rf "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
fi

substep "Info.plist"
cp -f Desktop/Info.plist "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $BINARY_NAME"      "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID"         "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME"                "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME"         "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 $URL_SCHEME" \
    "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true

# Resource bundle (app assets: images, etc.)
RESOURCE_BUNDLE="Desktop/.build/arm64-apple-macosx/debug/Omi Computer_Omi Computer.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    substep "Resource bundle"
    cp -Rf "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

substep ".env — pointing app to local backend"
printf 'OMI_API_URL=http://localhost:8080\n' > "$APP_BUNDLE/Contents/Resources/.env"

substep "App icon"
cp -f omi_icon.icns "$APP_BUNDLE/Contents/Resources/OmiIcon.icns" 2>/dev/null || true

substep "PkgInfo"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# ── Sign ──────────────────────────────────────────────────────────────────────
step "Signing..."

xattr -cr "$APP_BUNDLE"

SIGN_IDENTITY="${OMI_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning \
        | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
fi

if [ -n "$SIGN_IDENTITY" ]; then
    substep "Identity: $SIGN_IDENTITY"

    if [ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]; then
        codesign --force --options runtime --sign "$SIGN_IDENTITY" \
            "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    fi

    # Named bundles have no provisioning profile — strip Apple Sign-In entitlement
    # to avoid launchd spawn errors (RBSRequestErrorDomain Code=5).
    EFFECTIVE_ENTITLEMENTS="Desktop/Omi.entitlements"
    if [ -f "$EFFECTIVE_ENTITLEMENTS" ]; then
        cp "$EFFECTIVE_ENTITLEMENTS" /tmp/ollami-local.entitlements
        /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.applesignin" \
            /tmp/ollami-local.entitlements 2>/dev/null || true
        EFFECTIVE_ENTITLEMENTS="/tmp/ollami-local.entitlements"
    fi

    codesign --force --options runtime \
        ${EFFECTIVE_ENTITLEMENTS:+--entitlements "$EFFECTIVE_ENTITLEMENTS"} \
        --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
    substep "No signing identity found — signing ad-hoc (permissions may reset)"
    codesign --force --sign - "$APP_BUNDLE"
fi

xattr -cr "$APP_BUNDLE"

# ── Install & launch ──────────────────────────────────────────────────────────
step "Installing to /Applications/..."
ditto "$APP_BUNDLE" "$APP_PATH"
substep "Installed: $APP_PATH"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$APP_BUNDLE" 2>/dev/null || true
"$LSREGISTER" -u "$APP_PATH"  2>/dev/null || true
"$LSREGISTER" -f "$APP_PATH"  2>/dev/null || true

step "Launching $APP_NAME..."
open "$APP_PATH"

NOW=$(date +%s.%N)
TOTAL=$(echo "$NOW - $SCRIPT_START_TIME" | bc)
printf "  └─ done (%.2fs)\n" "$(echo "$NOW - $STEP_START_TIME" | bc)"
echo ""
echo "  App launched in ${TOTAL%.*}s → $APP_PATH"
echo "  Start the backend separately:  bash scripts/start.sh"
echo ""
