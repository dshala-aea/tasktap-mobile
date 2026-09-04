// lib/features/calendario/views/mese_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';

import '../../../data/local/app_database.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../calendario_providers.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

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
    final teamScheduleIds = ref.watch(teamAssignedScheduleIdsProvider).valueOrNull ?? const {};
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final selectedKey = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );

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
    final dayNameFmt = DateFormat('EEE', 'it');
    final weekdays = List.generate(7, (i) => gridStart.add(Duration(days: i)));

    return Column(
      children: [
        // No month title here. The period bar above the body names the period for every view and
        // is what moves between them; a second "Agosto 2026" underneath it said the same thing
        // twice and drifted out of step the moment either one was changed.
        // Weekday header row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: weekdays
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        dayNameFmt.format(d).toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Inter',
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Column(
              children: List.generate(weekCount, (row) {
                return Expanded(
                  child: Row(
                    children: List.generate(7, (col) {
                      final idx = row * 7 + col;
                      if (idx >= gridDays.length) {
                        return const Expanded(child: SizedBox());
                      }
                      final day = gridDays[idx];
                      final key = DateTime(day.year, day.month, day.day);
                      final inMonth = day.month == month.month;
                      final isToday = key == todayKey;
                      final isSelected = key == selectedKey;
                      final daySchedules = grouped[key] ?? [];
                      final count = daySchedules.length;
                      final hasTeam = daySchedules.any((s) => teamScheduleIds.contains(s.id));

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: AppTappable(
                            onTap: () => onDayTap?.call(day),
                            color: isSelected
                                ? AppColors.Y
                                : isToday
                                ? AppColors.Y.withAlpha(31)
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
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : inMonth
                                        ? context.colors.ink
                                        : context.colors.inkDisabled,
                                  ),
                                ),
                                if (count > 0)
                                  _EventDots(
                                    count: count,
                                    isSelected: isSelected,
                                    hasTeam: hasTeam,
                                  ),
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
}

class _EventDots extends StatelessWidget {
  const _EventDots({required this.count, required this.isSelected, this.hasTeam = false});

  final int count;
  final bool isSelected;

  /// Whether at least one schedule this day has a squadra-mediated assignee — see
  /// `_ScheduleListRow.isTeam` in `lista_view.dart` for what this flag means and why the day cell
  /// shows an icon rather than a squadra name.
  final bool hasTeam;

  @override
  Widget build(BuildContext context) {
    final show = count.clamp(0, 3);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasTeam)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(
                LucideIcons.users,
                size: 8,
                color: isSelected ? Colors.white : context.colors.amber,
              ),
            ),
          ...List.generate(show, (i) {
            return Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : context.colors.amber,
                shape: BoxShape.circle,
              ),
            );
          }),
        ],
      ),
    );
  }
}
