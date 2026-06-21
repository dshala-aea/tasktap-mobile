import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_text_styles.dart';

/// TaskTap branded text input.
///
/// Wraps [TextFormField] with the app's input decoration theme.
/// Pass [validator] for form integration; use [controller] or [onChanged]
/// for state management.
///
/// ```dart
/// AppTextField(
///   label: 'Email',
///   hint: 'technician@company.com',
///   keyboardType: TextInputType.emailAddress,
///   controller: _emailController,
/// );
///
/// AppTextField.multiline(
///   label: 'Note',
///   hint: 'Aggiungi una nota...',
///   controller: _noteController,
///   maxLines: 4,
/// );
/// ```
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.onChanged,
    this.onEditingComplete,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.focusNode,
    this.autofillHints,
    this.initialValue,
  });

  /// Multiline convenience constructor.
  const AppTextField.multiline({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.onChanged,
    this.onEditingComplete,
    this.validator,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 4,
    this.maxLength,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.focusNode,
    this.initialValue,
  })  : keyboardType = TextInputType.multiline,
        textInputAction = TextInputAction.newline,
        obscureText = false,
        autofillHints = null;

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;
  final String? initialValue;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      focusNode: focusNode,
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      style: AppTextStyles.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
