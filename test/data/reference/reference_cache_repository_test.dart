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

  group('allProdottiWithCustomer', () {
    ProdottoAssistenzaSyncDto prodotto(String id, String customerId, {bool active = true}) =>
        ProdottoAssistenzaSyncDto(
          id: id,
          tenantId: 't',
          createdAt: DateTime.now(),
          name: id,
          customerId: customerId,
          locationId: 'l1',
          isActive: active,
        );

    Future<void> seedCustomer(String id, String name) => db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: id,
            tenantId: 't',
            createdAt: DateTime.now(),
            companyName: name,
          ),
        );

    // The Asset hub list has no customer scope, and its rows print whose asset it is — so the
    // reader resolves the name here instead of leaving the screen to walk a customers endpoint.
    test('names the customer and skips deactivated assets', () async {
      await seedCustomer('cu1', 'ACME Srl');
      await seedCustomer('cu2', 'Beta Spa');
      await repo.upsertProdottiAssistenza([
        prodotto('p1', 'cu1'),
        prodotto('p2', 'cu2'),
        prodotto('p3', 'cu1', active: false),
      ]);

      final rows = await repo.allProdottiWithCustomer();

      expect(rows.map((r) => (r.$1.id, r.$2)), [('p1', 'ACME Srl'), ('p2', 'Beta Spa')]);
    });

    test('an asset whose customer this device does not carry gets no name, not a guess', () async {
      await repo.upsertProdottiAssistenza([prodotto('p1', 'cu-absent')]);

      final rows = await repo.allProdottiWithCustomer();

      expect(rows.single.$1.id, 'p1');
      expect(rows.single.$2, isNull);
    });
  });
}
