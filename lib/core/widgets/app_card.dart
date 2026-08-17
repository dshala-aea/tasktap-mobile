import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

import 'rack.dart';

/// The app's container, now a drawer front on the rail rather than a floating card.
///
/// The public API is unchanged on purpose. Thirty-three call sites across thirteen screens say
/// `AppCard(child: …)`, and every one of them means "a block of content at the page gutter" —
/// which is exactly what a cell is. Rebuilding the primitive rather than the call sites is what
/// let the world reach the whole app.
///
/// What changed underneath:
/// - Bone [AppPalette.labelCard] instead of the neutral `bg1`. This is the one warm surface in
///   the app and it is what makes a screen recognisable with the content stripped out.
/// - A graphite ledge down the leading edge instead of a drop shadow. A soft 10%-black shadow is
///   invisible on a dark ground and washes out entirely in direct sun; a 6dp bar does not.
/// - Square on the rail edge, machined 6dp on the other three. A card floats; a drawer is mounted.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderColor,
    this.backgroundColor,
    this.strapped = false,
    this.flush = true,
  });

  /// Tappable variant with ink ripple.
  const AppCard.pressable({
    super.key,
    required this.child,
    required VoidCallback this.onTap,
    this.padding,
    this.borderColor,
    this.backgroundColor,
    this.strapped = false,
    this.flush = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// Retained from the previous API. A card that overrode its border was marking a state; that
  /// now reads better on the ledge, so this is routed there.
  final Color? borderColor;

  final Color? backgroundColor;

  /// Live, running, or selected — turns the ledge brand yellow.
  final bool strapped;

  /// False for a cell that is not on the rail: inside a sheet, a dialog, or a nested panel.
  final bool flush;

  static const EdgeInsets _defaultPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);

  @override
  Widget build(BuildContext context) {
    return RackCell(
      onTap: onTap,
      strapped: strapped,
      flush: flush,
      background: backgroundColor ?? context.colors.labelCard,
      ledgeColor: borderColor,
      padding: padding ?? _defaultPadding,
      minHeight: 0,
      child: child,
    );
  }
}

/// Glass card for use on a dark hero.
///
/// Kept as a distinct material rather than folded into [AppCard]: it sits on the dashboard's dark
/// gradient, where a bone cell would punch a hole. It takes the rack's corner language so it does
/// not read as a survivor from the previous system.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.strapped = false,
  });

  const GlassCard.pressable({
    super.key,
    required this.child,
    required VoidCallback this.onTap,
    this.padding,
    this.strapped = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// A running job on the hero. Straps the glass cell in brand yellow, same grammar as everywhere
  /// else — the technician should not have to learn a second vocabulary for the dashboard.
  final bool strapped;

  static const EdgeInsets _defaultPadding = EdgeInsets.all(16);

  @override
  Widget build(BuildContext context) {
    final br = AppRack.freeShape;

    final decoration = BoxDecoration(
      borderRadius: br,
      border: Border.all(color: Colors.white.withAlpha(128), width: 0.5),
      boxShadow: context.colors.shadowInset,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withAlpha(51), // ~0.20 opacity
          Colors.white.withAlpha(20), // ~0.08 opacity
        ],
      ),
    );

    Widget content = Padding(padding: padding ?? _defaultPadding, child: child);

    if (strapped) {
      // Stack, not a stretched Row: a Row with `CrossAxisAlignment.stretch` demands a bounded
      // height, and this card lives in scrollable columns that offer none. The Positioned strap
      // takes its height from the Stack, which is sized by the content.
      content = Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: AppRack.strapWidth),
            child: content,
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: AppRack.strapWidth,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFFFF10E),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppRack.cellRadius),
                  bottomLeft: Radius.circular(AppRack.cellRadius),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: Ink(
          decoration: decoration,
          child: InkWell(onTap: onTap, borderRadius: br, child: content),
        ),
      );
    }

    return DecoratedBox(decoration: decoration, child: content);
  }
}
