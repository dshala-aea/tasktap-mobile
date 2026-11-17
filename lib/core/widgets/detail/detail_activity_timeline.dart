import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Colour family of a timeline dot. [neutral] is an outline dot; the others are filled.
enum DetailEventTone { neutral, good, bad, warn }

/// One entry in a [DetailActivityTimeline]. [time] is preformatted by the caller (`09:12`).
class DetailActivityEvent {
  const DetailActivityEvent({
    required this.time,
    required this.title,
    this.meta,
    this.tone = DetailEventTone.neutral,
  });

  final String time;
  final String title;
  final String? meta;
  final DetailEventTone tone;
}

/// A vertical activity list — the mockup's `.timeline`: a 1px rule on the left, a 9px dot per
/// event, mono time, 11.5/600 title, 10.5 muted meta. Presentation only.
class DetailActivityTimeline extends StatelessWidget {
  const DetailActivityTimeline({super.key, required this.events});

  final List<DetailActivityEvent> events;

  static const double _gutter = 22;
  static const double _dot = 9;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;

    return Stack(
      key: const Key('detail-activity-timeline'),
      children: [
        Positioned(
          left: 4,
          top: 5,
          bottom: 6,
          child: SizedBox(
            width: 1,
            child: ColoredBox(color: colors.borderLight),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: _gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < events.length; i++)
                _Event(event: events[i], isLast: i == events.length - 1),
            ],
          ),
        ),
      ],
    );
  }
}

class _Event extends StatelessWidget {
  const _Event({required this.event, required this.isLast});

  final DetailActivityEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final toneColor = switch (event.tone) {
      DetailEventTone.neutral => colors.inkMuted,
      DetailEventTone.good => colors.green,
      DetailEventTone.bad => colors.accentInk,
      DetailEventTone.warn => colors.amber,
    };
    final filled = event.tone != DetailEventTone.neutral;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -DetailActivityTimeline._gutter,
          top: 4,
          child: Container(
            width: DetailActivityTimeline._dot,
            height: DetailActivityTimeline._dot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? toneColor : colors.surface,
              border: Border.all(color: toneColor, width: 1.5),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 13),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.time,
                  style: AppTextStyles.docCode.copyWith(
                    fontSize: 8.5,
                    letterSpacing: 0.34,
                    color: colors.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.title,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 11.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
                if (event.meta != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    event.meta!,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 10.5,
                      height: 1.35,
                      color: colors.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
