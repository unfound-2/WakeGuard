import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Visual intent of an [showAppSnackBar] message.
enum AppSnackType { info, success, error }

/// Shows a snackbar that REPLACES any currently-visible one instead of queueing
/// behind it.
///
/// Flutter's default [ScaffoldMessenger] *queues* snackbars: while one is on
/// screen (the default lifetime is ~4s), a newly requested card waits in line
/// and only appears once the first times out. For rapid connection actions
/// (Sync Now, Reconnect, editing an alarm) that made the app feel like it was
/// "queuing the action itself" — the work had already run, but its feedback was
/// stuck behind the previous card. Clearing first makes the latest feedback
/// appear immediately.
void showAppSnackBar(
  BuildContext context,
  String message, {
  AppSnackType type = AppSnackType.info,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.of(context);
  // Drop whatever is currently showing (and anything queued) so this message
  // replaces it rather than waiting its turn.
  messenger.clearSnackBars();

  final Color? background = switch (type) {
    AppSnackType.success => AppColors.success,
    AppSnackType.error => Theme.of(context).colorScheme.error,
    AppSnackType.info => null,
  };

  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: background,
      behavior: SnackBarBehavior.floating,
      duration:
          duration ??
          (type == AppSnackType.error
              ? const Duration(seconds: 3)
              : const Duration(seconds: 2)),
    ),
  );
}
