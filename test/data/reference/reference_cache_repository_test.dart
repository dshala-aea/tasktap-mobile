import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reference/reference_cache_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';

void main() {
  late AppDatabase db;
  late ReferenceCacheRepository repo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = ReferenceCacheRepository(db);
  });
  tearDown(() => db.close());

  ContractSyncDto contract(
    String id,
    String customerId, {
    String? name,
    bool active = true,
  }) => ContractSyncDto(
    id: id,
    tenantId: 't',
    createdAt: DateTime.now(),
    name: name ?? id,
    customerId: customerId,
    startDate: DateTime.now(),
    isActive: active,
  );

  test(
    'contractsForCustomer returns only that customer, only active, in name order',
    () async {
      await repo.upsertContracts([
        contract('c1', 'cu1', name: 'Zeta'),
        contract('c2', 'cu1', name: 'Alfa'),
        contract('c3', 'cu1', name: 'Cessato', active: false),
        contract('c4', 'cu2', name: 'Altro cliente'),
      ]);

      final rows = await repo.contractsForCustomer('cu1');

      expect(rows.map((r) => r.name), ['Alfa', 'Zeta']);
    },
  );

  test(
    'prune removes a deleted contract of a customer the payload carries',
    () async {
      await repo.upsertContracts([
        contract('c1', 'cu1'),
        contract('c2', 'cu1'),
      ]);

      await repo.pruneContracts(
        presentCustomerIds: {'cu1'},
        keepContractIds: {'c1'},
      );

      expect((await repo.contractsForCustomer('cu1')).map((r) => r.id), ['c1']);
    },
  );

  /// The customer is not in the payload, so this sync says nothing about them — and the device
  /// must not guess. This is the case a "delete everything the payload omits" rule gets wrong.
  test('prune never touches a customer the payload does not carry', () async {
    await repo.upsertContracts([contract('c9', 'cu-absent')]);

    await repo.pruneContracts(presentCustomerIds: {'cu1'}, keepContractIds: {});

    expect((await repo.contractsForCustomer('cu-absent')).map((r) => r.id), [
      'c9',
    ]);
  });

  /// An empty keep-set is not an exotic case: a customer whose last contract was hard-deleted
  /// produces exactly it, and it is the one shape where a naive NOT IN list is empty.
  test(
    'prune with an empty keep-set clears that customer and nothing else',
    () async {
      await repo.upsertContracts([
        contract('c1', 'cu1'),
        contract('c9', 'cu-absent'),
      ]);

      await repo.pruneContracts(
        presentCustomerIds: {'cu1'},
        keepContractIds: {},
      );

      expect(await repo.contractsForCustomer('cu1'), isEmpty);
      expect((await repo.contractsForCustomer('cu-absent')).map((r) => r.id), [
        'c9',
      ]);
    },
  );

  test('an empty present-set prunes nothing', () async {
    await repo.upsertContracts([contract('c1', 'cu1')]);

    await repo.pruneContracts(presentCustomerIds: {}, keepContractIds: {});

    expect((await repo.contractsForCustomer('cu1')).map((r) => r.id), ['c1']);
  });

  // The customer screen records what the customer has, deactivated rows included (it prints them
  // as "Inattivo"); the pickers that attach a ticket to a contract must not offer a dead one. One
  // reader, two answers, chosen by the caller.
  test('includeInactive records a deactivated contract too, still in name order', () async {
    await repo.upsertContracts([
      contract('c1', 'cu1', name: 'Zeta'),
      contract('c2', 'cu1', name: 'Alfa'),
      contract('c3', 'cu1', name: 'Cessato', active: false),
      contract('c4', 'cu2', name: 'Altro cliente'),
    ]);

    final rows = await repo.contractsForCustomer('cu1', includeInactive: true);

    expect(rows.map((r) => r.name), ['Alfa', 'Cessato', 'Zeta']);
    expect(rows.firstWhere((r) => r.id == 'c3').isActive, isFalse);
  });

  test('prodottiForCustomer hides a deactivated asset unless asked for it', () async {
    ProdottoAssistenzaSyncDto prodotto(String id, {required bool active}) =>
        ProdottoAssistenzaSyncDto(
          id: id,
          tenantId: 't',
          createdAt: DateTime.now(),
          name: id,
          customerId: 'cu1',
          locationId: 'l1',
          isActive: active,
        );
    await repo.upsertProdottiAssistenza([
      prodotto('p1', active: true),
      prodotto('p2', active: false),
    ]);

    expect((await repo.prodottiForCustomer('cu1')).map((p) => p.id), ['p1']);
    expect(
      (await repo.prodottiForCustomer('cu1', includeInactive: true)).map((p) => p.id),
      ['p1', 'p2'],
    );
  });
}
