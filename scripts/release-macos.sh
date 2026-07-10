#!/usr/bin/env bash
#
# release-macos.sh — build a notarized, stapled, distributable macOS release of
# Minecraft Server Controller.
#
# Pipeline:
#   1. xcodebuild archive        (Release, into a temp .xcarchive)
#   2. xcodebuild -exportArchive (Developer ID re-sign via scripts/exportOptions.plist)
#   3. ditto -> .zip             (notarization submission payload)
#   4. xcrun notarytool submit --wait   (credentials from a keychain profile)
#   5. xcrun stapler staple      (attach the notarization ticket to the .app)
#   6. ditto -> versioned .zip in dist/ (the artifact you ship)
#   7. spctl / stapler validate  (prove Gatekeeper accepts the result)
#
# One-time human setup is documented in docs/release.md. In short you must have:
#   - a "Developer ID Application" certificate in your login keychain, and
#   - a notarytool keychain profile (default name: MSC_NOTARY), created once with:
#
#       xcrun notarytool store-credentials "MSC_NOTARY" \
#         --apple-id "<your-apple-id-email>" \
#         --team-id "6898622Y3Y" \
#         --password "<app-specific-password>"
#
#   (An App Store Connect API key works too — see docs/release.md.)
#
# Usage:
#   scripts/release-macos.sh                 # full pipeline
#   NOTARY_PROFILE=OtherName scripts/release-macos.sh
#   SKIP_NOTARIZE=1 scripts/release-macos.sh # archive+export+sign only (no notary creds)
#
set -euo pipefail

# ---- Configuration ----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT="${REPO_ROOT}/MSCmacOS/Minecraft_Server_Controller.xcodeproj"
SCHEME="MinecraftServerController"
CONFIGURATION="Release"
EXPORT_OPTIONS="${SCRIPT_DIR}/exportOptions.plist"
NOTARY_PROFILE="${NOTARY_PROFILE:-MSC_NOTARY}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

DIST_DIR="${REPO_ROOT}/dist"
BUILD_DIR="${DIST_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/MinecraftServerController.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"

# ---- Helpers ----------------------------------------------------------------
log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "${PROJECT}" ]]          || fail "Project not found at ${PROJECT}"
[[ -f "${EXPORT_OPTIONS}" ]]   || fail "Missing ${EXPORT_OPTIONS}"

# ---- 0. Clean previous build artifacts (keep already-shipped zips in dist/) --
log "Preparing dist/ (${DIST_DIR})"
rm -rf "${BUILD_DIR}"
mkdir -p "${EXPORT_DIR}"

# ---- 1. Archive -------------------------------------------------------------
log "Archiving ${SCHEME} (${CONFIGURATION})"
xcodebuild archive \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${ARCHIVE_PATH}" \
  -destination 'generic/platform=macOS'

[[ -d "${ARCHIVE_PATH}" ]] || fail "Archive was not produced at ${ARCHIVE_PATH}"

# ---- 2. Export with Developer ID re-signing ---------------------------------
log "Exporting Developer ID build"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}" \
  -exportPath "${EXPORT_DIR}"

# Locate the exported .app (name contains spaces: "Minecraft Server Controller.app").
APP_PATH="$(/usr/bin/find "${EXPORT_DIR}" -maxdepth 1 -name '*.app' -print -quit)"
[[ -n "${APP_PATH}" && -d "${APP_PATH}" ]] || fail "No .app found in ${EXPORT_DIR}"
log "Exported: ${APP_PATH}"

# Derive the version from the built app so the artifact name is always correct.
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}" 2>/dev/null || echo 'unknown')"
BUILD_NUM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}" 2>/dev/null || echo '0')"
log "Version ${VERSION} (build ${BUILD_NUM})"

# Confirm the re-sign actually used Developer ID (not the dev cert).
log "Verifying code signature authority"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 | tail -5 || true
SIGN_AUTH="$(codesign -dvv "${APP_PATH}" 2>&1 | grep -i 'Authority=Developer ID Application' || true)"
[[ -n "${SIGN_AUTH}" ]] || fail "App is NOT signed with a Developer ID Application certificate. \
Check that identity 'Developer ID Application: ... (6898622Y3Y)' is in your keychain."
log "Signed by: ${SIGN_AUTH#*=}"

# ---- 3. Zip for notarization submission -------------------------------------
NOTARIZE_ZIP="${BUILD_DIR}/MSC-notarize.zip"
log "Zipping app for notarization submission"
/usr/bin/ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"

# ---- 4. Notarize ------------------------------------------------------------
if [[ "${SKIP_NOTARIZE}" == "1" ]]; then
  log "SKIP_NOTARIZE=1 set — stopping after Developer ID export/sign. \
Not notarized, not stapled. (The exported app is at ${APP_PATH}.)"
  exit 0
fi

if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
  fail "notarytool keychain profile '${NOTARY_PROFILE}' not found.
Create it once (see docs/release.md):

  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\
    --apple-id \"<your-apple-id-email>\" \\
    --team-id \"6898622Y3Y\" \\
    --password \"<app-specific-password>\"

Or run with SKIP_NOTARIZE=1 to produce a signed-but-unnotarized build for local testing."
fi

log "Submitting to Apple notary service (this can take a few minutes)"
xcrun notarytool submit "${NOTARIZE_ZIP}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

# ---- 5. Staple --------------------------------------------------------------
log "Stapling notarization ticket to the app"
xcrun stapler staple "${APP_PATH}"

# ---- 6. Produce the versioned distributable zip -----------------------------
DIST_ZIP="${DIST_DIR}/MinecraftServerController-${VERSION}.zip"
log "Creating distributable: ${DIST_ZIP}"
rm -f "${DIST_ZIP}"
/usr/bin/ditto -c -k --keepParent "${APP_PATH}" "${DIST_ZIP}"

# ---- 7. Validate ------------------------------------------------------------
log "Validating stapled ticket"
xcrun stapler validate "${APP_PATH}"

log "Gatekeeper assessment (spctl)"
spctl -a -vv "${APP_PATH}"

log "DONE. Notarized, stapled build at:
  ${DIST_ZIP}
Upload this zip to a GitHub Release (see docs/release.md for tagging convention)."
