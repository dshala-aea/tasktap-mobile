import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Initials avatar circle.
///
/// Spec: default size 36, colour cycle [Y, #A8DADC, #FFE66D, #06AED5, #F4A261, #FFB200],
/// DARK text, Manrope 700, fontSize = size × 0.36.
///
/// Colour is deterministic — it is selected by the hash of [name].
///
/// ```dart
/// AppAvatar(name: 'Mario Rossi');
/// AppAvatar(name: 'giovanni@example.com', size: 48);
/// ```
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.size = 36,
  });

  final String name;
  final double size;

  static const List<Color> _palette = [
    AppColors.Y,
    Color(0xFFA8DADC),
    Color(0xFFFFE66D),
    Color(0xFF06AED5),
    Color(0xFFF4A261),
    Color(0xFFFFB200),
  ];

  Color _bgColor() {
    if (name.isEmpty) return _palette[0];
    final index = name.codeUnits.fold(0, (sum, c) => sum + c) % _palette.length;
    return _palette[index];
  }

  String _initials() {
    final parts = name
        .split(RegExp(r'[\s@.]+'))
        .where((p) => p.isNotEmpty)
        .toList();
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
        decoration: BoxDecoration(
          color: _bgColor(),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            _initials(),
            style: GoogleFonts.manrope(
              fontSize: size * 0.36,
              fontWeight: FontWeight.w700,
              color: AppColors.DARK,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
