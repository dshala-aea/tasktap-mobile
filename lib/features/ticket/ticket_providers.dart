import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';

/// All cached tickets, most-recent first.
final ticketsProvider = StreamProvider.autoDispose<List<Ticket>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

/// Map of statusId → Italian status name from cached TicketStatuses table.
final ticketStatusMapProvider =
    StreamProvider.autoDispose<Map<int, String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.ticketStatuses).watch().map(
        (rows) => {for (final r in rows) r.id: r.name},
      );
});

/// Map of typeId → type name from cached TicketTypes table.
final ticketTypeMapProvider =
    StreamProvider.autoDispose<Map<int, String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.ticketTypes).watch().map(
        (rows) => {for (final r in rows) r.id: r.name},
      );
});

/// All schedules for a specific ticket id.
final schedulesForTicketProvider =
    StreamProvider.autoDispose.family<List<Schedule>, String>((ref, ticketId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.schedules)
        ..where((s) => s.ticketId.equals(ticketId))
        ..orderBy([(s) => OrderingTerm.asc(s.activityDate)]))
      .watch();
});
