import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App lock and recent-apps privacy settings, plus the live lock state.
///
/// Unlocking uses the phone's own screen lock (fingerprint, face, or the
/// device PIN/pattern/passcode as fallback), so there is no separate app PIN
/// to forget or store.
class AppLockController {
  AppLockController._();

  static const _lockKey = 'app_lock_enabled';
  static const _hideKey = 'hide_in_recents';
  static const _channel = MethodChannel('doc_manager/privacy');

  /// How long the app may sit in the background before it locks again.
  /// Long enough that taking a photo, picking a file or sharing (which all
  /// briefly leave the app) doesn't trigger the lock.
  static const gracePeriod = Duration(minutes: 1);

  static final lockEnabled = ValueNotifier<bool>(false);
  static final hideInRecents = ValueNotifier<bool>(false);

  /// Whether the lock screen is currently covering the app.
  static final locked = ValueNotifier<bool>(false);

  /// Whether the privacy blur is covering the app (iOS app switcher).
  static final obscured = ValueNotifier<bool>(false);

  /// Shown when the native unlock code is missing, e.g. after hot-restarting
  /// a build made before local_auth was added.
  static const _unavailableMessage =
      'Unlock is unavailable in this build. Fully reinstall the app.';

  static final _auth = LocalAuthentication();
  static DateTime? _backgroundedAt;
  static bool _authenticating = false;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    lockEnabled.value = prefs.getBool(_lockKey) ?? false;
    hideInRecents.value = prefs.getBool(_hideKey) ?? false;
    locked.value = lockEnabled.value;
    await _applyHideInRecents();
    AppLifecycleListener(onStateChange: _onLifecycleChange);
  }

  /// Turns the lock on only after a successful unlock, so nobody enables it
  /// on a phone without a screen lock (or someone else's phone) by mistake.
  /// Returns an error message to show, or null on success/cancel.
  static Future<String?> setLockEnabled(bool enabled) async {
    if (enabled) {
      final bool supported;
      try {
        supported = await _auth.isDeviceSupported();
      } on PlatformException {
        return _unavailableMessage;
      }
      if (!supported) {
        return 'Set up a screen lock (PIN, pattern, fingerprint or face) '
            'in your phone settings first.';
      }
      final result = await _authenticate('Confirm to turn on App lock');
      if (result != null) return result.isEmpty ? null : result;
    }
    lockEnabled.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lockKey, enabled);
    return null;
  }

  static Future<void> setHideInRecents(bool hide) async {
    hideInRecents.value = hide;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideKey, hide);
    await _applyHideInRecents();
  }

  /// Shows the system unlock prompt and removes the lock screen on success.
  /// Returns an error message to show, or null on success/cancel.
  static Future<String?> unlock() async {
    final result = await _authenticate('Unlock Doc Manager');
    if (result == null) locked.value = false;
    return result == null || result.isEmpty ? null : result;
  }

  /// Returns null on success, '' when the user cancelled, or an error
  /// message.
  static Future<String?> _authenticate(String reason) async {
    if (_authenticating) return '';
    _authenticating = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? null : '';
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.authInProgress => '',
        LocalAuthExceptionCode.noCredentialsSet =>
          'Set up a screen lock in your phone settings first.',
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          'Too many attempts. Try again later or use your device PIN.',
        _ => e.description ?? 'Could not verify your identity.',
      };
    } on PlatformException {
      return _unavailableMessage;
    } finally {
      _authenticating = false;
    }
  }

  static void _onLifecycleChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // iOS snapshots the app for the switcher right after this; cover it.
        // (Skipped while our own Face ID prompt is up, which also makes the
        // app inactive.)
        if (Platform.isIOS && hideInRecents.value && !_authenticating) {
          obscured.value = true;
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        obscured.value = false;
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (lockEnabled.value &&
            !_authenticating &&
            since != null &&
            DateTime.now().difference(since) >= gracePeriod) {
          locked.value = true;
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  static Future<void> _applyHideInRecents() async {
    // iOS is handled by the blur overlay; Android has a native switch.
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setHideInRecents', hideInRecents.value);
    } on MissingPluginException {
      // Running on an old build without the native side; nothing to do.
    }
  }
}
