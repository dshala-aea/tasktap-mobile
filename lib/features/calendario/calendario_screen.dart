// lib/features/calendario/calendario_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import 'calendario_providers.dart';
import 'views/giorno_view.dart';
import 'views/lista_view.dart';
import 'views/mese_view.dart';
import 'views/settimana_view.dart';

/// Calendario tab — four view modes (Giorno / Settimana / Mese / Lista)
/// wired to cached schedules in Drift.
class CalendarioScreen extends ConsumerWidget {
  const CalendarioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(calendarioViewProvider);
    final selectedDate = ref.watch(selectedDateProvider);

    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            ScreenHeader(
              title: 'Calendario',
              actions: [
                HeaderIconBtn(
                  icon: LucideIcons.calendarCheck,
                  label: 'Vai a oggi',
                  onTap: () {
                    final today = DateTime.now();
                    ref.read(selectedDateProvider.notifier).state =
                        DateTime(today.year, today.month, today.day);
                  },
                ),
              ],
            ),

            // ── View mode tabs ───────────────────────────────────────────────
            AppTabs(
              tabs: const [
                AppTab(label: 'Giorno'),
                AppTab(label: 'Settimana'),
                AppTab(label: 'Mese'),
                AppTab(label: 'Lista'),
              ],
              selectedIndex: view.index,
              onSelected: (i) => ref
                  .read(calendarioViewProvider.notifier)
                  .state = CalendarioView.values[i],
            ),

            const Divider(height: 1, color: AppColors.BL),

            // ── Week-day scroller strip ──────────────────────────────────────
            if (view != CalendarioView.mese && view != CalendarioView.lista)
              _WeekDayScroller(
                selectedDate: selectedDate,
                onDateSelected: (d) =>
                    ref.read(selectedDateProvider.notifier).state = d,
              ),

            // ── Body ─────────────────────────────────────────────────────────
            Expanded(
              child: _CalendarioBody(
                view: view,
                selectedDate: selectedDate,
                onSelectDate: (d) =>
                    ref.read(selectedDateProvider.notifier).state = d,
                onSwitchView: (v) =>
                    ref.read(calendarioViewProvider.notifier).state = v,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Week-day scroller strip ───────────────────────────────────────────────────

class _WeekDayScroller extends ConsumerWidget {
  const _WeekDayScroller({
    required this.selectedDate,
    required this.onDateSelected,
  });

  final DateTime selectedDate;
  final void Function(DateTime) onDateSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Build 7 days centred on selectedDate's week (Mon-Sun).
    final monday = selectedDate.subtract(
        Duration(days: selectedDate.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));

    // Fetch schedules for the week to show event dots.
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    final weekEnd = weekStart.add(const Duration(days: 7));
    final range = DateRange(start: weekStart, end: weekEnd);
    final schedulesAsync = ref.watch(schedulesInRangeProvider(range));
    final schedules = schedulesAsync.valueOrNull ?? [];
    final grouped = groupSchedulesByDay(schedules);

    final dayAbbr = DateFormat('EEE', 'it');
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final selectedKey =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

    return Container(
      height: 74,
      color: AppColors.WHITE,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: days.map((day) {
          final key = DateTime(day.year, day.month, day.day);
          final isToday = key == todayKey;
          final isSelected = key == selectedKey;
          final hasDots = (grouped[key] ?? []).isNotEmpty;

          return Expanded(
            child: GestureDetector(
              onTap: () => onDateSelected(day),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayAbbr.format(day).toUpperCase(),
                    style: GoogleFonts.manrope(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppColors.Y : AppColors.MUTED,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.DARK
                          : isToday
                              ? AppColors.YSoft
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? AppColors.WHITE
                              : isToday
                                  ? AppColors.DARK
                                  : AppColors.DARK,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Event dot
                  AnimatedOpacity(
                    opacity: hasDots ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color:
                            isSelected ? AppColors.Y : AppColors.AMBER,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Body dispatcher ───────────────────────────────────────────────────────────

class _CalendarioBody extends ConsumerWidget {
  const _CalendarioBody({
    required this.view,
    required this.selectedDate,
    required this.onSelectDate,
    required this.onSwitchView,
  });

  final CalendarioView view;
  final DateTime selectedDate;
  final void Function(DateTime) onSelectDate;
  final void Function(CalendarioView) onSwitchView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (view) {
      CalendarioView.giorno => _GiornoBody(
          selectedDate: selectedDate,
          onTapTicket: (id) => context.push(AppRoutes.ticketDetailPath(id)),
          onTapSchedule: (s) => _showScheduleSheet(context, s),
        ),
      CalendarioView.settimana => _SettimanaBody(
          selectedDate: selectedDate,
          onDayTap: (d) {
            onSelectDate(d);
            onSwitchView(CalendarioView.giorno);
          },
          onEventTap: (s) {
            if (s.ticketId != null) {
              context.push(AppRoutes.ticketDetailPath(s.ticketId!));
            } else {
              _showScheduleSheet(context, s);
            }
          },
        ),
      CalendarioView.mese => _MeseBody(
          selectedDate: selectedDate,
          onDayTap: (d) {
            onSelectDate(d);
            onSwitchView(CalendarioView.giorno);
          },
        ),
      CalendarioView.lista => _ListaBody(
          onTapTicket: (id) => context.push(AppRoutes.ticketDetailPath(id)),
        ),
    };
  }

  static void _showScheduleSheet(BuildContext context, Schedule schedule) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ScheduleInfoSheet(schedule: schedule),
    );
  }
}

// ── Giorno body ───────────────────────────────────────────────────────────────

class _GiornoBody extends ConsumerWidget {
  const _GiornoBody({
    required this.selectedDate,
    this.onTapTicket,
    this.onTapSchedule,
  });

  final DateTime selectedDate;
  final void Function(String)? onTapTicket;
  final void Function(Schedule)? onTapSchedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final end = start.add(const Duration(days: 1));
    final range = DateRange(start: start, end: end);
    final async = ref.watch(schedulesInRangeProvider(range));

    return async.when(
      data: (schedules) => GiornoView(
        schedules: schedules,
        onTapTicket: onTapTicket,
        onTapSchedule: onTapSchedule,
      ),
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => const Center(child: Text('Errore nel caricamento')),
    );
  }
}

// ── Settimana body ────────────────────────────────────────────────────────────

class _SettimanaBody extends ConsumerWidget {
  const _SettimanaBody({
    required this.selectedDate,
    this.onDayTap,
    this.onEventTap,
  });

  final DateTime selectedDate;
  final void Function(DateTime)? onDayTap;
  final void Function(Schedule)? onEventTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monday = selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    final weekEnd = weekStart.add(const Duration(days: 7));
    final range = DateRange(start: weekStart, end: weekEnd);
    final async = ref.watch(schedulesInRangeProvider(range));

    return async.when(
      data: (schedules) => SettimanaView(
        weekStart: weekStart,
        schedules: schedules,
        onDayTap: onDayTap,
        onEventTap: onEventTap,
      ),
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => const Center(child: Text('Errore nel caricamento')),
    );
  }
}

// ── Mese body ─────────────────────────────────────────────────────────────────

class _MeseBody extends ConsumerWidget {
  const _MeseBody({required this.selectedDate, this.onDayTap});

  final DateTime selectedDate;
  final void Function(DateTime)? onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetch the entire month ± buffer for the grid cells from adjacent months.
    final monthStart = DateTime(selectedDate.year, selectedDate.month, 1);
    final monthEnd =
        DateTime(selectedDate.year, selectedDate.month + 1, 1);
    final range = DateRange(start: monthStart, end: monthEnd);
    final async = ref.watch(schedulesInRangeProvider(range));

    return async.when(
      data: (schedules) => MeseView(
        month: selectedDate,
        selectedDate: selectedDate,
        schedules: schedules,
        onDayTap: onDayTap,
      ),
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => const Center(child: Text('Errore nel caricamento')),
    );
  }
}

// ── Lista body ────────────────────────────────────────────────────────────────

class _ListaBody extends ConsumerWidget {
  const _ListaBody({this.onTapTicket});

  final void Function(String)? onTapTicket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lista shows a rolling 30-day window (today → +30 days).
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 31));
    final range = DateRange(start: start, end: end);
    final async = ref.watch(schedulesInRangeProvider(range));

    return async.when(
      data: (schedules) => ListaView(
        schedules: schedules,
        onTapTicket: onTapTicket,
      ),
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => const Center(child: Text('Errore nel caricamento')),
    );
  }
}

// ── Schedule info sheet ───────────────────────────────────────────────────────

class _ScheduleInfoSheet extends StatelessWidget {
  const _ScheduleInfoSheet({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final timeRange =
        '${formatMinutes(schedule.timeStartMinutes)} – ${formatMinutes(schedule.timeEndMinutes)}';
    final statusName = scheduleStatusName(schedule.statusId);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.BS,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            schedule.title,
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.DARK,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusPill(stato: statusName),
              const SizedBox(width: 12),
              Icon(LucideIcons.clock, size: 14, color: AppColors.MUTED),
              const SizedBox(width: 4),
              Text(
                timeRange,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: AppColors.MUTED,
                ),
              ),
            ],
          ),
          if (schedule.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              schedule.description,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.FG2,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
