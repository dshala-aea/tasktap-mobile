// lib/features/calendario/calendario_providers.dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';

// ── View mode ──────────────────────────────────────────────────────────────────

/// The four Calendario tab views.
enum CalendarioView { giorno, settimana, mese, lista }

/// Currently selected view (default: Giorno).
final calendarioViewProvider = StateProvider<CalendarioView>(
  (ref) => CalendarioView.giorno,
);

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
  bool operator ==(Object other) =>
      other is DateRange && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// StreamProvider.family that returns schedules where
/// [activityDate] ∈ [range.start, range.end).
///
/// Both dates are normalized to UTC midnight before querying Drift, mirroring
/// the convention used in schedule_providers.dart and dashboard_providers.dart.
final schedulesInRangeProvider = StreamProvider.autoDispose
    .family<List<Schedule>, DateRange>((ref, range) {
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

/// What a schedule reads as, to a person looking at it.
///
/// An absence-owned row (approved Ferie/Permesso/Malattia) is an ordinary `Schedule` server-side
/// and carries the tenant's default work status — the same "Pianificato" a fresh appointment has.
/// Printing that on a week of leave says it is a job waiting to be started, which is exactly the
/// misreading `SyncScheduleDto.isAssenza` exists to prevent. Those rows read as what they are.
String scheduleDisplayStatus(Schedule schedule) =>
    schedule.isAssenza ? 'Assenza' : scheduleStatusName(schedule.statusId);

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
  final sorted = Map.fromEntries(
    map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
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

// ── Where a schedule is, and for whom ──────────────────────────────────────────

/// The customer and site address of a schedule, resolved from the local mirror — no backend field
/// is needed: the customer is the ticket's (`Schedule.ticketId → Ticket.customerId`), falling back
/// to the location's own customer for a schedule with no ticket, and the address is the location's.
class ScheduleWhere {
  const ScheduleWhere({this.customerName, this.address});

  final String? customerName;
  final String? address;
}

/// "Via Roma 12, 20100 Milano", or the location's bare name when it carries no address.
String? formatLocationAddress(Location l) {
  String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
  final street = clean(l.address);
  final town = [clean(l.postalCode), clean(l.city)].whereType<String>().join(' ');
  final parts = [?street, if (town.isNotEmpty) town];
  return parts.isNotEmpty ? parts.join(', ') : clean(l.name);
}

/// Keyed on the two ids a schedule resolves through, so rows sharing a ticket/location share work.
final scheduleWhereProvider = FutureProvider.autoDispose
    .family<ScheduleWhere, ({String? ticketId, String locationId})>((ref, key) async {
      final db = ref.watch(appDatabaseProvider);

      final location = await (db.select(db.locations)..where((l) => l.id.equals(key.locationId)))
          .getSingleOrNull();

      String? customerId;
      if (key.ticketId != null) {
        final ticket = await (db.select(db.tickets)..where((t) => t.id.equals(key.ticketId!)))
            .getSingleOrNull();
        customerId = ticket?.customerId;
      }
      customerId ??= location?.customerId;

      String? customerName;
      if (customerId != null) {
        final customer = await (db.select(db.customers)..where((c) => c.id.equals(customerId!)))
            .getSingleOrNull();
        customerName = customer?.companyName;
      }

      return ScheduleWhere(
        customerName: customerName,
        address: location == null ? null : formatLocationAddress(location),
      );
    });

/// Names of the colleagues on a schedule (`ScheduleAssignees` → `Colleagues`), for the detail
/// sheet. Only people the device holds a name for appear; a squadra name is not mirrored locally.
final scheduleAssigneeNamesProvider = FutureProvider.autoDispose.family<List<String>, String>((
  ref,
  scheduleId,
) async {
  final db = ref.watch(appDatabaseProvider);
  final assignees = await (db.select(db.scheduleAssignees)
        ..where((a) => a.scheduleId.equals(scheduleId)))
      .get();
  if (assignees.isEmpty) return const [];
  final ids = assignees.map((a) => a.userId).toSet();
  final people = await (db.select(db.colleagues)..where((c) => c.id.isIn(ids))).get();
  final names = people.map((p) => p.displayName).where((n) => n.trim().isNotEmpty).toList()
    ..sort();
  return names;
});
