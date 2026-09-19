import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Branded toggle switch — 38×22 track, Y (on) / BM (off), 16 white knob, 200 ms.
///
/// Hit area is expanded to ≥44×44 pt via [GestureDetector].
///
/// ```dart
/// AppToggle(
///   value: _enabled,
///   onChanged: (v) => setState(() => _enabled = v),
/// );
/// ```
class AppToggle extends StatelessWidget {
  const AppToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const double _trackW = 38;
  static const double _trackH = 22;
  static const double _knobSize = 16;
  static const double _knobTravel = _trackW - _knobSize - 6; // 16
  static const Duration _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final trackColor = value ? AppColors.Y : context.colors.borderMedium;

    return Semantics(
      toggled: value,
      label: value ? 'attivo' : 'disattivo',
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: _duration,
              curve: Curves.easeInOut,
              width: _trackW,
              height: _trackH,
              decoration: BoxDecoration(
                color: trackColor,
                borderRadius: BorderRadius.circular(_trackH / 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedPositioned(
                    duration: _duration,
                    curve: Curves.easeInOut,
                    left: value ? _knobTravel + 3 : 3,
                    child: Container(
                      width: _knobSize,
                      height: _knobSize,
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
