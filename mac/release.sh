#!/bin/bash
# Cuts a Sparkle update: ./release.sh 0.2.0 2
# Builds, zips, signs the zip with the EdDSA key in the Keychain (account "utter"),
# and regenerates dist/releases/appcast.xml. Upload both to the release host.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: release.sh <version> <build>}"
BUILD="${2:?usage: release.sh <version> <build>}"
PREFIX="${DOWNLOAD_PREFIX:-https://github.com/thebigjah/utter/releases/download/mac-v${VERSION}/}"

VERSION="$VERSION" BUILD="$BUILD" ./build.sh
mkdir -p dist/releases
ZIP="dist/releases/Utter-${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent dist/Utter.app "$ZIP"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --account utter \
  --download-url-prefix "$PREFIX" dist/releases
echo "Ready: $ZIP and dist/releases/appcast.xml"
