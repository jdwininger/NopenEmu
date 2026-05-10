#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build, sign, and notarize a renamed OpenEmu app bundle (NopenEmu.app), and
package it as a notarized DMG.

Usage:
  build-sign-notarize-nopenemu.sh [options]

Options:
  --workspace PATH         Xcode workspace path.
                           Default: OpenEmu.xcworkspace
  --scheme NAME            Xcode scheme.
                           Default: OpenEmu + Cores (Experimental, Alpha)
  --configuration NAME     Xcode configuration.
                           Default: Release
  --arch ARCH              Build architecture.
                           Default: x86_64
  --output-dir PATH        Directory for final artifacts.
                           Default: dist/nopenemu
  --app-name NAME          Final app bundle name (without .app).
                           Default: NopenEmu
  --identity NAME          Developer ID Application cert common name.
                           Default: Developer ID Application: Jeremy Wininger (M6TW42W523)
  --notary-profile NAME    Keychain profile for xcrun notarytool.
                           Default: OPENEMU_NOTARY
  --team-id TEAMID         Team identifier for metadata output (optional).
  --skip-dmg              Skip DMG creation.
  --skip-notarize          Build and sign only.
  --skip-sign              Build only.
  --help                   Show this message.

Defaults:
  --identity       Defaults to your configured Developer ID identity.
  --notary-profile Defaults to your configured notarytool keychain profile.

Notes:
  1) This script renames the built product to NopenEmu.app and updates
     CFBundleName / CFBundleDisplayName in the copied bundle.
  2) It signs the renamed app with hardened runtime and timestamp.
  3) It creates NopenEmu.dmg from the signed app.
  4) It submits the DMG to Apple notarization, waits for completion, then staples.
EOF
}

WORKSPACE="OpenEmu.xcworkspace"
SCHEME="OpenEmu + Cores (Experimental, Alpha)"
CONFIGURATION="Release"
ARCH="x86_64"
OUTPUT_DIR="dist/nopenemu"
APP_NAME="NopenEmu"
IDENTITY="Developer ID Application: Jeremy Wininger (M6TW42W523)"
NOTARY_PROFILE="OPENEMU_NOTARY"
TEAM_ID=""
SKIP_NOTARIZE=0
SKIP_SIGN=0
SKIP_DMG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      WORKSPACE="$2"
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --arch)
      ARCH="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --app-name)
      APP_NAME="$2"
      shift 2
      ;;
    --identity)
      IDENTITY="$2"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --team-id)
      TEAM_ID="$2"
      shift 2
      ;;
    --skip-dmg)
      SKIP_DMG=1
      shift
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    --skip-sign)
      SKIP_SIGN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$SKIP_SIGN" -eq 0 && -z "$IDENTITY" ]]; then
  echo "Missing --identity (or use --skip-sign)." >&2
  exit 1
fi

if [[ "$SKIP_NOTARIZE" -eq 0 && "$SKIP_SIGN" -eq 1 ]]; then
  echo "Notarization requires signing. Remove --skip-sign or add --skip-notarize." >&2
  exit 1
fi

if [[ "$SKIP_NOTARIZE" -eq 0 && -z "$NOTARY_PROFILE" ]]; then
  echo "Missing --notary-profile (or use --skip-notarize)." >&2
  exit 1
fi

if [[ "$SKIP_SIGN" -eq 0 ]]; then
  CODESIGN_RUNTIME_ARGS=(--force --options runtime --timestamp --sign "$IDENTITY")
  CODESIGN_DMG_ARGS=(--force --timestamp --sign "$IDENTITY")
fi

command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild not found" >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "xcrun not found" >&2; exit 1; }
command -v /usr/libexec/PlistBuddy >/dev/null 2>&1 || { echo "PlistBuddy not found" >&2; exit 1; }

if [[ "$SKIP_SIGN" -eq 0 ]]; then
  command -v codesign >/dev/null 2>&1 || { echo "codesign not found" >&2; exit 1; }
fi

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
    echo "notarytool keychain profile '$NOTARY_PROFILE' not found or invalid." >&2
    echo "Create one with: xcrun notarytool store-credentials ..." >&2
    exit 1
  }
fi

mkdir -p "$OUTPUT_DIR"

BUILD_LOG="$OUTPUT_DIR/build.log"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
SOURCE_APP="$PRODUCTS_DIR/OpenEmu.app"
RENAMED_APP="$OUTPUT_DIR/${APP_NAME}.app"
DMG_PATH="$OUTPUT_DIR/${APP_NAME}.dmg"
DMG_STAGING_DIR="$OUTPUT_DIR/dmg-staging"

rm -rf "$DERIVED_DATA" "$RENAMED_APP" "$DMG_PATH" "$DMG_STAGING_DIR"

echo "==> Building workspace (this can take a while for large C++ files)"
set -o pipefail

# Emit a heartbeat so long compile steps do not look stalled.
(
  while true; do
    sleep 30
    if [[ -f "$BUILD_LOG" ]]; then
      echo "==> [$(date '+%H:%M:%S')] Build still running..."
      tail -n 1 "$BUILD_LOG" || true
    else
      echo "==> [$(date '+%H:%M:%S')] Build still running..."
    fi
  done
) &
HEARTBEAT_PID=$!

set +e
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -arch "$ARCH" \
  -derivedDataPath "$DERIVED_DATA" \
  build | tee "$BUILD_LOG"
XCODEBUILD_STATUS=${PIPESTATUS[0]}
set -e

kill "$HEARTBEAT_PID" 2>/dev/null || true
wait "$HEARTBEAT_PID" 2>/dev/null || true

if [[ "$XCODEBUILD_STATUS" -ne 0 ]]; then
  exit "$XCODEBUILD_STATUS"
fi

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Built app not found at: $SOURCE_APP" >&2
  exit 1
fi

echo "==> Copying and renaming app to ${APP_NAME}.app"
cp -R "$SOURCE_APP" "$RENAMED_APP"

# Ensure all built OpenEmu cores are bundled into the app.
# This avoids runtime failures when a signed app tries to load ad-hoc user cores.
CORES_SOURCE_DIR="$PRODUCTS_DIR"
CORES_DEST_DIR="$RENAMED_APP/Contents/PlugIns/Cores"
mkdir -p "$CORES_DEST_DIR"
echo "  -> Bundling core plugins from build products"
find "$CORES_SOURCE_DIR" -maxdepth 1 -type d -name "*.oecoreplugin" | while read -r core; do
  core_name=$(basename "$core")
  echo "    Copying $core_name"
  rm -rf "$CORES_DEST_DIR/$core_name"
  cp -R "$core" "$CORES_DEST_DIR/$core_name"
done

# Strip arm64 from Sparkle binaries (we build x86_64 only).
# Use -L to follow symlinks because Sparkle uses Versions/B and Versions/Current links.
echo "  -> Stripping arm64 from Sparkle.framework binaries"
SPARKLE_ROOT="$RENAMED_APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_ROOT" ]]; then
  while read -r bin; do
    if file "$bin" | grep -q "Mach-O"; then
      LIPO_INFO=$(lipo -info "$bin" 2>/dev/null || true)
      if echo "$LIPO_INFO" | grep -q "arm64"; then
        if ! echo "$LIPO_INFO" | grep -q "x86_64"; then
          echo "ERROR: $bin contains arm64 but no x86_64 slice." >&2
          exit 1
        fi
        echo "    Thinning $bin to x86_64 only"
        lipo -thin x86_64 "$bin" -output "$bin.thin"
        mv "$bin.thin" "$bin"
      fi
    fi
  done < <(find -L "$SPARKLE_ROOT" -type f 2>/dev/null)
fi

APP_PLIST="$RENAMED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP_PLIST" || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP_PLIST" || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$APP_PLIST"

if [[ "$SKIP_SIGN" -eq 0 ]]; then
  echo "==> Signing app (inside-out) with identity: $IDENTITY"

  # Strip the debug entitlement (com.apple.security.get-task-allow) from
  # OpenEmuHelperApp so Apple's notary service accepts it.
  # There may be multiple copies (e.g. MacOS/ and Resources/), so sign all of them.
  echo "  -> Extracting and sanitizing entitlements for OpenEmuHelperApp"
  find "$RENAMED_APP" -name "OpenEmuHelperApp" -type f 2>/dev/null | while read -r HELPER_BIN; do
    echo "    Signing $HELPER_BIN"
    HELPER_ENT_RAW=$(mktemp /tmp/helper-ent-raw.XXXXXX.plist)
    HELPER_ENT=$(mktemp /tmp/helper-ent.XXXXXX.plist)
    # Extract existing entitlements (may be absent; ignore errors)
    codesign -d --entitlements - --xml "$HELPER_BIN" > "$HELPER_ENT_RAW" 2>/dev/null || true
    if [[ -s "$HELPER_ENT_RAW" ]]; then
      # Copy and delete the debug key if present
      cp "$HELPER_ENT_RAW" "$HELPER_ENT"
      /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$HELPER_ENT" 2>/dev/null || true
    else
      # No prior entitlements — write a minimal placeholder
      printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict></dict></plist>' > "$HELPER_ENT"
    fi

    # Hardened runtime with dynarec/JIT requires explicit runtime entitlements.
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.allow-jit bool true" "$HELPER_ENT" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :com.apple.security.cs.allow-jit true" "$HELPER_ENT" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.allow-unsigned-executable-memory bool true" "$HELPER_ENT" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :com.apple.security.cs.allow-unsigned-executable-memory true" "$HELPER_ENT" 2>/dev/null || true

    codesign --entitlements "$HELPER_ENT" "${CODESIGN_RUNTIME_ARGS[@]}" "$HELPER_BIN"
    rm -f "$HELPER_ENT_RAW" "$HELPER_ENT"
  done || true

  # Sign the QuickLook plugin binary explicitly
  QL_BIN="$RENAMED_APP/Contents/Library/QuickLook/OESaveStateQLPlugin.qlgenerator"
  if [[ -d "$QL_BIN" ]]; then
    echo "  -> Signing OESaveStateQLPlugin.qlgenerator"
    codesign "${CODESIGN_RUNTIME_ARGS[@]}" "$QL_BIN"
  fi

  # Sparkle has nested executables that notary validates directly.
  # Sign these explicitly so Versions/B targets are definitely signed.
  SPARKLE_AUTOUPDATE="$RENAMED_APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  SPARKLE_UPDATER_APP="$RENAMED_APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
  SPARKLE_DOWNLOADER_XPC="$RENAMED_APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
  SPARKLE_INSTALLER_XPC="$RENAMED_APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
  SPARKLE_FRAMEWORK="$RENAMED_APP/Contents/Frameworks/Sparkle.framework"

  if [[ -f "$SPARKLE_AUTOUPDATE" ]]; then
    echo "  -> Signing Sparkle Autoupdate binary"
    codesign "${CODESIGN_RUNTIME_ARGS[@]}" "$SPARKLE_AUTOUPDATE"
  fi
  if [[ -d "$SPARKLE_UPDATER_APP" ]]; then
    echo "  -> Signing Sparkle Updater.app"
    codesign "${CODESIGN_RUNTIME_ARGS[@]}" "$SPARKLE_UPDATER_APP"
  fi
  if [[ -d "$SPARKLE_DOWNLOADER_XPC" ]]; then
    echo "  -> Signing Sparkle Downloader.xpc"
    codesign "${CODESIGN_RUNTIME_ARGS[@]}" "$SPARKLE_DOWNLOADER_XPC"
  fi
  if [[ -d "$SPARKLE_INSTALLER_XPC" ]]; then
    echo "  -> Signing Sparkle Installer.xpc"
    codesign "${CODESIGN_RUNTIME_ARGS[@]}" "$SPARKLE_INSTALLER_XPC"
  fi
  if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "  -> Signing Sparkle.framework"
    codesign "${CODESIGN_RUNTIME_ARGS[@]}" "$SPARKLE_FRAMEWORK"
  fi

  # Sign all remaining nested frameworks, dylibs, bundles, and executables
  # bottom-up so the outer bundle signature covers already-signed internals.
  echo "  -> Signing nested frameworks and plugins"
  find "$RENAMED_APP" \
    \( -name "*.framework" -o -name "*.dylib" -o -name "*.so" -o -name "*.oecoreplugin" \
       -o -name "*.oesystemplugin" -o -name "*.xpc" -o -name "*.app" \
       -o -name "*.qlgenerator" \) \
    -not -path "$RENAMED_APP" \
    | sort -r \
    | while read -r item; do
        codesign "${CODESIGN_RUNTIME_ARGS[@]}" "$item"
      done

  # Finally sign the outer app bundle
  echo "  -> Signing outer app bundle"
  codesign "${CODESIGN_RUNTIME_ARGS[@]}" "$RENAMED_APP"

  echo "==> Verifying signature"
  codesign --verify --deep --strict --verbose=2 "$RENAMED_APP"
else
  echo "==> Skipping signing"
fi

if [[ "$SKIP_DMG" -eq 0 ]]; then
  echo "==> Creating DMG"
  mkdir -p "$DMG_STAGING_DIR"
  cp -R "$RENAMED_APP" "$DMG_STAGING_DIR/"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"

  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

  rm -rf "$DMG_STAGING_DIR"

  if [[ "$SKIP_SIGN" -eq 0 ]]; then
    echo "==> Signing DMG"
    codesign "${CODESIGN_DMG_ARGS[@]}" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
  fi
else
  echo "==> Skipping DMG creation"
fi

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  if [[ "$SKIP_DMG" -eq 1 ]]; then
    echo "Notarization currently expects a DMG. Remove --skip-dmg or add --skip-notarize." >&2
    exit 1
  fi

  echo "==> Submitting for notarization"
  NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)
  echo "$NOTARY_OUTPUT"

  # Extract submission ID for log fetching on failure
  SUBMISSION_ID=$(echo "$NOTARY_OUTPUT" | grep -E '^\s+id:' | head -1 | awk '{print $2}')

  if echo "$NOTARY_OUTPUT" | grep -q "status: Invalid"; then
    echo "" >&2
    echo "==> Notarization REJECTED. Fetching Apple's rejection log..." >&2
    if [[ -n "$SUBMISSION_ID" ]]; then
      xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" 2>&1 | tee "$OUTPUT_DIR/notary-rejection.json" >&2
    fi
    exit 1
  fi

  echo "==> Stapling ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"

  echo "==> Verifying Gatekeeper acceptance"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
else
  echo "==> Skipping notarization"
fi

echo "==> Done"
echo "App: $RENAMED_APP"
if [[ -f "$DMG_PATH" ]]; then
  echo "DMG: $DMG_PATH"
fi
if [[ -n "$TEAM_ID" ]]; then
  echo "Team ID: $TEAM_ID"
fi

USER_CORES_DIR="$HOME/Library/Application Support/OpenEmu/Cores"
if [[ -d "$USER_CORES_DIR" ]]; then
  ADHOC_USER_CORES=$(find "$USER_CORES_DIR" -maxdepth 1 -type d -name "*.oecoreplugin" | while read -r core; do
    if codesign -dv --verbose=2 "$core" 2>&1 | grep -q "Signature=adhoc"; then
      basename "$core"
    fi
  done)

  if [[ -n "$ADHOC_USER_CORES" ]]; then
    echo ""
    echo "WARNING: ad-hoc user core overrides detected in ~/Library/Application Support/OpenEmu/Cores"
    echo "These can fail to load in the signed app due to hardened runtime."
    echo "Consider moving them aside so bundled signed cores are used:"
    echo "$ADHOC_USER_CORES" | sed 's/^/  - /'
  fi
fi
