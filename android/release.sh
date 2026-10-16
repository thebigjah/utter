#!/bin/bash
# Cuts an Android update: bump versionCode/versionName in app/build.gradle.kts first, then ./release.sh
# Produces dist/Utter-<version>.apk and dist/android.json for the release host.
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
cat > dist/android.json <<JSON
{"versionCode": ${CODE}, "versionName": "${NAME}", "apkUrl": "${PREFIX}${APK}", "notes": "${NOTES:-}"}
JSON
echo "Ready: dist/$APK and dist/android.json"
