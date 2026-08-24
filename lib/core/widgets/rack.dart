// dart format width=100
import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

/// The three primitives of the van-racking world: the [Rack] rail, the [RackCell] drawer front,
/// and the [ShadowBoard] cut silhouette.
///
/// ## Why the rail costs no layout
///
/// [Rack] paints the extrusion *inside the gutter the screens already have*. Every screen in this
/// app indents its content by `AppSpacing.pagePadding` (19); the rail occupies x 8–12 of that,
/// leaving `AppRack.railToCell` clear before a cell begins. So wrapping a screen in a [Rack] moves
/// nothing sideways and reflows nothing — it is a decoration, not a container. That property is
/// the whole reason this world could be adopted across forty-six screens instead of six.

/// Paints the aluminium extrusion behind a screen's content.
///
/// Fixed, not scrolling: in a van the rail is bolted to the body and the drawers move past it.
/// Wrap the scrollable, not the individual list.
class Rack extends StatelessWidget {
  const Rack({super.key, required this.child, this.top = 0, this.bottom = 0, this.visible = true});

  final Widget child;

  /// Inset from the top of the rack area — set this to clear a fixed header so the rail starts
  /// where the content does.
  final double top;

  /// Inset from the bottom — set this to clear the floating nav pill.
  final double bottom;

  /// A screen with no rack content (a full-bleed hero, a signature capture) turns the rail off
  /// rather than drawing structure that holds nothing.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return child;

    return Stack(
      children: [
        Positioned(
          left: AppRack.railInset,
          top: top,
          bottom: bottom,
          width: AppRack.railWidth,
          child: const _RailBar(),
        ),
        child,
      ],
    );
  }
}

class _RailBar extends StatelessWidget {
  const _RailBar();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Anodized alu is not a flat grey: it carries a machined highlight down one edge and
        // falls away across its width. Four device-independent pixels is enough to show it, and
        // showing it is what stops the rail reading as a stray 4dp divider.
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [c.railHighlight, c.railSurface, c.railSurface],
          stops: const [0.0, 0.45, 1.0],
        ),
        borderRadius: BorderRadius.circular(AppRack.railHighlight),
      ),
    );
  }
}

/// A drawer front on the rail: the app's universal container.
///
/// Depth is a hairline border, never a drop shadow — a shadow disappears in direct sun, a border
/// does not. [strapped] (or an explicit [ledgeColor]) marks state by recoloring and thickening
/// that same border, not by gluing a separate colored bar to the leading edge.
///
/// ## Why the ledge bar is gone (2026-08-24)
///
/// This used to carry a 6dp graphite-or-accent bar down the leading edge — a second material
/// glued onto the card rather than a property of its own edge. Direct user feedback: it read as
/// two colors stitched together, not one considered surface, and it was the single biggest thing
/// making the app look dated. A colored *border* says the same thing (this row is strapped,
/// selected, or overdue) as a property of the card's own outline, the way Stripe, Linear, and
/// Vercel all mark a selected or flagged row — not as a second block of material sitting on it.
///
/// [strapped] is still the app's single most important state change: *this one needs you*. The
/// selected day, the ticket you are on, a draft still unfinished. Not a live/running clock —
/// that's [LiveDot], deliberately a different mark, or the accent would be spent on the ordinary
/// state of most of a shift.
class RackCell extends StatelessWidget {
  const RackCell({
    super.key,
    required this.child,
    this.strapped = false,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.background,
    this.semanticLabel,
    this.ledgeColor,
    this.minHeight = AppRack.cellMinHeight,
    this.flush = true,
  });

  final Widget child;

  /// Selected, priority, or still-needs-finishing. Turns the ledge the brand accent. Not for a
  /// live/running state: see [LiveDot].
  final bool strapped;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;

  /// Defaults to the bone label card. Override only for a cell that is deliberately a different
  /// material — a dark summary panel, a danger cell.
  final Color? background;

  final String? semanticLabel;

  /// Overrides the border colour for a cell whose state is neither ordinary nor live — a rejected
  /// report, an overdue job. [strapped] still wins.
  final Color? ledgeColor;

  final double minHeight;

  /// False for a cell that is not on a rail: a sheet, a dialog, a standalone panel. Rounds all
  /// four corners instead of butting the leading edge.
  final bool flush;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = flush ? AppRack.cellShape : AppRack.freeShape;
    final accent = strapped ? AppColors.Y : ledgeColor;

    final body = Padding(padding: padding ?? AppRack.cellPadding, child: child);

    Widget inner(Widget bodyChild) =>
        ConstrainedBox(constraints: BoxConstraints(minHeight: minHeight), child: bodyChild);

    final decoration = BoxDecoration(
      color: background ?? c.labelCard,
      borderRadius: shape,
      // A plain hairline in the ordinary case; strapped/ledgeColor thickens and recolors the same
      // border rather than adding a second material. See the class doc for why.
      border: Border.all(color: accent ?? c.borderLight, width: accent != null ? 1.5 : 1),
    );

    if (onTap == null && onLongPress == null) {
      final cell = DecoratedBox(decoration: decoration, child: inner(body));
      return semanticLabel != null ? Semantics(label: semanticLabel, child: cell) : cell;
    }

    // `Ink`, not a `DecoratedBox` under an overlay.
    //
    // A cell's fill is opaque, so an InkWell layered *beneath* it paints a splash nobody sees, and
    // one layered *over* it eats every tap meant for something inside the cell — a status chip, a
    // stepper, a row's own trailing action. `Ink` resolves both: it hands the decoration to the
    // Material layer, so the splash lands above the fill and below the content, and the content
    // keeps first claim on the gesture.
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: decoration,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: shape,
            child: inner(body),
          ),
        ),
      ),
    );
  }
}

/// The label strip at the top of a cell: the printed card in its window.
///
/// Sora for the label because it is the thing you read from two feet away to decide whether this
/// is the cell you want; Manrope for everything inside the cell, which you read once you have
/// decided. That is the whole reason this app keeps two faces.
class RackLabel extends StatelessWidget {
  const RackLabel({super.key, required this.label, this.meta, this.leading});

  final String label;

  /// The right end of the strip: a status, a time, a count.
  final Widget? meta;

  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: AppRack.labelStripHeight,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.ink),
            ),
          ),
          if (meta != null) ...[const SizedBox(width: 8), meta!],
        ],
      ),
    );
  }
}

/// A cut silhouette: the shape of what belongs here and is not here.
///
/// This is the world's answer to the empty state, and it is a deliberately different claim than
/// "nothing here". A shadow board says *something is missing and this is its outline* — which is
/// exactly the difference between "you have no queued reports" and "the queue failed to load",
/// the distinction this app's third product principle exists to protect.
///
/// Give it a [reason] when the emptiness is a failure rather than a fact.
class ShadowBoard extends StatelessWidget {
  const ShadowBoard({
    super.key,
    required this.label,
    this.reason,
    this.icon,
    this.action,
    this.height = 96,
  });

  /// What belongs in this slot, named as the object it is: "nessun rapportino in coda".
  final String label;

  /// Why it is absent, when absence is not the normal case. Renders under the label in the
  /// muted ink, never in red — an empty rack is not an error.
  final String? reason;

  final IconData? icon;
  final Widget? action;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: reason == null ? label : '$label. $reason',
      // Without this the board is announced three times: once as this composed phrase, then again
      // as each Text's own node. A screen-reader user hears the whole empty state twice over
      // before reaching the action.
      excludeSemantics: true,
      child: CustomPaint(
        painter: SilhouettePainter(color: c.silhouette),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 22, color: c.silhouette),
                  const SizedBox(height: 8),
                ],
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.inkMuted),
                ),
                if (reason != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    reason!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.inkFaint),
                  ),
                ],
                if (action != null) ...[const SizedBox(height: 12), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a dashed rounded-rectangle outline in the rack's corner language — the cut line of a
/// shadow board. The single owner of this drawing; [ShadowBoard] and `EmptyState` both use it so
/// the two outlines cannot drift apart.
class SilhouettePainter extends CustomPainter {
  const SilhouettePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppRack.silhouetteStroke;

    // Deflate by half the stroke: a path laid on the exact bounds paints half its width outside
    // the widget and gets clipped to a 0.75dp line on one side.
    final inset = AppRack.silhouetteStroke / 2;
    final rect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(inset),
      const Radius.circular(AppRack.cellRadius),
    );

    // Walk the rounded rect's outline and lay dashes along it. `PathMetric.extractPath` is the
    // only way to dash an arbitrary path in Flutter; doing it per-edge would break the corners.
    final dash = AppRack.silhouetteDash[0];
    final gap = AppRack.silhouetteDash[1];
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + dash).clamp(0.0, metric.length)),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(SilhouettePainter oldDelegate) => oldDelegate.color != color;
}
