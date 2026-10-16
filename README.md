# Utter

Private, on-device dictation for every app. Hold a key (Mac) or a button (Android), talk, and your words appear where the cursor is. Say "Hey Cosmic" to start hands-free on the Mac.

Speech recognition runs on the device. Transcripts stay on the device. Nothing is sent to a server.

| | Mac | Android |
|---|---|---|
| Surface | Menu bar app with a floating pill | Voice keyboard |
| Start | Hold Fn (or Right Option), or say "Hey Cosmic" | Hold the round button |
| Hands-free | Fn + Space | Tap the button |
| Speech engine | Apple SpeechAnalyzer (macOS 26) | Android on-device SpeechRecognizer |
| Updates | Sparkle | Built-in updater |

## Install

Download the latest build from [Releases](https://github.com/thebigjah/utter/releases).

- **Mac:** unzip, move Utter to Applications, open it, and grant Microphone and Accessibility.
- **Android:** install the APK, open Utter, and follow the three setup steps.

## Build

- Mac: `cd mac && ./build.sh install` (Xcode 26, macOS 26)
- Android: `cd android && ./gradlew assembleDebug` (JDK 17, Android SDK 36)

Both apps share one formatter (filler words, stutters, "new line" and "new paragraph", dictionary, replacements, snippets), with matching tests in `mac/Tests` and `android/app/src/test`.

© 2026 Purcell Ventures LLC
