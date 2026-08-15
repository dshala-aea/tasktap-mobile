import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Signature pad placeholder.
///
/// Spec: empty state shows a dashed 1.5 px BS border, 10 px radius, ~90 tall,
/// signature icon + "Tocca per firmare". Filled state shows the captured stroke
/// (here a confirmation) + "Firmato il …".
///
/// Real stroke capture arrives in a later phase; this is the foundation widget.
///
/// ```dart
/// SignaturePadPlaceholder(onTap: () {});
/// SignaturePadPlaceholder(signed: true, signedAt: '20/06/2026 14:32');
/// ```
class SignaturePadPlaceholder extends StatelessWidget {
  const SignaturePadPlaceholder({super.key, this.signed = false, this.signedAt, this.onTap});

  final bool signed;
  final String? signedAt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final caption = signed ? 'Firmato il ${signedAt ?? ''}'.trim() : 'Tocca per firmare';

    return Semantics(
      button: true,
      label: signed ? 'Firma acquisita' : 'Tocca per firmare',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: signed ? null : _DashedBorderPainter(border: context.colors.borderStrong),
          child: Container(
            height: 90,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: signed ? context.colors.bg2 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: signed ? Border.all(color: context.colors.borderStrong, width: 1.5) : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  signed ? LucideIcons.checkCircle : LucideIcons.penTool,
                  size: 22,
                  color: signed ? context.colors.green : context.colors.inkMuted,
                ),
                const SizedBox(height: 6),
                Text(
                  caption,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: signed ? context.colors.ink : context.colors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a dashed rounded-rectangle border (1.5 px BS, 10 px radius).
class _DashedBorderPainter extends CustomPainter {
  /// A painter is outside the widget tree, so the colour is resolved by the caller
  /// and handed in rather than read from a context this class does not have.
  const _DashedBorderPainter({required this.border});

  final Color border;

  static const double _radius = 10;
  static const double _dash = 6;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = border
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(_radius));
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dash;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}
