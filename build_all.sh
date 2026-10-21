#!/usr/bin/env bash
# build_all.sh — every dist/ artifact buildable on a Linux host, in one run.
# Skips MSI/MSIX (Windows host only). dist/ is append-only: nothing existing
# is deleted, moved, or overwritten (the collector refuses to overwrite).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export NDK_HOME="${NDK_HOME:-$ANDROID_HOME/ndk/27.0.12077973}"
if [ -z "${JAVA_HOME:-}" ]; then
  JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  export JAVA_HOME
fi

TAURI=./node_modules/.bin/tauri

test -d node_modules || npm ci

# Automatic version bump — the stamper owns the version; never set it manually.
# The pre-build gate requires the stamp to be recorded source, so commit it.
npm run stamp
(cd src-tauri && cargo update --workspace)
VERSION="$(tr -d '\r\n' < version.txt)"
git add Package.appxmanifest version.txt version.json package.json package-lock.json src-tauri/tauri.conf.json src-tauri/Cargo.toml src-tauri/Cargo.lock
git commit -m "v${VERSION}: stamp (build_all)"

# Web/PWA surface (also the frontend embedded in every native shell)
npm run build:vite

# Linux: deb + AppImage
"$TAURI" build --bundles deb,appimage --ci

# Windows cross-compile: standalone PE + NSIS installer (MSI/MSIX deferred to a Windows host)
NSIS_PROJ="src-tauri/target/x86_64-pc-windows-msvc/release/nsis/x64"
if ! "$TAURI" build --runner cargo-xwin --target x86_64-pc-windows-msvc --bundles nsis --ci; then
  # Upstream tauri-bundler defect: the apostrophe in the product name breaks
  # the single-quoted COM parameter strings in the generated utils.nsh
  # (NSISCOMCALL "requires 4 parameter(s), passed 7"). Requote the COM
  # interface calls with backticks and run makensis (>= 3.11) directly.
  sed -i '/${I[A-Za-z]*::/ s/'"'"'/`/g' "$NSIS_PROJ/utils.nsh"
  (cd "$NSIS_PROJ" && makensis -INPUTCHARSET UTF8 installer.nsi)
  mkdir -p src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis
  mv "$NSIS_PROJ/nsis-output.exe" \
    "src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/St. Android's Missal_${VERSION}_x64-setup.exe"
fi
test -f src-tauri/target/x86_64-pc-windows-msvc/release/st-androids-missal.exe
ls src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/*_x64-setup.exe >/dev/null

# Android: debug APK, then release APK + AAB with native symbols preserved
"$TAURI" android build --debug --apk --ci

# Dual-key release: when .env names an alternate upload-key pointer
# (SAM_ALT_KEYSTORE_PROPERTIES, Admin-Manual path only), build the release
# with it first and park its outputs inside the gitignored Gradle build dir;
# they are labeled into dist/ after collection. The primary-key build below
# then produces the standard outputs the collector expects.
ANDROID_OUT=src-tauri/gen/android/app/build/outputs
ALT_OUT=src-tauri/gen/android/app/build/outputs-altkey
ALT_PROPS="$(sed -n 's/^SAM_ALT_KEYSTORE_PROPERTIES=//p' .env 2>/dev/null | tail -1)"
ALT_PROPS="${ALT_PROPS/#\~/$HOME}"
if [ -n "$ALT_PROPS" ]; then
  test -f "$ALT_PROPS"
  SAM_KEYSTORE_PROPERTIES="$ALT_PROPS" CARGO_PROFILE_RELEASE_STRIP=false "$TAURI" android build --apk --aab --ci
  mkdir -p "$ALT_OUT"
  cp "$ANDROID_OUT/apk/universal/release/standroidsmissal-v${VERSION}-universal-release.apk" "$ALT_OUT/"
  cp "$ANDROID_OUT/bundle/universalRelease/standroidsmissal-v${VERSION}-universal-release.aab" "$ALT_OUT/"
fi
CARGO_PROFILE_RELEASE_STRIP=false "$TAURI" android build --apk --aab --ci

# Android native debug symbols zip
bash scripts/package-android-symbols.sh

# Collect the stamped set into dist/ (append-only, hashed, manifested)
npm run collect-artifacts

# Label every release APK/AAB in dist/ with the upload certificate that signed it.
signer_label() {
  keytool -printcert -jarfile "$1" | sed -n 's/^Owner: CN=\([^,]*\).*/\1/p' | head -1 \
    | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-$//'
}
KEYMAP="dist/standroidsmissal-v${VERSION}-android-signing-keys.md"
{
  echo "# v${VERSION} Android release signing"
  echo
  echo "| file | signer | certificate SHA-256 |"
  echo "|---|---|---|"
} > "$KEYMAP"
label_into_dist() {
  local src="$1" ext="$2" label sha
  label="$(signer_label "$src")"
  test -n "$label"
  sha="$(keytool -printcert -jarfile "$src" | sed -n 's/^\s*SHA256: //p' | head -1)"
  local dst="dist/standroidsmissal-v${VERSION}-android-universal-release-key-${label}.${ext}"
  test ! -e "$dst"
  cp "$src" "$dst"
  echo "| $(basename "$dst") | ${label} | ${sha} |" >> "$KEYMAP"
}
label_into_dist "dist/standroidsmissal-v${VERSION}-android-universal-release.apk" apk
label_into_dist "dist/standroidsmissal-v${VERSION}-android-universal-release.aab" aab
if [ -n "$ALT_PROPS" ]; then
  label_into_dist "$ALT_OUT/standroidsmissal-v${VERSION}-universal-release.apk" apk
  label_into_dist "$ALT_OUT/standroidsmissal-v${VERSION}-universal-release.aab" aab
fi
cat "$KEYMAP"

echo "✅ build_all complete — artifacts in dist/ (MSI/MSIX pending Windows host)"
