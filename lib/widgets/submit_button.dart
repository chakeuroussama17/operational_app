import 'package:flutter/material.dart';

import '../config/constants.dart';

/// Full-width amber CTA button with a busy state while submitting.
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.label = 'SUBMIT LOG',
  });

  final VoidCallback? onPressed;
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppDimens.buttonHeight,
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.amber,
          disabledBackgroundColor: AppColors.amber.withValues(alpha: 0.6),
          foregroundColor: AppColors.navy,
          disabledForegroundColor: AppColors.navy,
          textStyle: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.cardRadius),
          ),
        ),
        icon: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.navy,
                ),
              )
            : const Icon(Icons.send_rounded, size: 26),
        label: Text(busy ? 'SUBMITTING…' : label),
      ),
    );
  }
}
