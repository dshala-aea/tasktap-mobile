import 'package:flutter/material.dart';

/// Initials avatar circle.
///
/// Spec: default size 36, white text, Inter 700, fontSize = size × 0.36.
///
/// Colour is deterministic — it is selected by the hash of [name], from a palette that stays
/// inside Vetro's own cool blue→violet family (built around the tint/tintStrong gradient every
/// other accent in the app uses) instead of the old warm, unrelated multi-hue set (safety orange,
/// mustard yellow, tan) that had nothing to do with the rest of the palette. Text went from DARK
/// to white for the same reason every other tint-filled surface in the app (AppChip active,
/// AppButton primary, a status pill's saturated fill) uses white foreground, not dark ink — these
/// backgrounds are saturated enough that dark text loses contrast on some of them.
///
/// ```dart
/// AppAvatar(name: 'Mario Rossi');
/// AppAvatar(name: 'giovanni@example.com', size: 48);
/// ```
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, this.size = 36});

  final String name;
  final double size;

  static const List<Color> _palette = [
    Color(0xFF4F6BFF), // Vetro tint
    Color(0xFF8A5CF6), // Vetro tintStrong
    Color(0xFF06AED5), // cyan
    Color(0xFF3DA9FC), // sky blue
    Color(0xFF7C6FF2), // indigo
    Color(0xFFB57BFF), // soft violet
  ];

  Color _bgColor() {
    if (name.isEmpty) return _palette[0];
    final index = name.codeUnits.fold(0, (sum, c) => sum + c) % _palette.length;
    return _palette[index];
  }

  String _initials() {
    final parts = name.split(RegExp(r'[\s@.]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: _bgColor(), shape: BoxShape.circle),
        child: Center(
          child: Text(
            _initials(),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: size * 0.36,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
