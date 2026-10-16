#!/bin/bash
# Cuts an Android update: bump versionCode/versionName in app/build.gradle.kts first, then ./release.sh
# Builds dist/Utter-<version>.apk, publishes it as GitHub release android-v<version>, and writes ../feeds/android.json.
# Commit and push feeds/android.json afterwards; that push is what makes the update visible.
set -euo pipefail
cd "$(dirname "$0")"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"

CODE=$(sed -n 's/.*versionCode = \([0-9]*\).*/\1/p' app/build.gradle.kts)
NAME=$(sed -n 's/.*versionName = "\(.*\)".*/\1/p' app/build.gradle.kts)
PREFIX="${DOWNLOAD_PREFIX:-https://github.com/thebigjah/utter/releases/download/android-v${NAME}/}"

./gradlew :app:testDebugUnitTest :app:assembleRelease -q
mkdir -p dist
APK="Utter-${NAME}.apk"
cp app/build/outputs/apk/release/app-release.apk "dist/$APK"
mkdir -p ../feeds
cat > ../feeds/android.json <<JSON
{"versionCode": ${CODE}, "versionName": "${NAME}", "apkUrl": "${PREFIX}${APK}", "notes": "${NOTES:-}"}
JSON
if [[ "${PUBLISH:-1}" == "1" ]]; then
  gh release create "android-v${NAME}" "dist/$APK" --repo thebigjah/utter --title "Utter for Android ${NAME}" --notes "${NOTES:-}"
fi
echo "Released dist/$APK. Now commit and push feeds/android.json."
