#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_VERSION="$(awk '/MARKETING_VERSION:/ { print $2; exit }' "$ROOT_DIR/project.yml")"
VERSION="${1:-$DEFAULT_VERSION}"
VERSION="${VERSION#v}"
TAG="v$VERSION"
REPO="aaramos/ClearVoice_native"
DMG_PATH="$ROOT_DIR/.build/dist/ClearVoice-$VERSION.dmg"
NOTES_ONLY=0

shift $(( $# > 0 ? 1 : 0 ))

for arg in "$@"; do
  case "$arg" in
    --notes-only)
      NOTES_ONLY=1
      ;;
    *)
      DMG_PATH="$arg"
      ;;
  esac
done

NOTES_FILE="$(mktemp /tmp/clearvoice_release_notes.XXXXXX)"
cleanup() {
  rm -f "$NOTES_FILE"
}
trap cleanup EXIT

"$ROOT_DIR/script/release_notes_body.sh" "$VERSION" > "$NOTES_FILE"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release edit "$TAG" --repo "$REPO" --title "$TAG" --notes-file "$NOTES_FILE"

  if [[ "$NOTES_ONLY" -eq 0 && -f "$DMG_PATH" ]]; then
    gh release upload "$TAG" "$DMG_PATH" --repo "$REPO" --clobber
  fi
else
  if [[ "$NOTES_ONLY" -eq 1 ]]; then
    echo "Release $TAG does not exist yet, so --notes-only cannot be used." >&2
    exit 1
  fi

  if [[ ! -f "$DMG_PATH" ]]; then
    echo "Expected DMG not found: $DMG_PATH" >&2
    exit 1
  fi

  gh release create "$TAG" "$DMG_PATH" --repo "$REPO" --title "$TAG" --notes-file "$NOTES_FILE"
fi

echo "Published release notes for $TAG from RELEASE_NOTES.md"
