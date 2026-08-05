import 'package:flutter/material.dart';

import '../config/constants.dart';

/// Full-bleed backdrop for the login/sign-up screens: the factory-floor
/// photo with a dark scrim so white text stays legible over any part of it,
/// darkest toward the bottom where the form sits. Wraps its own [Scaffold]
/// (transparent, so the photo shows through) and [SafeArea].
class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/background.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) =>
                const ColoredBox(color: Color(0xFF14101F)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // Just enough scrim to keep white text readable over the
                // brightest parts of the photo (the DCM-07 label, the ladle
                // glow) without crushing the photo to black — the mockup
                // keeps the factory floor visibly in frame throughout.
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  Colors.black.withValues(alpha: 0.40),
                  Colors.black.withValues(alpha: 0.62),
                ],
              ),
            ),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

/// The chevron + badge + wordmark that opens both auth screens.
class AuthLogoLockup extends StatelessWidget {
  const AuthLogoLockup({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ShaderMask(
          shaderCallback: (bounds) =>
              AppColors.authGradient.createShader(bounds),
          child: const Icon(
            Icons.keyboard_double_arrow_left_rounded,
            size: 30,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
        const SizedBox(width: 10),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.15,
            ),
            children: [
              TextSpan(text: 'HICOM\n'),
              TextSpan(
                text: 'Diecastings',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFD8D3E8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Welcome" / "Back!" — a plain white first line, gradient second line, the
/// headline every auth screen leads with.
class AuthHeadline extends StatelessWidget {
  const AuthHeadline({super.key, required this.line1, required this.line2});

  final String line1;
  final String line2;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 38,
      fontWeight: FontWeight.w800,
      height: 1.08,
      color: Colors.white,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line1, style: style),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) =>
              AppColors.authGradient.createShader(bounds),
          child: Text(line2, style: style),
        ),
      ],
    );
  }
}

/// A translucent "frosted glass" text field over the photo backdrop —
/// filled dark, hairline white border, white text and icons.
class AuthGlassField extends StatelessWidget {
  const AuthGlassField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.errorText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasError
                  ? AppColors.danger.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
            ),
            cursorColor: Colors.white,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Icon(
                icon,
                color: Colors.white.withValues(alpha: 0.65),
                size: 20,
              ),
              suffixIcon: suffixIcon,
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        ),
        if (hasError) const SizedBox(height: 6),
        if (hasError) AuthFieldError(message: errorText!),
      ],
    );
  }
}

/// Same chrome as [AuthGlassField], for a single-select dropdown
/// (Department) rather than free text.
class AuthGlassDropdown extends StatelessWidget {
  const AuthGlassDropdown({
    super.key,
    required this.hint,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.errorText,
  });

  final String hint;
  final IconData icon;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasError
                  ? AppColors.danger.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF241B3A),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.65),
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                icon: Icon(
                  icon,
                  color: Colors.white.withValues(alpha: 0.65),
                  size: 20,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
              hint: Text(
                hint,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
              ),
              items: [
                for (final option in options)
                  DropdownMenuItem(value: option, child: Text(option)),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
        if (hasError) const SizedBox(height: 6),
        if (hasError) AuthFieldError(message: errorText!),
      ],
    );
  }
}

/// The full-width gradient call-to-action ("LOG IN" / "SIGN UP").
class AuthGradientButton extends StatelessWidget {
  const AuthGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onPressed,
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.authGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.authPink.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.8,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Validation text under an auth field. Carries its own dark backing: at
/// 12.5px over a photo of a lit foundry, pink-on-whatever is a coin flip —
/// the pill is what makes it readable wherever the field happens to sit.
class AuthFieldError extends StatelessWidget {
  const AuthFieldError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 14,
              color: Color(0xFFFF8FB0),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF8FB0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
