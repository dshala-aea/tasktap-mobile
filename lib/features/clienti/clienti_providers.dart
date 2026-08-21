import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/clienti/cliente_overview_api_client.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_service.dart';

/// All active customers, alphabetical by company name.
final customersProvider = StreamProvider.autoDispose<List<Customer>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.customers)
        ..where((c) => c.isActive.equals(true))
        ..orderBy([(c) => OrderingTerm.asc(c.companyName)]))
      .watch();
});

/// Look up a single [Customer] by id from the local cache.
/// (Re-exported convenience alias — original lives in schedule_providers.dart)
final customerDetailProvider = StreamProvider.autoDispose
    .family<Customer?, String>((ref, id) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(
        db.customers,
      )..where((c) => c.id.equals(id))).watchSingleOrNull();
    });

/// Count of tickets belonging to [customerId] from the local Drift cache.
final ticketCountForCustomerProvider = StreamProvider.autoDispose
    .family<int, String>((ref, customerId) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(db.tickets)
            ..where((t) => t.customerId.equals(customerId)))
          .watch()
          .map((rows) => rows.length);
    });

/// All tickets for a given [customerId], most-recent first.
final ticketsForCustomerProvider = StreamProvider.autoDispose
    .family<List<Ticket>, String>((ref, customerId) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(db.tickets)
            ..where((t) => t.customerId.equals(customerId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();
    });

/// The server-side customer record: the fiscal fields and counts the mirror does not carry.
///
/// Enrichment, not the base. Everything the cliente detail already showed keeps coming from Drift,
/// so the screen is unchanged with no signal; this only fills the gaps. Offline it throws before
/// touching the network, so the screen states that rather than rendering a failure for a request
/// that never left the device.
final clienteOverviewProvider = FutureProvider.autoDispose
    .family<ClienteOverviewDto, String>((ref, customerId) async {
      if (!ref.watch(isOnlineProvider)) {
        throw const ClienteOverviewOfflineException();
      }
      return ref
          .watch(clienteOverviewApiClientProvider)
          .getOverview(customerId);
    });
