import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Look of an [AppToast]: the status icon and its color.
enum ToastType {
  success(FluentIcons.checkmark_circle_24_filled, AppColors.success500),
  error(FluentIcons.dismiss_circle_24_filled, AppColors.error500),
  warning(FluentIcons.warning_24_filled, AppColors.warning500),
  info(FluentIcons.info_24_filled, AppColors.primary500),
  standard(null, null);

  const ToastType(this.icon, this.color);

  final IconData? icon;
  final Color? color;
}

/// Floating status message that slides up from the bottom, used instead of
/// Material snack bars for success and error feedback across the app.
///
/// Only one toast shows at a time; a new one replaces the current one. It
/// belongs to the page it was shown on: it hides after long enough to read
/// it, when swiped down or closed, or as soon as the user moves to another
/// page (see [navigatorObserver]). Toasts are shown on the root navigator's
/// overlay, so no BuildContext is needed.
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static GlobalKey<_ToastState>? _key;

  /// Register on the MaterialApp so a toast doesn't follow the user to the
  /// next page.
  static final NavigatorObserver navigatorObserver = _ToastRouteObserver();

  /// Shows [message]. Without a [duration], it stays up for as long as it
  /// takes to read: 2.5 seconds for a few words, up to 6 for long ones.
  static void show(
    String message, {
    ToastType type = ToastType.standard,
    Duration? duration,
    bool showClose = true,
  }) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _remove();
    // Created once per toast, outside the builder: the overlay rebuilds the
    // entry whenever the app rebuilds, and a new key each time would replay
    // the toast from the start.
    final key = GlobalKey<_ToastState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Toast(
        key: key,
        message: message,
        type: type,
        duration: duration ?? _readingTime(message),
        showClose: showClose,
        onDismissed: () {
          if (_entry == entry) _remove();
        },
      ),
    );
    _entry = entry;
    _key = key;
    overlay.insert(entry);
  }

  static void success(String message) => show(message, type: ToastType.success);

  /// Shows [error] - an exception or a message - without the "Exception: "
  /// prefix Dart adds.
  static void error(Object error) => show(
    error.toString().replaceFirst('Exception: ', ''),
    type: ToastType.error,
  );

  static void warning(String message) => show(message, type: ToastType.warning);

  static void info(String message) => show(message, type: ToastType.info);

  /// Hides the current toast, if any, with its exit animation.
  static void dismiss() {
    final state = _key?.currentState;
    if (state != null) {
      state._dismiss();
    } else {
      _remove();
    }
  }

  static Duration _readingTime(String message) =>
      Duration(milliseconds: (1500 + message.length * 50).clamp(2500, 6000));

  static void _remove() {
    _entry?.remove();
    _entry = null;
    _key = null;
  }
}

/// Hides the toast when a page is pushed, popped or replaced. Dialogs and
/// bottom sheets don't count, so a toast shown just before or after one
/// stays put.
class _ToastRouteObserver extends NavigatorObserver {
  void _changed(Route<dynamic>? route) {
    if (route is PageRoute) AppToast.dismiss();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _changed(newRoute);
}

class _Toast extends StatefulWidget {
  const _Toast({
    super.key,
    required this.message,
    required this.type,
    required this.duration,
    required this.showClose,
    required this.onDismissed,
  });

  final String message;
  final ToastType type;
  final Duration duration;
  final bool showClose;
  final VoidCallback onDismissed;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final _slide = Tween(
    begin: const Offset(0, 0.6),
    end: Offset.zero,
  ).animate(_curve);
  late final _scale = Tween(begin: 0.96, end: 1.0).animate(_curve);

  /// Pops the status icon in with a slight overshoot just after the toast
  /// lands.
  late final _iconScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 1, curve: Curves.easeOutBack),
    reverseCurve: Curves.easeIn,
  );

  Timer? _timer;

  /// How far the toast has been dragged down by the user.
  double _drag = 0;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _iconScale.dispose();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _timer?.cancel();
    await _controller.reverse();
    widget.onDismissed();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _timer?.cancel();
    // Follows the finger downwards, resists a little upwards.
    setState(() => _drag = (_drag + details.delta.dy).clamp(-12.0, 200.0));
  }

  void _onDragEnd(DragEndDetails details) {
    if (_drag > 32 || details.velocity.pixelsPerSecond.dy > 400) {
      _dismiss();
    } else {
      setState(() => _drag = 0);
      _startTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    // Clear of the keyboard, the home indicator and floating action buttons.
    final bottom = media.viewInsets.bottom + media.viewPadding.bottom + 88;
    final icon = widget.type.icon;
    final foreground = dark ? AppColors.darkText : AppColors.neutral1300;

    return Positioned(
      left: AppSpacing.s5,
      right: AppSpacing.s5,
      bottom: bottom,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: FadeTransition(
            opacity: _curve,
            child: SlideTransition(
              position: _slide,
              child: ScaleTransition(
                scale: _scale,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: _drag == 0 ? 180 : 0),
                  curve: Curves.easeOut,
                  transform: Matrix4.translationValues(0, _drag, 0),
                  child: Opacity(
                    opacity: (1 - _drag.clamp(0, 120) / 160).toDouble(),
                    child: GestureDetector(
                      onVerticalDragUpdate: _onDragUpdate,
                      onVerticalDragEnd: _onDragEnd,
                      child: Semantics(
                        liveRegion: true,
                        container: true,
                        child: Material(
                          color: dark
                              ? AppColors.darkSurfaceAlt
                              : AppColors.neutral100,
                          elevation: 6,
                          shadowColor: Colors.black.withValues(
                            alpha: dark ? 0.5 : 0.18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.medium,
                            ),
                            side: BorderSide(
                              color: dark
                                  ? AppColors.darkBorder
                                  : AppColors.neutral300,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              AppSpacing.s5,
                              AppSpacing.s4,
                              widget.showClose ? AppSpacing.s2 : AppSpacing.s5,
                              AppSpacing.s4,
                            ),
                            child: Row(
                              children: [
                                if (icon != null) ...[
                                  ScaleTransition(
                                    scale: _iconScale,
                                    child: Icon(
                                      icon,
                                      size: 22,
                                      color: widget.type.color,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.s4),
                                ],
                                Expanded(
                                  child: Text(
                                    widget.message,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: foreground,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (widget.showClose)
                                  IconButton(
                                    tooltip: 'Dismiss',
                                    onPressed: _dismiss,
                                    icon: Icon(
                                      FluentIcons.dismiss_20_regular,
                                      size: 18,
                                      color: foreground.withValues(alpha: 0.7),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
