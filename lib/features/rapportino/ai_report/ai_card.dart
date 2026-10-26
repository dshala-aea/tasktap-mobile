// dart format width=100
import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Primitives for the AI report screens (Descrivi / Controlla / Firma), built from the client design
// pack (`design-tokens.json` + `reference/rapporto-ai.html`, ClickUp 12493t4rvhn).
//
// Everything here maps onto an existing app token — `context.colors.surface` is the card, `bg2` the
// screen, `borderStrong` the dashed "Da completare" edge, Archivo/Archivo Narrow/IBM Plex Mono the
// fonts. The ONE addition is the AI provenance band, whose two colours the client specified and no
// existing token matches; they live here as consts rather than in the theme, because exactly this
// screen pair uses them.
// ══════════════════════════════════════════════════════════════════════════════

/// `status.aiBg` from the design tokens.
const _aiBandBg = Color(0xFFFFF5C2);

/// `status.aiText` from the design tokens.
const _aiBandInk = Color(0xFF5B4B00);

/// The amber band that opens the review screen: what was compiled by the assistant, and the one
/// instruction that goes with it.
class AiProvenanceBand extends StatelessWidget {
  const AiProvenanceBand({
    super.key,
    this.text = "Compilato dall'assistente AI · controlla e conferma",
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: _aiBandBg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        '✦ $text',
        style: const TextStyle(
          color: _aiBandInk,
          fontFamily: 'Archivo',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

/// A paper card. [todo] draws the dashed border the design uses for a value the assistant could not
/// derive — it reads as "still to fill in", never as a value.
class AiCard extends StatelessWidget {
  const AiCard({super.key, required this.child, this.todo = false, this.padding});

  final Widget child;
  final bool todo;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final inner = Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: todo ? Colors.transparent : context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: todo
          ? CustomPaint(
              painter: _DashedBorderPainter(context.colors.borderStrong),
              child: inner,
            )
          : inner,
    );
  }
}

/// The 10 pt mono label every card starts with.
class AiLabel extends StatelessWidget {
  const AiLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'IBM Plex Mono',
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.4,
        color: color ?? context.colors.inkMuted,
      ),
    );
  }
}

/// The 14/600 body value inside a card.
class AiValue extends StatelessWidget {
  const AiValue(this.text, {super.key, this.muted = false, this.italic = false});

  final String text;
  final bool muted;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Archivo',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: muted ? context.colors.inkMuted : context.colors.ink,
      ),
    );
  }
}

/// One `label — value` line inside a card, with the hairline divider the design uses between rows.
class AiKvRow extends StatelessWidget {
  const AiKvRow({
    super.key,
    required this.label,
    required this.value,
    this.first = false,
    this.note,
    this.noteIsError = false,
    this.trailing,
  });

  final String label;
  final String value;
  final bool first;

  /// A second line under the label — "Da completare", "Non in anagrafica", a conflict.
  final String? note;
  final bool noteIsError;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: first
          ? null
          : BoxDecoration(border: Border(top: BorderSide(color: context.colors.divider))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 13,
                    height: 1.3,
                    color: context.colors.ink,
                  ),
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      note!,
                      style: TextStyle(
                        fontFamily: 'Archivo',
                        fontSize: 12,
                        fontWeight: noteIsError ? FontWeight.w600 : FontWeight.w500,
                        color: noteIsError ? context.colors.red : context.colors.inkMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Archivo',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.colors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small helper text under a card title (SPEC §4's "Da completare").
class AiHelper extends StatelessWidget {
  const AiHelper(this.text, {super.key, this.color, this.italic = false});

  final String text;
  final Color? color;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Archivo',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.4,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: color ?? context.colors.inkMuted,
      ),
    );
  }
}

/// A fixed vertical gap between cards, at the density the design uses for the review screen.
class AiCardGap extends StatelessWidget {
  const AiCardGap({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) => SizedBox(height: dense ? 10 : AppSpacing.base);
}

/// Rounded dashed outline. Flutter has no dashed border, and `Border.all` cannot express one.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.color);

  final Color color;

  static const _dash = 6.0;
  static const _gap = 4.0;
  static const _radius = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
          const Radius.circular(_radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
