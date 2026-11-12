#!/usr/bin/env bash
# Generates the Android project (if missing) and applies the permissions and
# SDK level the app needs. Safe to run more than once.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  flutter create --platforms=android --org com.aishwaryaengg --project-name aes_team_app .
  # flutter create adds a sample test that references a counter app.
  rm -f test/widget_test.dart
fi

MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q ACCESS_FINE_LOCATION "$MANIFEST"; then
  perl -0pi -e 's#<application#<uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <application#' "$MANIFEST"
fi
# App name on the phone
perl -pi -e 's#android:label="[^"]*"#android:label="AES Team"#' "$MANIFEST"
# url_launcher on Android 11+ needs a <queries> entry to open https links.
if ! grep -q '<data android:scheme="https"' "$MANIFEST"; then
  perl -0pi -e 's#</queries>#    <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
    </queries>#' "$MANIFEST"
fi

# minSdk 23 (Firebase Auth). Handles both Groovy and Kotlin Gradle files.
for G in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$G" ] || continue
  perl -pi -e 's/minSdk\s*=\s*flutter\.minSdkVersion/minSdk = 23/; s/minSdkVersion\s+flutter\.minSdkVersion/minSdkVersion 23/' "$G"
done

echo "Android project ready."
