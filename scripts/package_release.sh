#!/bin/bash
# Build, sign, notarize, staple, and zip a seesee release.
#
# Local release (what v0.2.2 used):
#   REPLAY_SIGNING_IDENTITY="Developer ID Application: YIQI XIE (ANVS3UQK9W)" \
#   REPLAY_NOTARIZE=1 REPLAY_NOTARY_PROFILE=openmy-notary \
#   REPLAY_UNIVERSAL=0 REPLAY_BUNDLED_TOOLS_DIR=.build/runtime-tools/arm64 \
#       ./scripts/package_release.sh
#
# Output: dist/release-v<version>/seesee-v<version>-<arch>.zip and .sha256,
# where the archive contains seesee.app.
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
signing_identity="${REPLAY_SIGNING_IDENTITY:--}"
notarize="${REPLAY_NOTARIZE:-0}"
notary_profile="${REPLAY_NOTARY_PROFILE:-}"
notary_keychain="${REPLAY_NOTARY_KEYCHAIN:-}"
universal="${REPLAY_UNIVERSAL:-1}"

if [[ "$notarize" == "1" ]]; then
    if [[ "$signing_identity" == "-" || -z "$notary_profile" ]]; then
        echo "REPLAY_NOTARIZE=1 requires REPLAY_SIGNING_IDENTITY and REPLAY_NOTARY_PROFILE." >&2
        exit 1
    fi
fi

runtime_tools_dir="${REPLAY_BUNDLED_TOOLS_DIR:-}"
if [[ -z "$runtime_tools_dir" ]]; then
    runtime_tools_dir=$("$project_dir/scripts/prepare_runtime_tools.sh" | tail -1)
fi
runtime_tools_dir="$(cd "$runtime_tools_dir" && pwd)"

REPLAY_UNIVERSAL="$universal" \
REPLAY_BUNDLED_TOOLS_DIR="$runtime_tools_dir" \
REPLAY_SIGNING_IDENTITY="$signing_identity" \
REPLAY_INSTALL_APP=0 \
REPLAY_LAUNCH_APP=0 \
    "$project_dir/scripts/build_app.sh"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")
if [[ "$universal" == "1" ]]; then
    arch_label="universal"
else
    arch_label="apple-silicon"
fi
release_dir="$project_dir/dist/release-v$version"
stage_dir="$release_dir/stage"
app="$stage_dir/seesee.app"
archive="$release_dir/seesee-v$version-$arch_label.zip"
checksum="$archive.sha256"
notary_archive="$release_dir/notarization-upload.zip"

rm -rf "$stage_dir" "$archive" "$checksum" "$notary_archive"
mkdir -p "$stage_dir"
ditto "$project_dir/dist/Replay.app" "$app"
codesign --verify --deep --strict "$app"

if [[ "$notarize" == "1" ]]; then
    notary_args=(--keychain-profile "$notary_profile")
    if [[ -n "$notary_keychain" ]]; then
        notary_args+=(--keychain "$notary_keychain")
    fi
    ditto -c -k --sequesterRsrc --keepParent "$app" "$notary_archive"
    submit_output=$(xcrun notarytool submit "$notary_archive" "${notary_args[@]}" --wait --timeout 45m 2>&1) || true
    printf '%s\n' "$submit_output"
    if ! grep -q "status: Accepted" <<<"$submit_output"; then
        submission_id=$(awk '/^  id: / { print $2; exit }' <<<"$submit_output")
        if [[ -n "$submission_id" ]]; then
            xcrun notarytool log "$submission_id" "${notary_args[@]}" >&2 || true
        fi
        echo "Notarization was not accepted; release stopped." >&2
        exit 1
    fi
    rm -f "$notary_archive"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi

(
    cd "$stage_dir"
    ditto -c -k --sequesterRsrc --keepParent seesee.app "$archive"
)
(
    cd "$release_dir"
    shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")"
)

printf '%s\n%s\n' "$archive" "$checksum"
