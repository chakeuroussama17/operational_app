import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/constants.dart';

/// A check mark that springs in rather than simply appearing — the moment of
/// "it saved" is the one the whole form exists for, and it should register.
class _PoppingCheck extends StatelessWidget {
  const _PoppingCheck({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Icon(Icons.check_circle_rounded, color: color, size: size),
    );
  }
}

/// Success confirmation shown after a row is logged: a checkmark dialog that
/// auto-dismisses, after which the caller returns to the home screen.
Future<void> showSubmissionSuccess(BuildContext context) async {
  // Felt as well as seen: gloves, noise and a glance away from the screen
  // all make a visual-only confirmation easy to miss on the floor.
  HapticFeedback.mediumImpact();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      // Auto-close after a short beat; manual OK not needed on success.
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
      });
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PoppingCheck(size: 84, color: AppColors.success),
              const SizedBox(height: 16),
              Text(
                'Logged successfully',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Lightweight success confirmation used by the casting entry screen,
/// which stays open after saving (supervisors keep adding slots all shift).
void showSaveSuccessSnack(
  BuildContext context, {
  String message = 'Saved successfully',
}) {
  HapticFeedback.mediumImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const _PoppingCheck(size: 24, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

/// Error banner with a Retry action; the form keeps its values.
void showSubmissionError(
  BuildContext context, {
  required String message,
  required VoidCallback onRetry,
}) {
  // A different, heavier buzz than success, so the two can't be confused
  // by feel alone.
  HapticFeedback.heavyImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 15, color: Colors.white),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'RETRY',
          textColor: AppColors.amber,
          onPressed: onRetry,
        ),
      ),
    );
}
