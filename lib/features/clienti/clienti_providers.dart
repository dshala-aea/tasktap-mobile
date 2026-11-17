import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/clienti/cliente_overview_api_client.dart';
import '../../data/local/app_database.dart';
import '../../data/reference/reference_cache_repository.dart';
import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_service.dart';
import '../ticket/ticket_providers.dart'
    show closedTicketStatusIdsProvider, ticketIsClosed, ticketsProvider;

/// Active customers only, alphabetical by company name.
///
/// Kept for call sites that genuinely want the active set; the Clienti list uses
/// [allClientiCustomersProvider] so its `Attivi · Tutti · Inattivi` chips and groups have real data.
final customersProvider = StreamProvider.autoDispose<List<Customer>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.customers)
        ..where((c) => c.isActive.equals(true))
        ..orderBy([(c) => OrderingTerm.asc(c.companyName)]))
      .watch();
});

/// Every mirrored customer — active and inactive — alphabetical by company name.
final allClientiCustomersProvider = StreamProvider.autoDispose<List<Customer>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(
    db.customers,
  )..orderBy([(c) => OrderingTerm.asc(c.companyName)])).watch();
});

/// Open-ticket count per customer id, from the local mirror.
///
/// "Open" uses the same predicate as the ticket list (`closedAt` or a closing status), not the
/// raw row count: a plain count includes every mirrored ticket, closed ones included, which is
/// not what the prototype's `ticket aperti` says.
final customerOpenTicketCountsProvider = Provider.autoDispose<Map<String, int>>(
  (ref) {
    final tickets = ref.watch(ticketsProvider).value ?? const <Ticket>[];
    final closedStatusIds =
        ref.watch(closedTicketStatusIdsProvider).value ?? const <int>{};
    final counts = <String, int>{};
    for (final ticket in tickets) {
      if (ticketIsClosed(ticket, closedStatusIds)) continue;
      counts[ticket.customerId] = (counts[ticket.customerId] ?? 0) + 1;
    }
    return counts;
  },
);

/// Active-contract count per customer id, from the local reference mirror.
///
/// The mirror is technician-scoped (it carries the contracts this device's payload included), so
/// this is a local, possibly partial view — never invented, and never a network read.
final activeContractCountsByCustomerProvider =
    StreamProvider.autoDispose<Map<String, int>>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(
        db.contracts,
      )..where((c) => c.isActive.equals(true))).watch().map((rows) {
        final counts = <String, int>{};
        for (final row in rows) {
          counts[row.customerId] = (counts[row.customerId] ?? 0) + 1;
        }
        return counts;
      });
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

/// All tickets for a given [customerId], most-recent first.
final ticketsForCustomerProvider = StreamProvider.autoDispose
    .family<List<Ticket>, String>((ref, customerId) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(db.tickets)
            ..where((t) => t.customerId.equals(customerId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();
    });

/// All active locations (sedi) for a given [customerId], alphabetical by name.
///
/// Locations are synced to Drift (unlike cantiere contacts/assignments, which are fetched live),
/// so this reads the local mirror the same way [ticketsForCustomerProvider] does — offline-capable,
/// no network round-trip. Gap 3 of the feature audit: the customer detail screen had no Sedi
/// section at all despite `LocationsController` having full CRUD and the location itself already
/// being synced to the device.
final locationsForCustomerProvider = StreamProvider.autoDispose
    .family<List<Location>, String>((ref, customerId) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(db.locations)
            ..where(
              (l) => l.customerId.equals(customerId) & l.isActive.equals(true),
            )
            ..orderBy([(l) => OrderingTerm.asc(l.name)]))
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

/// A customer's labeled contacts (`CustomerContact`), read from the Drift mirror.
///
/// It used to be a live `GET /api/customers/{id}/contacts` that raised an offline exception when the
/// radio was gone. Wrong shape for this section: it sits
/// on the customer detail a technician reaches straight from a ticket ("Cliente") while standing in
/// front of the machine, and the number to phone is exactly what they need with no signal. The sync
/// now carries the rows, so this reads the cache the way every other list on that screen does.
final customerContactsProvider = StreamProvider.autoDispose
    .family<List<CustomerContactRow>, String>(
      (ref, customerId) => ref
          .watch(referenceCacheProvider)
          .watchContactsForCustomer(customerId),
    );
