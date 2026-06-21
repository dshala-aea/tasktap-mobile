import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// TaskTap branded card.
///
/// A clean, white card with a subtle border and rounded corners.
/// Use [AppCard.pressable] when the entire card is tappable.
///
/// ```dart
/// AppCard(
///   child: ListTile(title: Text('Rapportino #42')),
/// );
///
/// AppCard.pressable(
///   onTap: () => context.go('/reports/42'),
///   child: ListTile(title: Text('Rapportino #42')),
/// );
/// ```
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderColor,
    this.backgroundColor,
  });

  /// Tappable variant with ink ripple.
  const AppCard.pressable({
    super.key,
    required this.child,
    required VoidCallback this.onTap,
    this.padding,
    this.borderColor,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.surface;
    final border = borderColor ?? AppColors.outline;

    final decoration = BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      border: Border.all(color: border),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: Ink(
          decoration: decoration,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: _content(),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: decoration,
      child: _content(),
    );
  }

  Widget _content() {
    if (padding != null) {
      return Padding(padding: padding!, child: child);
    }
    return child;
  }
}
