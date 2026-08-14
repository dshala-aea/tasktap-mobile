// lib/features/calendario/views/settimana_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/status_colors.dart';
import '../../../data/local/app_database.dart';
import '../calendario_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

/// Calendario → Settimana view: 7-column day grid for the selected week with
/// compact event chips per day. Columns are scrollable horizontally; chips
/// are scrollable vertically within each column.
class SettimanaView extends ConsumerWidget {
  const SettimanaView({
    super.key,
    required this.weekStart,
    required this.schedules,
    this.onDayTap,
    this.onEventTap,
  });

  /// Monday of the displayed week (local midnight).
  final DateTime weekStart;

  /// All schedules for this week, sorted by date/time.
  final List<Schedule> schedules;

  /// Called when a day header is tapped → switches to Giorno.
  final void Function(DateTime day)? onDayTap;

  /// Called when an event chip is tapped (ticketId or null).
  final void Function(Schedule schedule)? onEventTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayAbbr = DateFormat('EEE', 'it');
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final grouped = groupSchedulesByDay(schedules);
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: days.map((day) {
          final key = DateTime(day.year, day.month, day.day);
          final isToday = key == todayKey;
          final daySchedules = grouped[key] ?? [];

          return SizedBox(
            width: 110,
            child: Column(
              children: [
                // Day header
                Container(
                  height: 52,
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  child: AppTappable(
                    onTap: () => onDayTap?.call(day),
                    color: isToday ? context.colors.surfaceInverse : Colors.transparent,
                    borderRadius: AppRack.insetShape,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dayAbbr.format(day).toUpperCase(),
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isToday ? AppColors.Y : context.colors.inkMuted,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${day.day}',
                          style: GoogleFonts.sora(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isToday ? context.colors.inkInverse : context.colors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Event chips
                ...daySchedules.map(
                  (s) => _WeekEventChip(schedule: s, onTap: () => onEventTap?.call(s)),
                ),
                if (daySchedules.isEmpty)
                  SizedBox(
                    height: 32,
                    child: Center(
                      child: Text(
                        '–',
                        style: TextStyle(color: context.colors.inkDisabled, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WeekEventChip extends StatelessWidget {
  const _WeekEventChip({required this.schedule, required this.onTap});

  final Schedule schedule;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusName = scheduleStatusName(schedule.statusId);
    final pair = statusColor(statusName);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      constraints: const BoxConstraints(minHeight: 44),
      child: AppTappable(
        onTap: onTap,
        color: pair.background,
        borderRadius: AppRack.insetShape,
        border: Border.all(color: pair.foreground.withAlpha(51), width: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          schedule.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: pair.foreground,
          ),
        ),
      ),
    );
  }
}
