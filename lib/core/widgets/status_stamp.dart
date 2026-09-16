import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_rack.dart';
import '../theme/status_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';

/// Il Documento's status device: a rubber stamp, not a pill.
///
/// Replaces the flat colored badge every status display in this app previously used
/// ([StatusPill], [StatusBadge] both render through this now — see each file's own doc comment).
/// Per frontend `DESIGN.md`'s States section: double-ring border, slight rotation, all-caps
/// Archivo Narrow, family-specific ring/fill treatment. `AppRack.cellRadius` (2px, "paper, nearly
/// square") is the corner radius, same token every other bordered surface in the app already uses.
///
/// ```dart
/// StatusStamp(stato: 'Completato');
/// StatusStamp(stato: 'Annullato', size: StampSize.small);
/// StatusStamp(stato: 'Inviato', animate: true); // "stamping" entrance, see [animate]
/// ```
enum StampSize { small, medium, large }

class StatusStamp extends StatelessWidget {
  const StatusStamp({
    super.key,
    required this.stato,
    this.size = StampSize.medium,
    this.animate = false,
  });

  /// Italian status string — same vocabulary [statusFamilyOf] already maps.
  final String stato;

  final StampSize size;

  /// Plays the "stamping" in-flight entrance once on mount: scale 1.18 → 0.95 → 1 over 220ms with
  /// a 1° rotation settle, no bounce after (frontend DESIGN.md's States section). Off by default —
  /// a status appearing in a scrolled list should not animate every time it scrolls into view; opt
  /// in only at the moment a status is genuinely new (e.g. right after a submission succeeds).
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final family = statusFamilyOf(stato);
    final style = _StampStyle.forFamily(family, context.colors, context.vetro);
    final label = stato.trim().toUpperCase();

    final metrics = switch (size) {
      StampSize.small => const _StampMetrics(
        fontSize: 9,
        hPad: 7,
        vPad: 3,
        ringGap: 2,
      ),
      StampSize.medium => const _StampMetrics(
        fontSize: 10.5,
        hPad: 9,
        vPad: 4,
        ringGap: 2.5,
      ),
      StampSize.large => const _StampMetrics(
        fontSize: 12,
        hPad: 11,
        vPad: 5,
        ringGap: 3,
      ),
    };

    Widget stamp = Transform.rotate(
      angle: _stampAngleFor(stato),
      child: CustomPaint(
        painter: _StampRingPainter(
          color: style.ring,
          doubleRing: style.doubleRing,
          gap: metrics.ringGap,
          radius: AppRack.cellRadius,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.hPad,
            vertical: metrics.vPad,
          ),
          decoration: BoxDecoration(
            color: style.fill,
            borderRadius: AppRack.freeShape,
          ),
          child: Stack(
            children: [
              if (style.textured)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _StampTexturePainter(
                      seed: stato.hashCode,
                      color: style.ring,
                    ),
                  ),
                ),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Archivo Narrow',
                  fontSize: metrics.fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: style.ink,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (animate) {
      stamp = _StampingEntrance(child: stamp);
    }

    return Semantics(
      label: 'Stato: $stato',
      excludeSemantics: true,
      child: stamp,
    );
  }
}

class _StampMetrics {
  const _StampMetrics({
    required this.fontSize,
    required this.hPad,
    required this.vPad,
    required this.ringGap,
  });

  final double fontSize;
  final double hPad;
  final double vPad;
  final double ringGap;
}

/// The resolved visual treatment for one [StatusFamily] — see frontend DESIGN.md's States
/// section: Verificato (info, double-ring), Approvato (good, double-ring, the only non-red
/// "approved" ink), Non valido (bad, double-ring + coarse texture), In lavorazione (warn, single
/// ring, no fill), Draft (neutral, ghost — ink at 40%, single thin ring).
class _StampStyle {
  const _StampStyle({
    required this.ink,
    required this.ring,
    required this.fill,
    required this.doubleRing,
    required this.textured,
  });

  final Color ink;
  final Color ring;
  final Color? fill;
  final bool doubleRing;
  final bool textured;

  static _StampStyle forFamily(
    StatusFamily family,
    AppPalette colors,
    AppVetroPalette v,
  ) {
    return switch (family) {
      StatusFamily.info => _StampStyle(
        ink: v.tint,
        ring: v.tint,
        fill: v.tint.withAlpha(20),
        doubleRing: true,
        textured: false,
      ),
      StatusFamily.good => _StampStyle(
        ink: v.statusGood,
        ring: v.statusGood,
        fill: v.statusGoodBg,
        doubleRing: true,
        textured: false,
      ),
      StatusFamily.warn => _StampStyle(
        ink: v.statusWarn,
        ring: v.statusWarn,
        fill: null,
        doubleRing: false,
        textured: false,
      ),
      StatusFamily.bad => _StampStyle(
        ink: v.statusBad,
        ring: v.statusBad,
        fill: v.statusBadBg,
        doubleRing: true,
        textured: true,
      ),
      // Draft/ghost: carbon ink at 40%, no fill, single thin ring — "not yet real" per DESIGN.md.
      StatusFamily.neutral => _StampStyle(
        ink: colors.inkMuted,
        ring: colors.inkMuted.withAlpha(102), // 40%
        fill: null,
        doubleRing: false,
        textured: false,
      ),
    };
  }
}

/// A small, stable rotation per label (±1.4°) — enough to read as an ink impression, not enough
/// to cost a technician a second re-reading a status at a glance (see PRODUCT.md Product
/// Principle 5). Deterministic from the label so the same status always tilts the same way,
/// rather than jittering on every rebuild.
double _stampAngleFor(String label) {
  final normalized =
      (label.hashCode.abs() % 1000) / 1000; // 0..1, stable per label
  return (normalized - 0.5) * (2 * 1.4) * (math.pi / 180);
}

/// Double- or single-ring border, drawn outside the widget's own [BoxDecoration] fill so the two
/// rings never compete with the corner radius a plain `Border` would round on its own.
class _StampRingPainter extends CustomPainter {
  const _StampRingPainter({
    required this.color,
    required this.doubleRing,
    required this.gap,
    required this.radius,
  });

  final Color color;
  final bool doubleRing;
  final double gap;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    void ring(Rect rect) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
    }

    ring(Offset.zero & size);
    if (doubleRing) {
      final inset = gap + 1.5;
      ring(
        Rect.fromLTWH(
          inset,
          inset,
          size.width - inset * 2,
          size.height - inset * 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StampRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.doubleRing != doubleRing ||
      oldDelegate.gap != gap;
}

/// "Coarse texture" for the Non valido (destructive) stamp only — DESIGN.md reserves texture for
/// the one status that should read as visually loud. A handful of fixed, low-alpha flecks scattered
/// from a seed derived from the label, not `Random()` on every frame — stable across rebuilds.
class _StampTexturePainter extends CustomPainter {
  const _StampTexturePainter({required this.seed, required this.color});

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint()..color = color.withAlpha(30);
    for (var i = 0; i < 14; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      canvas.drawCircle(Offset(dx, dy), 0.5 + rnd.nextDouble() * 0.6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StampTexturePainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.color != color;
}

/// The "stamping" in-flight entrance: scale 1.18 → 0.95 → 1 over 220ms, no bounce after. Plays
/// once on mount, never repeats — a status that re-renders (theme change, parent rebuild) does
/// not re-stamp itself.
class _StampingEntrance extends StatefulWidget {
  const _StampingEntrance({required this.child});
  final Widget child;

  @override
  State<_StampingEntrance> createState() => _StampingEntranceState();
}

class _StampingEntranceState extends State<_StampingEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 0.95), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Same reduce-motion convention as bottom_nav.dart/timbra_screen.dart — checked here, not
    // initState, because MediaQuery isn't reliably resolvable before the first dependency pass.
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: widget.child,
    );
  }
}
