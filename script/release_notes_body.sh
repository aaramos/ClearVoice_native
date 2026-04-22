#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTES_FILE="$ROOT_DIR/RELEASE_NOTES.md"
VERSION="${1:-$(awk '/MARKETING_VERSION:/ { print $2; exit }' "$ROOT_DIR/project.yml")}"
VERSION="${VERSION#v}"

if [[ ! -f "$NOTES_FILE" ]]; then
  echo "Release notes file not found: $NOTES_FILE" >&2
  exit 1
fi

BODY="$(awk -v version="$VERSION" '
  BEGIN { capture = 0 }
  $0 ~ "^## " version " —" {
    capture = 1
    print $0
    next
  }
  capture && $0 ~ "^## " {
    exit
  }
  capture {
    print $0
  }
' "$NOTES_FILE")"

if [[ -z "${BODY//[[:space:]]/}" ]]; then
  echo "No release notes section found for version $VERSION in $NOTES_FILE" >&2
  exit 1
fi

REQUIRED_NOTE="$(cat <<'EOF'
### Distribution Note

- The docs and release notes now explain the simplest current sharing path for an unsigned `.dmg`.
- Trusted testers should expect the first launch to require `System Settings > Privacy & Security > Open Anyway` until signing and notarization are added.
EOF
)"

if [[ "$BODY" != *"The docs and release notes now explain the simplest current sharing path for an unsigned \`.dmg\`."* ]] || \
   [[ "$BODY" != *"Trusted testers should expect the first launch to require \`System Settings > Privacy & Security > Open Anyway\` until signing and notarization are added."* ]]; then
  BODY="${BODY%"${BODY##*[!$'\n']}"}"
  BODY+=$'\n\n'
  BODY+="$REQUIRED_NOTE"
fi

printf '%s\n' "$BODY"
