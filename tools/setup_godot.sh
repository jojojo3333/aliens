#!/usr/bin/env bash
# Fetches the pinned Godot build into .godot-bin/ (gitignored).
# Idempotent: exits immediately if the pinned version is already present.
set -euo pipefail

GODOT_VERSION="4.7-stable"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$REPO_ROOT/.godot-bin"
BIN="$BIN_DIR/Godot_v${GODOT_VERSION}_linux.x86_64"

if [[ -x "$BIN" ]]; then
  echo "godot $GODOT_VERSION already present at $BIN"
  exit 0
fi

mkdir -p "$BIN_DIR"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"

echo "fetching godot $GODOT_VERSION ..."
for attempt in 1 2 3 4; do
  if curl -sSL -o "$BIN_DIR/godot.zip" "$URL"; then
    break
  fi
  if [[ $attempt -eq 4 ]]; then
    echo "failed to download godot after 4 attempts" >&2
    exit 1
  fi
  sleep $((2 ** attempt))
done

unzip -o -q "$BIN_DIR/godot.zip" -d "$BIN_DIR"
rm -f "$BIN_DIR/godot.zip"
chmod +x "$BIN"

"$BIN" --headless --version
echo "godot ready at $BIN"
