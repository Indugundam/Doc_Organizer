# Doc Manager

A simple Flutter app for organizing receipts, bills, and documents into
folders on your phone. Create folders (e.g. "Bills", "Hospital"), open one,
and add documents by scanning with the camera, picking a photo from the
gallery, or importing an existing file (PDF, etc.).

Everything is stored locally on the device, under the app's private storage
folder. Optionally, users can connect their Google account in Settings to
back up their folders to a `DocManager` folder in their own Google Drive.
Backup is one-way: Drive mirrors the device, and nothing is ever downloaded
to the device. There is no server of ours involved - the app talks to Google Drive
directly. Backup can be limited to Wi-Fi in Settings, so large videos don't
use mobile data.

## Installing the APK on your phone

1. Build it (see below) or copy the existing `build/app/outputs/flutter-apk/app-release.apk`.
2. Transfer the APK to your phone (e.g. via USB, email to yourself, Google Drive, etc.).
3. Open the file on your phone. Android will prompt to allow installing from
   this source ("Install unknown apps") — allow it for the app you used to
   open the file (e.g. Files, Chrome).
4. Tap Install. No further setup is needed — the app works fully offline.

## Rebuilding the APK

```
flutter pub get
flutter build apk --release --dart-define-from-file=config/google_oauth.json
```

The output APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

Note: the release build is signed with Flutter's default debug key (not a
custom keystore), which is fine for installing on your own device but not
for publishing to the Play Store. If you ever want to publish this app,
set up a proper signing key first — see
https://docs.flutter.dev/deployment/android#signing-the-app.

## Google Drive sync setup

Sync stays disabled (Settings shows "Not available in this build") until
the app has Google OAuth client IDs. They live in gitignored files, so each
clone needs its own copy:

1. In [Google Cloud Console](https://console.cloud.google.com/), create a
   project, enable the **Google Drive API**, and configure the **OAuth
   consent screen** (add yourself as a test user while it is in testing).
2. Under **APIs & Services -> Credentials**, create three OAuth client IDs:
   - **iOS** - bundle ID `com.gundamindu.docManager`
   - **Android** - package `com.gundamindu.doc_manager` plus the SHA-1 of
     the key the APK is signed with (`cd android && ./gradlew signingReport`)
   - **Web application** - no settings needed; Android uses its ID
3. Copy `config/google_oauth.example.json` to `config/google_oauth.json` and
   fill in the iOS and Web client IDs.
4. Copy `ios/Flutter/Secrets.example.xcconfig` to
   `ios/Flutter/Secrets.xcconfig` and set `GOOGLE_REVERSED_CLIENT_ID` to the
   iOS client ID reversed (`com.googleusercontent.apps.<...>`).
5. Build/run with `--dart-define-from-file=config/google_oauth.json` (the
   VS Code launch configs already do this).

## Project structure

- `lib/services/storage_service.dart` — all folder/file operations. Folders
  and documents are plain directories/files on disk
  (`<app documents dir>/DocManager/<folder>/<file>`), so the structure you
  see in the app is exactly what's on disk.
- `lib/services/sync_service.dart` — Google sign-in and one-way Drive backup.
- `lib/screens/home_screen.dart` — folder list (create/rename/delete).
- `lib/screens/folder_screen.dart` — documents inside a folder (scan with
  camera, pick from gallery, or import a file).
- `lib/screens/document_viewer_screen.dart` — view/delete a document, or
  open non-image files (PDFs, etc.) with the system viewer.
- `lib/theme/` — colors, spacing/radius scale, and the app's `ThemeData`
  (flat white app bars, rounded cards/dialogs/sheets, the bundled Inter
  font). Styled after InnCircles' internal design tokens.
- `lib/widgets/app_dialogs.dart` — shared name-prompt dialog, delete
  confirmation, and bottom-sheet action menu used across all screens.

Icons come from `fluentui_system_icons` (Fluent UI System Icons). The
`Inter` font is bundled locally under `assets/fonts/` — no runtime
download, works fully offline.
