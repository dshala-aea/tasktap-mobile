import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
