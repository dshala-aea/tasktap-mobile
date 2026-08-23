import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The equipment-lamp "running" indicator: a pulsing green dot.
///
/// Deliberately not the accent. A running clock is the ordinary state of most of a shift, not an
/// alert — painted with the accent for eight hours a day, that color would stop meaning
/// "needs you" the first time someone clocks in. Green-pulse is this world's own convention for
/// "live," the same pairing (accent = needs you, green = running normally) the audience already
/// reads on the equipment it operates. First built inline in the dashboard's active-tracker strip;
/// pulled out here once a second screen needed the same mark, so a third site can't drift from it.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.size = 8});

  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.GREEN, shape: BoxShape.circle),
        child: SizedBox(width: widget.size, height: widget.size),
      );
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Opacity(
        opacity: 0.35 + (_pulse.value * 0.65),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.GREEN, shape: BoxShape.circle),
          child: SizedBox(width: widget.size, height: widget.size),
        ),
      ),
    );
  }
}
