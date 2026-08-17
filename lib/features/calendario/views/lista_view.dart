// lib/features/calendario/views/lista_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../calendario_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

/// Calendario → Lista view: schedules grouped by day (date section headers)
/// as ListRows (title, time range, StatusPill, location), soonest first.
/// Shows an EmptyState when there are no schedules.
class ListaView extends ConsumerWidget {
  const ListaView({super.key, required this.schedules, this.onTapTicket});

  /// All schedules to display — already sorted by date/time.
  final List<Schedule> schedules;

  /// Called when the user taps a row that has a ticketId.
  final void Function(String ticketId)? onTapTicket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (schedules.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.calendarX,
        title: 'Nessun intervento',
        body: 'Non ci sono interventi pianificati nel periodo selezionato.',
      );
    }

    final grouped = groupSchedulesByDay(schedules);
    final dayFmt = DateFormat('EEEE d MMMM', 'it');

    final children = <Widget>[];
    for (final entry in grouped.entries) {
      // Section header
      children.add(_DateHeader(date: entry.key, formatter: dayFmt));
      for (final s in entry.value) {
        children.add(_ScheduleListRow(schedule: s, onTapTicket: onTapTicket));
      }
    }

    return ListView(padding: const EdgeInsets.only(bottom: 32), children: children);
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date, required this.formatter});

  final DateTime date;
  final DateFormat formatter;

  @override
  Widget build(BuildContext context) {
    final label = formatter.format(date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 20, 19, 6),
      child: Text(
        _capitalize(label),
        style: TextStyle(
          fontFamily: 'Sora',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: context.colors.ink,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _ScheduleListRow extends StatelessWidget {
  const _ScheduleListRow({required this.schedule, this.onTapTicket});

  final Schedule schedule;
  final void Function(String ticketId)? onTapTicket;

  @override
  Widget build(BuildContext context) {
    final timeRange =
        '${formatMinutes(schedule.timeStartMinutes)} – ${formatMinutes(schedule.timeEndMinutes)}';
    final statusName = scheduleStatusName(schedule.statusId);
    final statusPair = statusColor(statusName);

    return ListRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: statusPair.background, borderRadius: AppRack.insetShape),
        child: Icon(LucideIcons.clock, size: 18, color: statusPair.foreground),
      ),
      title: schedule.title,
      subtitle: timeRange,
      meta: StatusPill(stato: statusName, small: true),
      onTap: schedule.ticketId != null && onTapTicket != null
          ? () => onTapTicket!(schedule.ticketId!)
          : null,
    );
  }
}
