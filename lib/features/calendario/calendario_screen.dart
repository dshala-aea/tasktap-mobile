// lib/features/calendario/calendario_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import 'calendario_providers.dart';
import 'views/giorno_view.dart';
import 'views/lista_view.dart';
import 'views/mese_view.dart';
import 'views/settimana_view.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Calendario tab — four view modes (Giorno / Settimana / Mese / Lista)
/// wired to cached schedules in Drift.
class CalendarioScreen extends ConsumerWidget {
  const CalendarioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(calendarioViewProvider);
    final selectedDate = ref.watch(selectedDateProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            //
            // "Vai a oggi" was here as an icon. It has moved into the period bar, where it sits
            // next to the date it changes and appears only when the calendar is not already
            // showing today — a control for a state you are already in is a control that has to
            // be read and dismissed on every visit.
            const ScreenHeader(title: 'Calendario'),

            // ── View mode tabs ───────────────────────────────────────────────
            AppTabs(
              tabs: const [
                AppTab(label: 'Giorno'),
                AppTab(label: 'Settimana'),
                AppTab(label: 'Mese'),
                AppTab(label: 'Lista'),
              ],
              selectedIndex: view.index,
              onSelected: (i) =>
                  ref.read(calendarioViewProvider.notifier).state =
                      CalendarioView.values[i],
            ),

            Divider(height: 1, color: context.colors.borderLight),

            // ── Which period, and how to leave it ────────────────────────────
            //
            // The calendar had no way to move between periods and no label saying which one it
            // was showing. The only date controls were the week strip — which only reaches inside
            // the week it is already on — and a "go to today" icon. In Mese the strip was hidden
            // entirely, so a month view could never show a month other than the current one, and
            // nothing on screen named the month it was displaying.
            _PeriodBar(
              view: view,
              selectedDate: selectedDate,
              onChanged: (d) =>
                  ref.read(selectedDateProvider.notifier).state = d,
            ),

            // ── Week-day scroller strip ──────────────────────────────────────
            if (view != CalendarioView.mese && view != CalendarioView.lista)
              _WeekDayScroller(
                selectedDate: selectedDate,
                onDateSelected: (d) =>
                    ref.read(selectedDateProvider.notifier).state = d,
              ),

            // ── Body ─────────────────────────────────────────────────────────
            Expanded(
              // Swiping across the calendar moves to the next period, in whatever unit the
              // current view is measured in. It is the gesture people already try, and it beats
              // reaching for a 44dp arrow with one hand on a ladder.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() < 200 || !view.isNavigable) return;
                  ref.read(selectedDateProvider.notifier).state = view.step(
                    selectedDate,
                    velocity < 0 ? 1 : -1,
                  );
                },
                child: _CalendarioBody(
                  view: view,
                  selectedDate: selectedDate,
                  onSelectDate: (d) =>
                      ref.read(selectedDateProvider.notifier).state = d,
                  onSwitchView: (v) =>
                      ref.read(calendarioViewProvider.notifier).state = v,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Period navigation ─────────────────────────────────────────────────────────

/// Each view measures time in its own unit, so "next" means a different thing in each.
extension _Period on CalendarioView {
  /// Lista is a rolling window anchored to today; there is no previous or next one.
  bool get isNavigable => this != CalendarioView.lista;

  /// Moves [from] by [delta] periods of this view's unit.
  DateTime step(DateTime from, int delta) => switch (this) {
    CalendarioView.giorno => DateTime(from.year, from.month, from.day + delta),
    CalendarioView.settimana => DateTime(
      from.year,
      from.month,
      from.day + 7 * delta,
    ),
    // Clamped by DateTime itself: 31 January + 1 month lands in March if the day is kept, so the
    // day is dropped to 1 and the month view only ever needs the month anyway.
    CalendarioView.mese => DateTime(from.year, from.month + delta, 1),
    CalendarioView.lista => from,
  };

  /// What the bar says. Written for someone glancing, not reading: no year unless it is not
  /// this one, no month name repeated across a week that sits inside one month.
  String label(DateTime date) {
    final now = DateTime.now();
    switch (this) {
      case CalendarioView.giorno:
        final pattern = date.year == now.year ? 'EEEE d MMMM' : 'EEEE d MMMM y';
        return _capitalise(DateFormat(pattern, 'it').format(date));
      case CalendarioView.settimana:
        final monday = date.subtract(Duration(days: date.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        final endPattern = date.year == now.year ? 'd MMM' : 'd MMM y';
        final startPattern = monday.month == sunday.month ? 'd' : 'd MMM';
        return '${DateFormat(startPattern, 'it').format(monday)} – '
            '${DateFormat(endPattern, 'it').format(sunday)}';
      case CalendarioView.mese:
        return _capitalise(DateFormat('MMMM y', 'it').format(date));
      case CalendarioView.lista:
        return 'Prossimi 30 giorni';
    }
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Names the period on screen and steps to the one either side of it.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.view,
    required this.selectedDate,
    required this.onChanged,
  });

  final CalendarioView view;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;

  static DateTime _monday(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  bool get _isOnToday {
    final now = DateTime.now();
    return switch (view) {
      CalendarioView.giorno =>
        selectedDate.year == now.year &&
            selectedDate.month == now.month &&
            selectedDate.day == now.day,
      // Same Monday, not "within seven days" — a Friday and the following Tuesday are five days
      // apart and belong to different weeks.
      CalendarioView.settimana => _monday(selectedDate) == _monday(now),
      CalendarioView.mese =>
        selectedDate.year == now.year && selectedDate.month == now.month,
      CalendarioView.lista => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final navigable = view.isNavigable;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(bottom: BorderSide(color: context.vetro.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 6, AppSpacing.sm, 6),
      child: Row(
        children: [
          if (navigable)
            _StepButton(
              icon: LucideIcons.chevronLeft,
              label: 'Periodo precedente',
              onTap: () => onChanged(view.step(selectedDate, -1)),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              view.label(selectedDate),
              textAlign: navigable ? TextAlign.center : TextAlign.start,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.colors.ink,
              ),
            ),
          ),
          if (navigable)
            _StepButton(
              icon: LucideIcons.chevronRight,
              label: 'Periodo successivo',
              onTap: () => onChanged(view.step(selectedDate, 1)),
            ),
          // Only when it would do something.
          if (navigable && !_isOnToday)
            TextButton(
              onPressed: () {
                final now = DateTime.now();
                onChanged(DateTime(now.year, now.month, now.day));
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: const Text('Oggi'),
            ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: context.colors.ink),
      tooltip: label,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      visualDensity: VisualDensity.compact,
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
      Duration(days: selectedDate.weekday - 1),
    );
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
    final selectedKey = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );

    return Container(
      // 80, not the original 74: raising the day-abbreviation label from 9pt to the 11pt platform
      // floor added a few px the fixed-height cell no longer had room for (a real overflow, caught
      // by the test suite after that fix landed).
      height: 80,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(bottom: BorderSide(color: context.vetro.hairline)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: days.map((day) {
          final key = DateTime(day.year, day.month, day.day);
          final isToday = key == todayKey;
          final isSelected = key == selectedKey;
          final hasDots = (grouped[key] ?? []).isNotEmpty;

          return Expanded(
            // Left as a GestureDetector for the same reason as the bottom nav: the day disc
            // below is an AnimatedContainer that moves on every selection, so the tap is already
            // answered. The three calendar *views* were converted, because an appointment block
            // does nothing visible when tapped until the next screen renders.
            child: Semantics(
              button: true,
              selected: isSelected,
              label:
                  '${dayAbbr.format(day).toUpperCase()} ${day.day}'
                  '${hasDots ? ', con appuntamenti' : ''}',
              child: GestureDetector(
                onTap: () => onDateSelected(day),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayAbbr.format(day).toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? context.vetro.tint : context.colors.inkMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [context.vetro.tint, context.vetro.tintStrong],
                              )
                            : null,
                        color: isSelected
                            ? null
                            : isToday
                            ? context.vetro.tint.withAlpha(31)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        // Clamped so a boosted system text size can't grow the digit past the
                        // fixed 32x32 disc and overlap the event dot below it.
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: MediaQuery.textScalerOf(
                              context,
                            ).clamp(maxScaleFactor: 1.3),
                          ),
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : context.colors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Event dot
                    AnimatedOpacity(
                      opacity: hasDots ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isSelected ? context.vetro.tint : context.colors.amber,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
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

// ── Loading/data/error crossfade for a date-range fetch ────────────────────────
//
// Every one of the four view bodies below keys `schedulesInRangeProvider` by a date range —
// "next day," "next week," "next month" all construct a genuinely new range, so Riverpod starts a
// fresh `.family` instance in its own `loading` state each time (there is no prior value for that
// specific range to fall back to; this isn't a plain refresh of the same provider). Before this,
// that meant the single most repeated interaction on this screen — tapping through dates — hard-cut
// the whole view to a bare spinner and back on every tap. A crossfade doesn't remove that beat, but
// it stops it reading as the screen breaking and rebuilding itself each time.
class _AsyncViewSwitcher<T> extends StatelessWidget {
  const _AsyncViewSwitcher({required this.async, required this.builder});

  final AsyncValue<T> async;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    final child = async.when(
      data: (data) => KeyedSubtree(key: const ValueKey('data'), child: builder(data)),
      loading: () => const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (e, _) =>
          const Center(key: ValueKey('error'), child: Text('Errore nel caricamento')),
    );

    return AnimatedSwitcher(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
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
    final start = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final end = start.add(const Duration(days: 1));
    final range = DateRange(start: start, end: end);
    final async = ref.watch(schedulesInRangeProvider(range));

    return _AsyncViewSwitcher(
      async: async,
      builder: (schedules) => GiornoView(
        schedules: schedules,
        onTapTicket: onTapTicket,
        onTapSchedule: onTapSchedule,
      ),
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
    final monday = selectedDate.subtract(
      Duration(days: selectedDate.weekday - 1),
    );
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    final weekEnd = weekStart.add(const Duration(days: 7));
    final range = DateRange(start: weekStart, end: weekEnd);
    final async = ref.watch(schedulesInRangeProvider(range));

    return _AsyncViewSwitcher(
      async: async,
      builder: (schedules) => SettimanaView(
        weekStart: weekStart,
        schedules: schedules,
        onDayTap: onDayTap,
        onEventTap: onEventTap,
      ),
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
    final monthEnd = DateTime(selectedDate.year, selectedDate.month + 1, 1);
    final range = DateRange(start: monthStart, end: monthEnd);
    final async = ref.watch(schedulesInRangeProvider(range));

    return _AsyncViewSwitcher(
      async: async,
      builder: (schedules) => MeseView(
        month: selectedDate,
        selectedDate: selectedDate,
        schedules: schedules,
        onDayTap: onDayTap,
      ),
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

    return _AsyncViewSwitcher(
      async: async,
      builder: (schedules) => ListaView(schedules: schedules, onTapTicket: onTapTicket),
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
        AppSpacing.xl,
        AppSpacing.base,
        AppSpacing.xl,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
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
                color: context.colors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            schedule.title,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.colors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusPill(stato: statusName, outlined: true),
              const SizedBox(width: 12),
              Icon(LucideIcons.clock, size: 14, color: context.colors.inkMuted),
              const SizedBox(width: 4),
              Text(
                timeRange,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: context.colors.inkMuted,
                ),
              ),
            ],
          ),
          if (schedule.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              schedule.description,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: context.colors.inkFaint,
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
