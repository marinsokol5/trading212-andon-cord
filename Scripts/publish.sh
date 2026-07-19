#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-marinsokol5/trading212-andon-cord}"
TAP_DIR="${TAP_DIR:-$HOME/projects/homebrew-tap}"
LOCAL_CASK="Casks/trading212-andon-cord.rb"
TAP_CASK="$TAP_DIR/Casks/trading212-andon-cord.rb"
PLIST="Support/Info.plist.in"
CLI_SOURCE="Sources/andon/AndonCLI.swift"

cd "$(git rev-parse --show-toplevel)"

if [[ -z "${ALLOW_DIRTY:-}" && -n "$(git status --porcelain)" ]]; then
  echo "working tree is dirty; commit first or set ALLOW_DIRTY=1" >&2
  git status --short
  exit 1
fi

if [[ $# -ge 1 && -n "$1" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $1" "$PLIST"
  /usr/bin/sed -i '' -E \
    "s/(static let version = \")[^\"]*(\")/\1$1\2/" "$CLI_SOURCE"
  git add "$PLIST" "$CLI_SOURCE"
  if ! git diff --cached --quiet; then
    git commit -m "Bump to $1"
  fi
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
CLI_VERSION="$(/usr/bin/sed -nE 's/.*static let version = "([^"]+)".*/\1/p' "$CLI_SOURCE")"
TAG="v$VERSION"
ZIP=".build/Trading212-Andon-Cord-$VERSION.zip"

[[ -d "$TAP_DIR/.git" ]] || {
  echo "Homebrew tap checkout not found: $TAP_DIR (set TAP_DIR)" >&2
  exit 1
}
[[ "$CLI_VERSION" == "$VERSION" ]] || {
  echo "version mismatch: Info.plist=$VERSION CLI=$CLI_VERSION" >&2
  exit 1
}
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "release already exists: $TAG" >&2
  exit 1
fi

echo "==> publishing Trading212 Andon Cord $VERSION to $REPO"
if [[ -z "${YES:-}" ]]; then
  [[ -t 0 ]] || { echo "non-interactive; set YES=1" >&2; exit 1; }
  read -r -p "Continue? [y/N] " answer
  [[ "$answer" == [yY]* ]] || exit 1
fi

make release
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
/usr/bin/sed -i '' -E \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 .*/  sha256 \"$SHA\"/" \
  "$LOCAL_CASK"
git add "$LOCAL_CASK"
if ! git diff --cached --quiet; then
  git commit -m "Prepare Trading212 Andon Cord $VERSION cask"
fi

RELEASE_COMMIT="$(git rev-parse HEAD)"
git push origin HEAD
if [[ -n "${NOTES:-}" ]]; then
  gh release create "$TAG" "$ZIP" --repo "$REPO" \
    --target "$RELEASE_COMMIT" --title "Trading212 Andon Cord $VERSION" --notes "$NOTES"
else
  gh release create "$TAG" "$ZIP" --repo "$REPO" \
    --target "$RELEASE_COMMIT" --title "Trading212 Andon Cord $VERSION" --generate-notes
fi

mkdir -p "$(dirname "$TAP_CASK")"
cp "$LOCAL_CASK" "$TAP_CASK"
git -C "$TAP_DIR" add Casks/trading212-andon-cord.rb
if ! git -C "$TAP_DIR" diff --cached --quiet; then
  git -C "$TAP_DIR" commit -m "trading212-andon-cord $VERSION"
fi
git -C "$TAP_DIR" push origin HEAD

echo "==> published $TAG"

echo "==> upgrading local install"
brew upgrade -y --cask marinsokol5/tap/trading212-andon-cord

# Match the running app by its bundle path (the process name is the
# executable, which pgrep truncates), and quit by bundle id so display-name
# changes never break this.
echo "==> restarting Trading 212 Andon Cord"
if pgrep -qf "Trading212 Andon Cord.app/Contents/MacOS"; then
  osascript -e 'tell application id "com.marinsokol.trading212andoncord" to quit'
  for _ in {1..20}; do
    pgrep -qf "Trading212 Andon Cord.app/Contents/MacOS" || break
    sleep 0.25
  done
fi
open -b com.marinsokol.trading212andoncord
