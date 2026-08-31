// dart format width=100
// lib/features/cantiere/cantiere_providers.dart
//
// Providers backing the technician-facing Cantieri tab (CantieriListScreen,
// CantiereDetailScreen). Both read the local Drift mirror only — no independent network call,
// same offline-first shape as cantieriProvider (features/timbra/cantiere_timbra_screen.dart),
// which this file's cantiereByIdProvider complements with a single-row lookup by id.

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider;

/// A single cantiere by id, or null if none is synced locally with that id. Not filtered by
/// status (unlike `cantieriProvider`) — a cantiere reached via a ticket's link may be
/// Completed/Cancelled, and that's a legitimate state to display, not an error.
final cantiereByIdProvider = FutureProvider.family<CantieriData?, String>((ref, id) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await (db.select(db.cantieri)..where((c) => c.id.equals(id))).get();
  return rows.isNotEmpty ? rows.first : null;
});

/// Tickets linked to the given cantiere (`Ticket.cantiereId == id`), for the "Tickets in questo
/// cantiere" section on CantiereDetailScreen. Local-only, like every other list in this app —
/// the technician's own ticket sync scope already determines what's available here.
final ticketsForCantiereProvider = StreamProvider.family<List<Ticket>, String>((ref, cantiereId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)
        ..where((t) => t.cantiereId.equals(cantiereId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});
