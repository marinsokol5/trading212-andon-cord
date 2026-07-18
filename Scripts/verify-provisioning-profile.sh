#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:?profile path is required}"
BUNDLE_ID="${2:?bundle identifier is required}"
TEAM_ID="${3:?team identifier is required}"

if [[ ! -f "$PROFILE" ]]; then
  echo "missing provisioning profile: $PROFILE" >&2
  exit 1
fi

TEMP="$(mktemp "${TMPDIR:-/tmp}/t212-profile.XXXXXX")"
trap 'rm -f "$TEMP"' EXIT

if ! /usr/bin/openssl cms -verify -noverify -inform DER \
  -in "$PROFILE" -out "$TEMP" >/dev/null 2>&1; then
  echo "invalid provisioning profile CMS signature: $PROFILE" >&2
  exit 1
fi

read_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$TEMP" 2>/dev/null || true
}

EXPECTED_APPLICATION_ID="$TEAM_ID.$BUNDLE_ID"
APPLICATION_ID="$(read_value 'Entitlements:com.apple.application-identifier')"
PROFILE_TEAM="$(read_value 'Entitlements:com.apple.developer.team-identifier')"
KEYCHAIN_ALLOWANCE="$(read_value 'Entitlements:keychain-access-groups:0')"
PLATFORM="$(read_value 'Platform:0')"
PROVISIONS_ALL_DEVICES="$(read_value 'ProvisionsAllDevices')"

[[ "$APPLICATION_ID" == "$EXPECTED_APPLICATION_ID" ]] || {
  echo "profile application identifier mismatch: expected $EXPECTED_APPLICATION_ID, got $APPLICATION_ID" >&2
  exit 1
}
[[ "$PROFILE_TEAM" == "$TEAM_ID" ]] || {
  echo "profile team mismatch: expected $TEAM_ID, got $PROFILE_TEAM" >&2
  exit 1
}
[[ "$KEYCHAIN_ALLOWANCE" == "$TEAM_ID.*" ]] || {
  echo "profile does not authorize this team's Keychain groups" >&2
  exit 1
}
[[ "$PROVISIONS_ALL_DEVICES" == "true" && "$PLATFORM" == "OSX" ]] || {
  echo "profile is not a macOS Developer ID direct-distribution profile" >&2
  exit 1
}

echo "==> verified $(read_value Name)"
