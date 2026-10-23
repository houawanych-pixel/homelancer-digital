# Homelancer on phones (Android + iPhone)

Same Godot project as the web game. Mobile builds use **Godot 4.7.2** (Google Play needs target API 36 and 16 KB
page sizes; Godot 4.3 targets API 34). The web build stays on 4.3 for now.

- Presets: `export_presets.cfg` → `Android` (preset.1) and `iOS` (preset.2). Unlike the web preset, the phone presets
  include every asset (no content packs to download). Package / bundle ID: `com.homelancergame.homelancer`
  (permanent once uploaded; change it before the first upload if you want a different one).
- App icon (placeholder, from the Ranger render): `assets/app_icon/` (1024, 512, 192) + Play feature graphic 1024x500.
- Workflow: `.github/workflows/mobile-build.yml`, runs on every push to branch `mobile-release` (or "Run workflow").
  - Always: `homelancer-test-apk-N` artifact (debug-signed APK to sideload on your own phone).
  - With secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`: signed Play **AAB**.
  - With `PLAY_SERVICE_ACCOUNT_JSON` too: uploads the AAB to the Play internal testing track (draft).
  - With `IOS_TEAM_ID`, `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`, `IOS_PROFILE_BASE64`, `ASC_KEY_ID`,
    `ASC_ISSUER_ID`, `ASC_KEY_P8`: builds on GitHub's macOS 26 runner (Xcode 26) and uploads to TestFlight.
- Make the upload key once on your own computer (keep the file + passwords safe, never commit them):
  `keytool -genkeypair -v -keystore homelancer-upload.keystore -alias homelancer -keyalg RSA -keysize 2048 -validity 10000`
  then `base64 -w0 homelancer-upload.keystore` → secret `ANDROID_KEYSTORE_BASE64`.
- Web-only features that fall back on phones: voice input (browser speech recognition) → typing; the pilot-name box
  uses the in-game name screen; content packs are already inside the app.
