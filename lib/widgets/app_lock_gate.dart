import 'dart:ui';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../services/app_lock_controller.dart';
import '../theme/app_spacing.dart';

/// Sits above the whole app (via MaterialApp.builder) and covers it with the
/// lock screen while locked, or a blur while the iOS app switcher is
/// showing it.
class AppLockGate extends StatelessWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLockController.locked,
      builder: (context, locked, _) => ValueListenableBuilder<bool>(
        valueListenable: AppLockController.obscured,
        builder: (context, obscured, _) => Stack(
          children: [
            // Keep the app mounted (so navigation state survives) but hidden
            // from screen readers while locked.
            ExcludeSemantics(excluding: locked, child: child),
            if (locked) const Positioned.fill(child: _LockScreen()),
            if (obscured && !locked)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prompt straight away so unlocking is a single touch/glance.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final error = await AppLockController.unlock();
    if (mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.lock_closed_24_regular,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.s5),
                Text('Doc Manager is locked', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  _error ?? 'Unlock with your fingerprint, face or device PIN.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _error != null
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.s7),
                FilledButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(FluentIcons.lock_open_24_regular),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
