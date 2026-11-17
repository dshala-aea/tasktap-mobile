// dart format width=100
// lib/features/cantiere/cantiere_design.dart
//
// The small visual vocabulary of the cantiere detail / map / close-sheet design
// (prototypes/cantiere-design.html): Archivo Narrow display titles, IBM Plex Mono kickers and
// readouts, 1px rules, 2px corners, no shadows. Every colour is an AppPalette token; sizes are the
// mockup's own, so they live here as literals rather than being rounded onto the app-wide text
// scale.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_rack.dart';

// ── Text styles ──────────────────────────────────────────────────────────────

/// Archivo Narrow display text (`--display`).
TextStyle cantiereDisplay(
  BuildContext context,
  double size, {
  FontWeight weight = FontWeight.w600,
  double letterSpacing = 0,
  double? height,
  Color? color,
}) => TextStyle(
  fontFamily: 'Archivo Narrow',
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  height: height,
  color: color ?? context.colors.ink,
);

/// Archivo body text (`--body`).
TextStyle cantiereBody(
  BuildContext context,
  double size, {
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
}) => TextStyle(
  fontFamily: 'Archivo',
  fontSize: size,
  fontWeight: weight,
  height: height,
  color: color ?? context.colors.ink,
);

/// IBM Plex Mono (`--mono`), tabular figures.
TextStyle cantiereMono(
  BuildContext context,
  double size, {
  FontWeight weight = FontWeight.w500,
  double letterSpacing = 0,
  Color? color,
}) => TextStyle(
  fontFamily: 'IBM Plex Mono',
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  fontFeatures: const [FontFeature.tabularFigures()],
  color: color ?? context.colors.inkMuted,
);

/// `.mini`: mono 9, tracking .1em, uppercase, muted.
TextStyle cantiereMini(BuildContext context) => cantiereMono(context, 9, letterSpacing: 0.9);

/// `.timer`: mono 22 (or [size]), tracking -.03em, red, tabular.
TextStyle cantiereTimer(BuildContext context, {double size = 22}) =>
    cantiereMono(context, size, letterSpacing: -0.03 * size, color: context.colors.accentInk);

// ── Surfaces ─────────────────────────────────────────────────────────────────

/// `.card`: sheet fill, 1px rule, 2px radius, no shadow.
class CantiereCard extends StatelessWidget {
  const CantiereCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRack.freeShape,
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 1px rule line (`--rule`).
class CantiereRule extends StatelessWidget {
  const CantiereRule({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1,
    width: double.infinity,
    child: ColoredBox(color: context.colors.divider),
  );
}

// ── Section head ─────────────────────────────────────────────────────────────

/// `.section` + `.section-head`: 18px above, 17/600 display title on the left, an 8.5 mono
/// uppercase muted note or link on the right, baseline-aligned, 8px below.
class CantiereSection extends StatelessWidget {
  const CantiereSection({
    super.key,
    required this.title,
    required this.child,
    this.note,
    this.onNoteTap,
    this.noteWidget,
    this.first = false,
  });

  final String title;
  final Widget child;
  final String? note;
  final VoidCallback? onNoteTap;

  /// A live widget in the note slot (a ticking timer), instead of static [note] text.
  final Widget? noteWidget;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final noteStyle = cantiereMono(context, 8.5, letterSpacing: 0.51);
    Widget? right = noteWidget;
    if (right == null && note != null) {
      right = Text(note!.toUpperCase(), style: noteStyle);
      if (onNoteTap != null) {
        right = InkWell(
          onTap: onNoteTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: right),
        );
      }
    }
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(title, style: cantiereDisplay(context, 17))),
                ?right,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ── Buttons ──────────────────────────────────────────────────────────────────

enum CantiereButtonKind { primary, secondary, ghost }

/// `.btn`: 2px radius, Archivo 12/600 (11 in a `.row-btns`), 42px (36px compact). Primary is the
/// accent red on the sheet colour; secondary is the fill with a 1px rule; ghost is bare muted.
class CantiereButton extends StatelessWidget {
  const CantiereButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = CantiereButtonKind.primary,
    this.compact = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final CantiereButtonKind kind;
  final bool compact;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, border) = switch (kind) {
      CantiereButtonKind.primary => (c.accentInk, c.brandOn, null),
      CantiereButtonKind.secondary => (c.bg3, c.ink, c.borderLight),
      CantiereButtonKind.ghost => (Colors.transparent, c.inkMuted, null),
    };
    final enabled = onPressed != null && !loading;
    final weight = kind == CantiereButtonKind.ghost ? FontWeight.w500 : FontWeight.w600;

    return Opacity(
      opacity: onPressed == null && !loading ? 0.45 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRack.freeShape,
          side: border == null ? BorderSide.none : BorderSide(color: border),
        ),
        child: InkWell(
          borderRadius: AppRack.freeShape,
          onTap: enabled ? onPressed : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 36 : 42),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: cantiereBody(context, compact ? 11 : 12, weight: weight, color: fg),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stamps ───────────────────────────────────────────────────────────────────

/// `.stamp`: 1.5px double-style border, Archivo Narrow 9/700, tracking .13em, uppercase, rotated
/// -3deg, with a 4px dot. [color] is the stamp's single ink.
class CantiereStamp extends StatelessWidget {
  const CantiereStamp({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -3 * math.pi / 180,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRack.freeShape,
          border: Border.all(color: color, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const SizedBox(width: 4, height: 4),
              ),
              const SizedBox(width: 5),
              Text(
                label.toUpperCase(),
                style: cantiereDisplay(
                  context,
                  9,
                  weight: FontWeight.w700,
                  letterSpacing: 1.17,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.mini-stamp`: the red LEAD tag — display 7, tracking .1em, 1px red border, 1px radius,
/// rotated -4deg.
class CantiereMiniStamp extends StatelessWidget {
  const CantiereMiniStamp({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final red = context.colors.accentInk;
    return Transform.rotate(
      angle: -4 * math.pi / 180,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1),
          border: Border.all(color: red),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: Text(label, style: cantiereDisplay(context, 7, letterSpacing: 0.7, color: red)),
        ),
      ),
    );
  }
}

// ── Hero copy ────────────────────────────────────────────────────────────────

/// `.hero-copy`: 11.5 muted, with `<b>` runs in ink. [bold] is spliced between [before] and
/// [after].
class CantiereHeroCopy extends StatelessWidget {
  const CantiereHeroCopy({super.key, required this.before, this.bold, this.after = ''});

  final String before;
  final String? bold;
  final String after;

  @override
  Widget build(BuildContext context) {
    final base = cantiereBody(context, 11.5, color: context.colors.inkMuted);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: before),
          if (bold != null)
            TextSpan(
              text: bold,
              style: base.copyWith(fontWeight: FontWeight.w700, color: context.colors.ink),
            ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
    );
  }
}

// ── Drawn map ────────────────────────────────────────────────────────────────

/// `.map-art`: the drawn map thumbnail — a fill ground, an 18px hairline grid, two road bands
/// and the red site pin. Painted from palette tokens only.
class CantiereMapArt extends StatelessWidget {
  const CantiereMapArt({super.key, this.height = 78});

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRack.freeShape,
        border: Border.all(color: c.borderLight),
      ),
      child: ClipRRect(
        borderRadius: AppRack.freeShape,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _MapArtPainter(ground: c.bg3, road: c.borderLight, grid: c.inkMuted),
            child: Align(
              alignment: const Alignment(0.04, -0.24),
              child: DecoratedBox(
                decoration: BoxDecoration(color: c.accentInk, shape: BoxShape.circle),
                child: const SizedBox(width: 14, height: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapArtPainter extends CustomPainter {
  _MapArtPainter({required this.ground, required this.road, required this.grid});

  final Color ground;
  final Color road;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.11)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 18) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Two road bands, as the mockup's 115deg / 25deg gradients: a steep one crossing at ~44% of
    // the width and a shallow one crossing lower right.
    final roadPaint = Paint()
      ..color = road
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    roadPaint.strokeWidth = 3;
    canvas.drawLine(
      Offset(size.width * 0.44 + size.height * 0.47, 0),
      Offset(size.width * 0.44 - size.height * 0.47, size.height),
      roadPaint,
    );
    roadPaint.strokeWidth = 5;
    canvas.drawLine(
      Offset(0, size.height * 0.95),
      Offset(size.width, size.height * 0.95 - size.width * 0.47),
      roadPaint,
    );
  }

  @override
  bool shouldRepaint(_MapArtPainter old) =>
      old.ground != ground || old.road != road || old.grid != grid;
}
