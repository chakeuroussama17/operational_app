import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/constants.dart';

/// Large-touch-target text field with a label above it.
///
/// Free-text input; set [upperCase] to auto-capitalise entries such as line
/// codes (F31, ASSY). Required unless [required] is false.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.required = true,
    this.upperCase = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool required;
  final bool upperCase;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label: label, required: required),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: upperCase
              ? TextCapitalization.characters
              : TextCapitalization.none,
          inputFormatters: [if (upperCase) UpperCaseTextFormatter()],
          style: TextStyle(
            fontSize: AppDimens.fieldFontSize,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(hintText: hint),
          validator: (value) {
            if (required && (value == null || value.trim().isEmpty)) {
              return '$label is required';
            }
            return null;
          },
        ),
      ],
    );
  }
}

/// Numeric field: accepts only digits (and one decimal point when
/// [allowDecimal] is true) and validates the value is a number >= 0.
class AppNumberField extends StatelessWidget {
  const AppNumberField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.required = true,
    this.allowDecimal = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool required;

  /// Enable for rate fields such as LOR%; leave off for piece counts.
  final bool allowDecimal;

  /// Fires on every keystroke — for screens that show something derived from
  /// this field (a running total, a live percentage) as it is typed.
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label: label, required: required),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              allowDecimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
            ),
          ],
          style: TextStyle(
            fontSize: AppDimens.fieldFontSize,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(hintText: hint ?? '0'),
          onChanged: onChanged,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) {
              return required ? '$label is required' : null;
            }
            final parsed = num.tryParse(text);
            if (parsed == null) {
              return 'Enter a valid number';
            }
            if (parsed < 0) {
              return 'Must be 0 or more';
            }
            return null;
          },
        ),
      ],
    );
  }
}

/// Field caption shown above inputs, with a red asterisk when required.
class FieldLabel extends StatelessWidget {
  const FieldLabel({super.key, required this.label, this.required = true});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: label,
        style: TextStyle(
          fontSize: AppDimens.labelFontSize,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.2,
        ),
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: AppColors.danger),
            ),
        ],
      ),
    );
  }
}

/// Forces typed characters to upper case (for line/part codes).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
