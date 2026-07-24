import 'package:flutter/material.dart';

import '../config/constants.dart';

/// Success confirmation shown after a row is logged: a checkmark dialog that
/// auto-dismisses, after which the caller returns to the home screen.
Future<void> showSubmissionSuccess(BuildContext context) async {
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
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 84,
              ),
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
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
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
