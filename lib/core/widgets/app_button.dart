import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Button variant.
enum AppButtonVariant {
  /// Filled brand yellow — primary actions.
  primary,

  /// Outlined — secondary / neutral actions.
  secondary,

  /// Text only — low-emphasis / inline.
  ghost,

  /// Filled destructive red — irreversible actions.
  danger,
}

/// TaskTap brand button.
///
/// ```dart
/// AppButton(label: 'Invia rapportino', onPressed: _submit);
/// AppButton.secondary(label: 'Annulla', onPressed: _cancel);
/// AppButton.ghost(label: 'Salta', onPressed: _skip);
/// AppButton.danger(label: 'Elimina', onPressed: _delete);
/// ```
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.expand = true,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = false,
  }) : variant = AppButtonVariant.ghost;

  const AppButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
  }) : variant = AppButtonVariant.danger;

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final AppButtonVariant variant;

  /// When true, button stretches to full available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = _buildChild();

    Widget button = switch (variant) {
      AppButtonVariant.primary => _PrimaryButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      AppButtonVariant.secondary => _SecondaryButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      AppButtonVariant.ghost => _GhostButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      AppButtonVariant.danger => _DangerButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
    };

    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }

  Widget _buildChild() {
    if (isLoading) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon!,
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: AppTextStyles.labelLarge),
        ],
      );
    }
    return Text(label, style: AppTextStyles.labelLarge);
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.child, this.onPressed});
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
        disabledBackgroundColor: AppColors.brand.withAlpha(120),
        disabledForegroundColor: AppColors.onBrand.withAlpha(120),
      ),
      child: child,
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.child, this.onPressed});
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: child,
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.child, this.onPressed});
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: child,
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.child, this.onPressed});
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.error,
        foregroundColor: AppColors.onError,
        disabledBackgroundColor: AppColors.error.withAlpha(120),
        disabledForegroundColor: AppColors.onError.withAlpha(120),
      ),
      child: child,
    );
  }
}
