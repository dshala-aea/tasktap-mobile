// dart format width=100
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';

/// Cantieri tagged with a given [commessaId] — a real gap the Vetro mockup's own Commessa
/// detail screen called for: `Cantiere.commessaId` was already synced to Drift (module #13 of
/// the feature audit) and shown nowhere as the *other* direction of the link — from the commessa
/// back to what it's tied to. Local, offline-capable, same shape as `ticketsForCustomerProvider`.
final cantieriForCommessaProvider = StreamProvider.autoDispose.family<List<CantieriData>, String>((
  ref,
  commessaId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cantieri)
        ..where((c) => c.commessaId.equals(commessaId))
        ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
      .watch();
});

/// Tickets tagged with a given [commessaId] — same reasoning as [cantieriForCommessaProvider].
final ticketsForCommessaProvider = StreamProvider.autoDispose.family<List<Ticket>, String>((
  ref,
  commessaId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)
        ..where((t) => t.commessaId.equals(commessaId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});
