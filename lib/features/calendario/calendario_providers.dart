// lib/features/calendario/calendario_providers.dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';

// ── View mode ──────────────────────────────────────────────────────────────────

/// The four Calendario tab views.
enum CalendarioView { giorno, settimana, mese, lista }

/// Currently selected view (default: Giorno).
final calendarioViewProvider = StateProvider<CalendarioView>((ref) => CalendarioView.giorno);

// ── Selected date ──────────────────────────────────────────────────────────────

/// The currently focused date (local midnight, normalized).
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

// ── Date range provider ────────────────────────────────────────────────────────

/// A date range passed as a family key.
class DateRange {
  const DateRange({required this.start, required this.end});

  /// Inclusive start (local midnight → stored as UTC in Drift).
  final DateTime start;

  /// Exclusive end (local midnight → stored as UTC in Drift).
  final DateTime end;

  @override
  bool operator ==(Object other) => other is DateRange && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// StreamProvider.family that returns schedules where
/// [activityDate] ∈ [range.start, range.end).
///
/// Both dates are normalized to UTC midnight before querying Drift, mirroring
/// the convention used in schedule_providers.dart and dashboard_providers.dart.
final schedulesInRangeProvider = StreamProvider.autoDispose.family<List<Schedule>, DateRange>((
  ref,
  range,
) {
  final db = ref.watch(appDatabaseProvider);
  final startUtc = range.start.toUtc();
  final endUtc = range.end.toUtc();

  return (db.select(db.schedules)
        ..where(
          (s) =>
              s.activityDate.isBiggerOrEqualValue(startUtc) &
              s.activityDate.isSmallerThanValue(endUtc),
        )
        ..orderBy([
          (s) => OrderingTerm.asc(s.activityDate),
          (s) => OrderingTerm.asc(s.timeStartMinutes),
        ]))
      .watch();
});

// ── Status helpers ─────────────────────────────────────────────────────────────

/// Pilot status-table convention (mirrors dashboard_providers.dart constants):
/// 2 = In corso, 5 = Completato. Other IDs fall through to neutral.
///
/// WARNING: This mapping is derived from the observed backend seed data, not
/// a dynamic lookup of the ticket_statuses table. Update when the server-side
/// status table changes.
String scheduleStatusName(int statusId) {
  return switch (statusId) {
    2 => 'In corso',
    5 => 'Completato',
    1 => 'Aperto',
    3 => 'In pausa',
    4 => 'In attesa',
    6 => 'Chiuso',
    7 => 'Annullato',
    _ => 'Pianificato',
  };
}

// ── Group helpers ──────────────────────────────────────────────────────────────

/// Groups a list of [Schedule]s by their local-date (year/month/day).
/// Returns a sorted map (ascending by date).
Map<DateTime, List<Schedule>> groupSchedulesByDay(List<Schedule> schedules) {
  final map = <DateTime, List<Schedule>>{};
  for (final s in schedules) {
    final local = s.activityDate.toLocal();
    final key = DateTime(local.year, local.month, local.day);
    map.putIfAbsent(key, () => []).add(s);
  }
  // Sort groups by date
  final sorted = Map.fromEntries(map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  return sorted;
}

/// Groups a list of [Schedule]s by hour bucket (start-hour) for the Giorno view.
Map<int, List<Schedule>> groupSchedulesByHour(List<Schedule> schedules) {
  final map = <int, List<Schedule>>{};
  for (final s in schedules) {
    final hour = s.timeStartMinutes ~/ 60;
    map.putIfAbsent(hour, () => []).add(s);
  }
  return map;
}

/// Formats an int-minutes-since-midnight value as "HH:MM".
String formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
