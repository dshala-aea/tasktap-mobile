// dart format width=100
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/app_database.dart';
import '../sync/sync_dto.dart';
import '../sync/sync_service.dart' show appDatabaseProvider;

/// The four reference tables, read and written in one place.
///
/// The sync writes them from the payload; [ReferenceSearchClient] writes them again when a
/// technician picks a row an online search found (spec 7.4). Both go through these same upserts, so
/// a row materialised by a pick is indistinguishable from one the payload delivered.
///
/// Nothing above this layer knows how a reference row is stored: screens and widgets ask for rows
/// and hand back ids. See the class's callers — there are two, and neither is a widget.
class ReferenceCacheRepository {
  ReferenceCacheRepository(this._db);

  final AppDatabase _db;

  Future<void> upsertContracts(Iterable<ContractSyncDto> rows) async {
    for (final c in rows) {
      await _db
          .into(_db.contracts)
          .insertOnConflictUpdate(
            ContractsCompanion(
              id: Value(c.id),
              tenantId: Value(c.tenantId),
              createdAt: Value(c.createdAt),
              updatedAt: Value(c.updatedAt),
              name: Value(c.name),
              customerId: Value(c.customerId),
              locationId: Value(c.locationId),
              startDate: Value(c.startDate),
              endDate: Value(c.endDate),
              isActive: Value(c.isActive),
              numero: Value(c.numero),
              codice: Value(c.codice),
              tipo: Value(c.tipo),
              externalId: Value(c.externalId),
            ),
          );
    }
  }

  Future<void> upsertCommesse(Iterable<CommessaSyncDto> rows) async {
    for (final c in rows) {
      await _db
          .into(_db.commesse)
          .insertOnConflictUpdate(
            CommesseCompanion(
              id: Value(c.id),
              tenantId: Value(c.tenantId),
              createdAt: Value(c.createdAt),
              updatedAt: Value(c.updatedAt),
              codice: Value(c.codice),
              descrizione: Value(c.descrizione),
              customerId: Value(c.customerId),
              isActive: Value(c.isActive),
              stato: Value(c.stato),
              externalId: Value(c.externalId),
            ),
          );
    }
  }

  Future<void> upsertProdottiAssistenza(Iterable<ProdottoAssistenzaSyncDto> rows) async {
    for (final p in rows) {
      await _db
          .into(_db.prodottiAssistenza)
          .insertOnConflictUpdate(
            ProdottiAssistenzaCompanion(
              id: Value(p.id),
              tenantId: Value(p.tenantId),
              createdAt: Value(p.createdAt),
              updatedAt: Value(p.updatedAt),
              name: Value(p.name),
              customerId: Value(p.customerId),
              locationId: Value(p.locationId),
              isActive: Value(p.isActive),
              codice: Value(p.codice),
              serialNumber: Value(p.serialNumber),
              categoria: Value(p.categoria),
              marchio: Value(p.marchio),
              externalId: Value(p.externalId),
            ),
          );
    }
  }

  Future<void> upsertAgents(Iterable<AgentSyncDto> rows) async {
    for (final a in rows) {
      await _db
          .into(_db.agents)
          .insertOnConflictUpdate(
            AgentsCompanion(
              id: Value(a.id),
              tenantId: Value(a.tenantId),
              createdAt: Value(a.createdAt),
              updatedAt: Value(a.updatedAt),
              nome: Value(a.nome),
              email: Value(a.email),
              cellulare: Value(a.cellulare),
              isActive: Value(a.isActive),
            ),
          );
    }
  }

  /// Deletes the rows of the customers this payload carries that the payload no longer lists for
  /// them — the only case where an absence is evidence of a deletion. A customer the payload does
  /// not carry is left alone: this sync has nothing to say about them, and the device accumulates
  /// across syncs (see the class doc comment).
  ///
  /// The empty keep-set is handled explicitly: it is what a customer whose last contract was
  /// deleted produces, and it is exactly the shape where a generated NOT IN list would be empty.
  Future<void> pruneContracts({
    required Set<String> presentCustomerIds,
    required Set<String> keepContractIds,
  }) async {
    if (presentCustomerIds.isEmpty) return;
    await (_db.delete(_db.contracts)..where((t) {
          final inScope = t.customerId.isIn(presentCustomerIds);
          return keepContractIds.isEmpty ? inScope : inScope & t.id.isNotIn(keepContractIds);
        }))
        .go();
  }

  Future<void> pruneCommesse({
    required Set<String> presentCustomerIds,
    required Set<String> keepCommessaIds,
  }) async {
    if (presentCustomerIds.isEmpty) return;
    await (_db.delete(_db.commesse)..where((t) {
          final inScope = t.customerId.isIn(presentCustomerIds);
          return keepCommessaIds.isEmpty ? inScope : inScope & t.id.isNotIn(keepCommessaIds);
        }))
        .go();
  }

  Future<void> pruneProdottiAssistenza({
    required Set<String> presentCustomerIds,
    required Set<String> keepProdottiIds,
  }) async {
    if (presentCustomerIds.isEmpty) return;
    await (_db.delete(_db.prodottiAssistenza)..where((t) {
          final inScope = t.customerId.isIn(presentCustomerIds);
          return keepProdottiIds.isEmpty ? inScope : inScope & t.id.isNotIn(keepProdottiIds);
        }))
        .go();
  }

  // There is deliberately no pruneAgents: an agent absent from one payload may still be referenced
  // by a ticket already on this device, and deleting it would break that ticket.

  Future<List<Contract>> contractsForCustomer(String customerId) =>
      (_db.select(_db.contracts)
            ..where((c) => c.customerId.equals(customerId) & c.isActive.equals(true))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();

  Future<List<CommesseData>> commesseForCustomer(String customerId) =>
      (_db.select(_db.commesse)
            ..where((c) => c.customerId.equals(customerId) & c.isActive.equals(true))
            ..orderBy([(c) => OrderingTerm.asc(c.codice)]))
          .get();

  Future<List<ProdottiAssistenzaData>> prodottiForCustomer(String customerId) =>
      (_db.select(_db.prodottiAssistenza)
            ..where((p) => p.customerId.equals(customerId) & p.isActive.equals(true))
            ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .get();

  Future<List<Agent>> activeAgents() =>
      (_db.select(_db.agents)
            ..where((a) => a.isActive.equals(true))
            ..orderBy([(a) => OrderingTerm.asc(a.nome)]))
          .get();
}

final referenceCacheProvider = Provider<ReferenceCacheRepository>(
  (ref) => ReferenceCacheRepository(ref.watch(appDatabaseProvider)),
);
