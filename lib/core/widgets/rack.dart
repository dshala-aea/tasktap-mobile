// dart format width=100
import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

/// Was the aluminium-rail decoration painted behind the app shell's content — the van-racking
/// metaphor's own fixed backdrop. Vetro has no rail-and-drawer shell to bolt content to, so this
/// is a passthrough now: kept as a class (one call site, `home_shell.dart`, wraps its content in
/// it) purely so that site needs no change, not because anything still renders here.
class Rack extends StatelessWidget {
  const Rack({super.key, required this.child, this.top = 0, this.bottom = 0, this.visible = true});

  final Widget child;

  /// No longer consulted — nothing is painted behind [child] to inset around. Kept on the
  /// constructor so `home_shell.dart`'s call site needs no change.
  final double top;

  /// No longer consulted, for the same reason as [top].
  final double bottom;

  /// No longer consulted, for the same reason as [top].
  final bool visible;

  @override
  Widget build(BuildContext context) => child;
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

// RackLabel and ShadowBoard/SilhouettePainter used to live here — the label strip was never
// referenced by anything (dead code, removed), and the shadow-board empty-slot indicator moved to
// `empty_state.dart` as `CompactEmptyState`, the family it actually belongs with under Vetro. See
// that file's own doc comment for the Vetro replacement.
