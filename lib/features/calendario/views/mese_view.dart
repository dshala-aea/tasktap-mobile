// lib/features/calendario/views/mese_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/app_database.dart';
import '../calendario_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

/// Calendario → Mese view: month calendar grid (weeks × 7). Each day cell
/// shows event dots / count. Tapping a day selects it and switches to Giorno.
class MeseView extends ConsumerWidget {
  const MeseView({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.schedules,
    this.onDayTap,
  });

  /// Any date within the month to display.
  final DateTime month;

  /// Currently selected date.
  final DateTime selectedDate;

  /// All schedules for the displayed month.
  final List<Schedule> schedules;

  /// Called when a day is tapped.
  final void Function(DateTime day)? onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = groupSchedulesByDay(schedules);
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final selectedKey = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    // Start from the Monday of the week containing monthStart
    final firstWeekday = monthStart.weekday; // 1=Mon, 7=Sun
    final gridStart = monthStart.subtract(Duration(days: firstWeekday - 1));

    // Build grid days until we cover the full last week
    final lastWeekday = monthEnd.weekday;
    final gridEnd = monthEnd.add(Duration(days: 7 - lastWeekday));

    final gridDays = <DateTime>[];
    var cursor = gridStart;
    while (!cursor.isAfter(gridEnd)) {
      gridDays.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    final weekCount = (gridDays.length / 7).ceil();
    final monthFmt = DateFormat('MMMM y', 'it');
    final dayNameFmt = DateFormat('EEE', 'it');
    final weekdays = List.generate(7, (i) => gridStart.add(Duration(days: i)));

    return Column(
      children: [
        // Month + year title
        Padding(
          padding: const EdgeInsets.fromLTRB(19, 8, 19, 12),
          child: Text(
            _capitalize(monthFmt.format(month)),
            style: GoogleFonts.sora(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.ink,
            ),
          ),
        ),
        // Weekday header row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: weekdays
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        dayNameFmt.format(d).toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: context.colors.inkMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        // Day cells
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: List.generate(weekCount, (row) {
                return Expanded(
                  child: Row(
                    children: List.generate(7, (col) {
                      final idx = row * 7 + col;
                      if (idx >= gridDays.length) return const Expanded(child: SizedBox());
                      final day = gridDays[idx];
                      final key = DateTime(day.year, day.month, day.day);
                      final inMonth = day.month == month.month;
                      final isToday = key == todayKey;
                      final isSelected = key == selectedKey;
                      final daySchedules = grouped[key] ?? [];
                      final count = daySchedules.length;

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: AppTappable(
                            onTap: () => onDayTap?.call(day),
                            color: isSelected
                                ? context.colors.surfaceInverse
                                : isToday
                                ? AppColors.YSoft
                                : Colors.transparent,
                            borderRadius: AppRack.insetShape,
                            border: isToday && !isSelected
                                ? Border.all(color: AppColors.Y, width: 1.5)
                                : null,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${day.day}',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? context.colors.inkInverse
                                        : inMonth
                                        ? context.colors.ink
                                        : context.colors.inkDisabled,
                                  ),
                                ),
                                if (count > 0) _EventDots(count: count, isSelected: isSelected),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _EventDots extends StatelessWidget {
  const _EventDots({required this.count, required this.isSelected});

  final int count;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final show = count.clamp(0, 3);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(show, (i) {
          return Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.Y : context.colors.amber,
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}
