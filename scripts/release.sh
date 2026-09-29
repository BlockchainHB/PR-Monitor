#!/usr/bin/env bash
# Builds a signed, notarized, stapled PR Monitor release: dist/PRMonitor.dmg and dist/PRMonitor.zip.
#
#   scripts/release.sh 1.1.0              build, sign, notarize into dist/
#   scripts/release.sh 1.1.0 --publish    …then tag v1.1.0 on origin/main and publish the GitHub release
#
# Environment:
#   TEAM_ID          Apple Developer team (default: G2537ZRGNU)
#   SIGN_IDENTITY    codesign identity (default: "Developer ID Application"). Use "-" for an ad-hoc
#                    local test build, which skips export and notarization.
#   NOTARY_PROFILE   notarytool keychain profile (local; see docs/RELEASING.md), or
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID   App Store Connect API key (CI).
#   BUILD_NUMBER     CFBundleVersion (default: commit count, which always increases)
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh <version> [--publish]}"
VERSION="${VERSION#v}"
PUBLISH="${2:-}"
if [[ -n "$PUBLISH" && "$PUBLISH" != "--publish" ]]; then
  echo "error: unknown option $PUBLISH" >&2; exit 1
fi
if [[ "$PUBLISH" == "--publish" ]]; then
  # Publish only what's on main, exactly as pushed, so the release matches the tagged source.
  git fetch -q origin main --tags
  if [[ -n "$(git status --porcelain)" || "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
    echo "error: --publish needs a clean checkout of origin/main" >&2; exit 1
  fi
  if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
    echo "error: tag v$VERSION already exists" >&2; exit 1
  fi
  [[ "${SIGN_IDENTITY:-}" == "-" ]] && { echo "error: can't publish an ad-hoc build" >&2; exit 1; }
fi
TEAM_ID="${TEAM_ID:-G2537ZRGNU}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
DIST="$PWD/dist"
# Build outside the checkout: iCloud-synced folders add extended attributes that break codesign.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/prmonitor-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

notarize() {
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${ASC_KEY_PATH:-}" ]]; then
    xcrun notarytool submit "$1" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
  else
    echo "error: set NOTARY_PROFILE or ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID to notarize" >&2
    exit 1
  fi
}

step "Archiving PR Monitor $VERSION ($BUILD_NUMBER)"
SIGNING_ARGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" != "-" ]] && SIGNING_ARGS+=("DEVELOPMENT_TEAM=$TEAM_ID" "OTHER_CODE_SIGN_FLAGS=--timestamp")
xcodebuild archive \
  -project PRMonitor.xcodeproj -scheme PRMonitor -configuration Release \
  -archivePath "$WORK/PRMonitor.xcarchive" -derivedDataPath "$WORK/DerivedData" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${SIGNING_ARGS[@]}" -quiet

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  step "Ad-hoc build: skipping export and notarization"
  APP="$WORK/PRMonitor.xcarchive/Products/Applications/PRMonitor.app"
else
  step "Exporting with Developer ID"
  cp scripts/ExportOptions.plist "$WORK/ExportOptions.plist"
  plutil -replace teamID -string "$TEAM_ID" "$WORK/ExportOptions.plist"
  xcodebuild -exportArchive -archivePath "$WORK/PRMonitor.xcarchive" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export" -quiet
  APP="$WORK/export/PRMonitor.app"

  step "Notarizing the app"
  ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
  notarize "$WORK/notarize.zip"
  xcrun stapler staple "$APP"
fi
codesign --verify --deep --strict --verbose=1 "$APP"

step "Building the disk image"
rm -rf "$DIST" && mkdir -p "$DIST" "$WORK/dmg"
ditto "$APP" "$WORK/dmg/PRMonitor.app"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -volname "PR Monitor" -srcfolder "$WORK/dmg" -fs APFS -format ULMO -ov "$DIST/PRMonitor.dmg" -quiet

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DIST/PRMonitor.dmg"
  step "Notarizing the disk image"
  notarize "$DIST/PRMonitor.dmg"
  xcrun stapler staple "$DIST/PRMonitor.dmg"
  spctl --assess --type open --context context:primary-signature --verbose "$DIST/PRMonitor.dmg"
fi

ditto -c -k --keepParent "$APP" "$DIST/PRMonitor.zip"

step "Checksums"
( cd "$DIST" && LC_ALL=C shasum -a 256 PRMonitor.dmg PRMonitor.zip | tee SHA256SUMS )

if [[ "$PUBLISH" == "--publish" ]]; then
  step "Publishing v$VERSION"
  git tag -a "v$VERSION" -m "PR Monitor $VERSION"
  git push -q origin "v$VERSION"
  gh release create "v$VERSION" "$DIST/PRMonitor.dmg" "$DIST/PRMonitor.zip" "$DIST/SHA256SUMS" \
    --title "PR Monitor $VERSION" --generate-notes --verify-tag --latest
fi
