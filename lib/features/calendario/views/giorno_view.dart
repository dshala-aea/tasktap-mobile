// lib/features/calendario/views/giorno_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';

import '../../../core/theme/status_colors.dart';
import '../../../data/local/app_database.dart';
import '../calendario_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

/// First hour shown in the day grid.
const int _kStartHour = 7;

/// Last hour shown (exclusive) — rows from 7:00 to 20:00.
const int _kEndHour = 21;

/// Height in logical pixels for one hour row.
const double _kHourHeight = 64.0;

/// Width reserved for the hour labels column.
const double _kLabelWidth = 48.0;

/// Calendario → Giorno view: vertical hour grid with coloured event blocks
/// positioned by timeStartMinutes / timeEndMinutes.
///
/// Tapping an event block with a ticketId triggers [onTapTicket]; otherwise
/// [onTapSchedule] is called to show an info sheet.
class GiornoView extends ConsumerWidget {
  const GiornoView({super.key, required this.schedules, this.onTapTicket, this.onTapSchedule});

  final List<Schedule> schedules;
  final void Function(String ticketId)? onTapTicket;
  final void Function(Schedule schedule)? onTapSchedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalHeight = (_kEndHour - _kStartHour) * _kHourHeight;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(0, 8, 0, context.navClearance),
      child: SizedBox(
        height: totalHeight + 8,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hour labels ──────────────────────────────────────────────────
            SizedBox(
              width: _kLabelWidth,
              height: totalHeight,
              child: Column(
                children: [
                  for (int h = _kStartHour; h < _kEndHour; h++)
                    SizedBox(
                      height: _kHourHeight,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8, top: 4),
                          child: Text(
                            '${h.toString().padLeft(2, '0')}:00',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: context.colors.inkMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Hour grid + event blocks ─────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // Grid lines
                  Column(
                    children: [
                      for (int h = _kStartHour; h < _kEndHour; h++)
                        Container(
                          height: _kHourHeight,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: context.colors.borderLight, width: 1),
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Event blocks
                  for (final s in schedules)
                    _EventBlock(
                      schedule: s,
                      onTapTicket: onTapTicket,
                      onTapSchedule: onTapSchedule,
                    ),
                ],
              ),
            ),

            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _EventBlock extends StatelessWidget {
  const _EventBlock({required this.schedule, this.onTapTicket, this.onTapSchedule});

  final Schedule schedule;
  final void Function(String ticketId)? onTapTicket;
  final void Function(Schedule schedule)? onTapSchedule;

  @override
  Widget build(BuildContext context) {
    final startMin = schedule.timeStartMinutes;
    final endMin = schedule.timeEndMinutes;
    final clampedStart = startMin.clamp(_kStartHour * 60, _kEndHour * 60).toDouble();
    final clampedEnd = endMin.clamp(_kStartHour * 60, _kEndHour * 60).toDouble();

    final top = (clampedStart - _kStartHour * 60) / 60 * _kHourHeight;
    // 44dp floor, not 24: at 64dp/hour a half-hour job painted 32dp and a quarter-hour one
    // clamped to 24 — both under the minimum target for a gloved thumb, on the view a technician
    // uses standing at a van door.
    //
    // The cost is that a short block now runs 12dp past its own end time and can overlap whatever
    // follows it. That overlap already existed here (nothing lays these out for collisions — they
    // are absolutely positioned by time in a plain Stack, so concurrent jobs stack today), and a
    // 12dp band at the bottom edge is a better failure than a target nothing can hit reliably.
    final height = ((clampedEnd - clampedStart) / 60 * _kHourHeight).clamp(44.0, double.infinity);

    final statusName = scheduleStatusName(schedule.statusId);
    final pair = statusColor(statusName);

    return Positioned(
      top: top,
      left: 4,
      right: 4,
      height: height,
      // AppTappable, not GestureDetector + AnimatedContainer: the 200ms colour morph only ran when
      // a job's stato changed under the user, while the missing press feedback was felt on every
      // single tap. Feedback wins the trade.
      child: AppTappable(
        onTap: () {
          if (schedule.ticketId != null && onTapTicket != null) {
            onTapTicket!(schedule.ticketId!);
          } else if (onTapSchedule != null) {
            onTapSchedule!(schedule);
          }
        },
        color: pair.background,
        borderRadius: AppRack.insetShape,
        border: Border.all(color: pair.foreground.withAlpha(51), width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              schedule.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: pair.foreground,
              ),
            ),
            // No height gate on the time: the 44dp floor makes the old `height > 36` test
            // always true, and a block that shows a title without its hours is worth less than
            // the space it saves.
            Text(
              '${formatMinutes(schedule.timeStartMinutes)} – '
              '${formatMinutes(schedule.timeEndMinutes)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: pair.foreground.withAlpha(179),
              ),
            ),
            if (schedule.ticketId != null && height > 52)
              Icon(LucideIcons.link, size: 10, color: pair.foreground.withAlpha(153)),
          ],
        ),
      ),
    );
  }
}
