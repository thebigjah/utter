#!/bin/bash
# Cuts a Sparkle update: ./release.sh 0.2.0 2
# Builds, zips, signs the zip with the EdDSA key in the Keychain (account "utter"),
# regenerates the appcast into ../feeds/appcast.xml, and publishes the zip as GitHub release mac-v<version>.
# Commit and push feeds/appcast.xml afterwards; that push is what makes the update visible.
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
mkdir -p ../feeds
cp dist/releases/appcast.xml ../feeds/appcast.xml
if [[ "${PUBLISH:-1}" == "1" ]]; then
  gh release create "mac-v${VERSION}" "$ZIP" --repo thebigjah/utter --title "Utter for Mac ${VERSION}" --notes "${NOTES:-}"
fi
echo "Released $ZIP. Now commit and push feeds/appcast.xml."
