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

# Some plugins pin an old compileSdk; current AndroidX needs 36+.
# Raise every plugin to at least 36. Must run before evaluationDependsOn.
ROOT_KTS=android/build.gradle.kts
ROOT_GROOVY=android/build.gradle
if [ -f "$ROOT_KTS" ] && ! grep -q "AES_COMPILE_SDK" "$ROOT_KTS"; then
  perl -0pi -e 's/\nsubprojects \{/
\/\/ AES_COMPILE_SDK
subprojects {
    afterEvaluate {
        val ext = extensions.findByName("android") ?: return\@afterEvaluate
        try {
            val get = ext.javaClass.getMethod("getCompileSdk")
            val cur = get.invoke(ext) as Int?
            if (cur == null || cur < 36) {
                ext.javaClass.getMethod("setCompileSdk", Int::class.javaObjectType).invoke(ext, 36)
            }
        } catch (e: Exception) {
            logger.warn("AES: could not raise compileSdk for \${project.name}: \${e.message}")
        }
    }
}

subprojects {/' "$ROOT_KTS"
elif [ -f "$ROOT_GROOVY" ] && ! grep -q "AES_COMPILE_SDK" "$ROOT_GROOVY"; then
  perl -0pi -e 's/\nsubprojects \{/
\/\/ AES_COMPILE_SDK
subprojects {
    afterEvaluate { p ->
        if (p.hasProperty("android") && (p.android.compileSdkVersion == null
                || p.android.compileSdkVersion.replace("android-", "").toInteger() < 36)) {
            p.android.compileSdkVersion = 36
        }
    }
}

subprojects {/' "$ROOT_GROOVY"
fi

# Release signing with the company's permanent key (android/key.properties,
# written by CI from repository secrets). Without it, falls back to debug.
APP_KTS=android/app/build.gradle.kts
if [ -f "$APP_KTS" ] && ! grep -q "AES_SIGNING" "$APP_KTS"; then
  perl -0pi -e 's/\n    buildTypes \{/
    \/\/ AES_SIGNING
    signingConfigs {
        create("release") {
            val f = rootProject.file("key.properties")
            if (f.exists()) {
                val p = java.util.Properties()
                f.inputStream().use { p.load(it) }
                storeFile = file(p.getProperty("storeFile"))
                storePassword = p.getProperty("storePassword")
                keyAlias = p.getProperty("keyAlias")
                keyPassword = p.getProperty("keyPassword")
            }
        }
    }

    buildTypes {/' "$APP_KTS"
  perl -pi -e 's/signingConfig = signingConfigs\.getByName\("debug"\)/signingConfig = if (rootProject.file("key.properties").exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")/' "$APP_KTS"
fi

echo "Android project ready."
