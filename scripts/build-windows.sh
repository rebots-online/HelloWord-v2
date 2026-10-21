#!/usr/bin/env bash
APP_SLUG="$(node "$(dirname "${BASH_SOURCE[0]}")/app-identity.mjs" slug)"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(node -p "JSON.parse(require('fs').readFileSync('version.json','utf8')).version")"
test "$(tr -d '\r\n' < version.txt)" = "$VERSION"

# cargo-xwin supplies the MSVC SDK/linker on Linux. The standalone PE is the
# reliable cross-host artifact; NSIS remains a Windows-host packaging layer.
./node_modules/.bin/tauri build \
  --runner cargo-xwin \
  --target x86_64-pc-windows-msvc \
  --no-bundle \
  --ci

test -f dist/target/x86_64-pc-windows-msvc/release/${APP_SLUG}.exe
