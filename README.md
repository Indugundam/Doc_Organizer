# Doc Manager

A simple Flutter app for organizing receipts, bills, and documents into
folders on your phone. Create folders (e.g. "Bills", "Hospital"), open one,
and add documents by scanning with the camera, picking a photo from the
gallery, or importing an existing file (PDF, etc.).

Everything is stored locally on the device, under the app's private storage
folder — there is no server, account, or internet connection involved. This
also means: uninstalling the app deletes its data, and there is currently no
cloud backup/sync.

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
flutter build apk --release
```

The output APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

Note: the release build is signed with Flutter's default debug key (not a
custom keystore), which is fine for installing on your own device but not
for publishing to the Play Store. If you ever want to publish this app,
set up a proper signing key first — see
https://docs.flutter.dev/deployment/android#signing-the-app.

## Project structure

- `lib/services/storage_service.dart` — all folder/file operations. Folders
  and documents are plain directories/files on disk
  (`<app documents dir>/DocManager/<folder>/<file>`), so the structure you
  see in the app is exactly what's on disk.
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
