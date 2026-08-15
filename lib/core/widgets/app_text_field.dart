import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';
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
  }) : keyboardType = TextInputType.multiline,
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
    // The label sits above the field as plain text, not inside it as a Material floating label.
    //
    // The floating label is the single loudest "this is a 2015 Android form" tell: the label
    // starts as placeholder text, animates up on focus and notches itself into the outline. It
    // also makes a filled, fully-outlined box mandatory to have somewhere to notch *into*, which
    // is why every field in the app carried both a fill and a 1px box on all four sides.
    //
    // Static labels read the same whether the field is empty, focused or full — which matters on
    // a form being filled in a van — and they let the field itself be quiet: a filled inset with
    // a hairline, and the yellow only when it has focus.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFieldLabel(label: label, enabled: enabled),
        const SizedBox(height: 6),
        TextFormField(
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
            hintText: hint,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            isDense: true,
          ),
        ),
      ],
    );
  }
}


/// Puts a static label above any input widget — a dropdown, a date picker, a segmented control.
///
/// Exists so the label treatment is one decision rather than one per widget type. Without it the
/// dropdowns in the admin forms would keep floating a Material label into a border notch while
/// the text fields beside them label from above, which reads worse than either choice made
/// consistently.
class AppFieldShell extends StatelessWidget {
  const AppFieldShell({
    super.key,
    required this.label,
    required this.child,
    this.enabled = true,
  });

  final String label;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFieldLabel(label: label, enabled: enabled),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// The static label above a field.
///
/// Small, heavy and slightly tracked — the same voice as the other micro-labels in the app
/// ("SESSIONI DI OGGI", the timbra date) rather than a shrunken copy of body text. A trailing
/// asterisk is coloured, so "required" is visible at a glance down a column of labels instead of
/// being one more grey character.
class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel({super.key, required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final required = label.trimRight().endsWith('*');
    final text = required ? label.trimRight().substring(0, label.trimRight().length - 1).trim() : label;
    final style = TextStyle(
      fontFamily: 'Manrope',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: enabled ? context.colors.inkMuted : context.colors.inkDisabled,
    );

    return Text.rich(
      TextSpan(
        text: text.toUpperCase(),
        style: style,
        children: required
            ? [TextSpan(text: ' *', style: style.copyWith(color: context.colors.red))]
            : null,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
