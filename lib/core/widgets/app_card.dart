import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Standard TaskTap card — BG1 bg, 14 px radius, default 16 px padding, SH shadow.
///
/// ```dart
/// AppCard(child: Text('Hello'));
/// AppCard.pressable(onTap: () {}, child: Text('Tap me'));
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

  static const double _radius = 14;
  static const EdgeInsets _defaultPadding = EdgeInsets.all(16);

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? context.colors.bg1;
    final border = borderColor ?? context.colors.borderMedium;

    final br = BorderRadius.circular(_radius);

    final decoration = BoxDecoration(
      color: bg,
      borderRadius: br,
      border: Border.all(color: border, width: 0.5),
      boxShadow: context.colors.shadow,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: Ink(
          decoration: decoration,
          child: InkWell(
            onTap: onTap,
            borderRadius: br,
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
    final p = padding ?? _defaultPadding;
    return Padding(padding: p, child: child);
  }
}

/// Glass card for use on dark hero sections.
///
/// White-translucent gradient, 0.5 px white border, SH_INSET, 14 px radius.
///
/// ```dart
/// GlassCard(child: Text('glass'));
/// GlassCard.pressable(onTap: () {}, child: Text('tap'));
/// ```
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
  });

  const GlassCard.pressable({
    super.key,
    required this.child,
    required VoidCallback this.onTap,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  static const double _radius = 14;
  static const EdgeInsets _defaultPadding = EdgeInsets.all(16);

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(_radius);

    final decoration = BoxDecoration(
      borderRadius: br,
      border: Border.all(color: Colors.white.withAlpha(128), width: 0.5),
      boxShadow: context.colors.shadowInset,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withAlpha(51),  // ~0.20 opacity
          Colors.white.withAlpha(20),  // ~0.08 opacity
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: Ink(
          decoration: decoration,
          child: InkWell(
            onTap: onTap,
            borderRadius: br,
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
    final p = padding ?? _defaultPadding;
    return Padding(padding: p, child: child);
  }
}
