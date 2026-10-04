import 'dart:io';

/// OAuth client IDs for Google Drive sync, created in Google Cloud Console
/// (APIs & Services -> Credentials) for a project with the Drive API enabled.
///
/// They are kept out of the repo and injected at build time from the
/// gitignored `config/google_oauth.json` (copy `google_oauth.example.json`):
///
///     flutter run --dart-define-from-file=config/google_oauth.json
///
/// (the VS Code launch configs already pass this).
///
/// - [iosClientId]: the "iOS" OAuth client for this app's bundle ID. Its
///   reversed form also goes in the gitignored `ios/Flutter/Secrets.xcconfig`
///   for the sign-in callback URL scheme.
/// - [webClientId]: the "Web application" OAuth client. Android needs it as
///   the server client ID; the "Android" OAuth client (package name + SHA-1)
///   only has to exist in the same project, it is never referenced in code.
///
/// While these are empty, sync is disabled and Settings says so.
class GoogleConfig {
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static bool get isConfigured {
    if (Platform.isIOS) return iosClientId.isNotEmpty;
    if (Platform.isAndroid) return webClientId.isNotEmpty;
    return false;
  }
}
