import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reference/reference_cache_repository.dart';
import 'package:tasktap_mobile/data/reference/reference_option.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/ticket/reference_providers.dart';

/// The four `local*Provider`s and the four `ReferenceOption` DTO factories each build the same
/// label and subtitle from the same row, written twice because the two sources are different types
/// (a wire DTO and a Drift row) and Dart has no structural typing to bridge them.
///
/// Nothing else makes the two agree. A picker's list is the *union* of both halves — see
/// [ReferencePickerField] — so a row drawn from the mirror and the same row reached by a search
/// would render differently, and no single-sided test would notice. These tests run the real
/// providers against a real (in-memory) database and hold both sides to the same literal.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late ReferenceCacheRepository repo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = ReferenceCacheRepository(db);
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  final at = DateTime.utc(2026, 10, 1);

  /// Holds one row's two renderings to one literal, and to each other.
  void pin(
    ReferenceOption viaProvider,
    ReferenceOption viaDto, {
    required String label,
    required String? subtitle,
  }) {
    expect(viaProvider.id, viaDto.id);
    expect(viaProvider.label, label, reason: 'the provider half drifted');
    expect(viaProvider.subtitle, subtitle, reason: 'the provider half drifted');
    expect(viaDto.label, label, reason: 'the DTO factory half drifted');
    expect(viaDto.subtitle, subtitle, reason: 'the DTO factory half drifted');
  }

  test('a contract renders its name, and numero wins over codice', () async {
    final withNumero = ContractSyncDto(
      id: 'c1',
      tenantId: 't',
      createdAt: at,
      name: 'Manutenzione caldaie',
      customerId: 'cu1',
      startDate: at,
      numero: 'N-1',
      codice: 'C-9',
    );
    // The fallback is the whole point of `numero ?? codice`: a contract carrying only the code is
    // still pickable, and it is labelled with what is printed on the paper.
    final onlyCodice = ContractSyncDto(
      id: 'c2',
      tenantId: 't',
      createdAt: at,
      name: 'Assistenza porte',
      customerId: 'cu1',
      startDate: at,
      codice: 'C-9',
    );
    await repo.upsertContracts([withNumero, onlyCodice]);

    final opts = await container.read(localContractsProvider('cu1').future);

    pin(
      opts.firstWhere((o) => o.id == 'c1'),
      ReferenceOption.contract(withNumero),
      label: 'Manutenzione caldaie',
      subtitle: 'N-1',
    );
    pin(
      opts.firstWhere((o) => o.id == 'c2'),
      ReferenceOption.contract(onlyCodice),
      label: 'Assistenza porte',
      subtitle: 'C-9',
    );
  });

  test('a commessa is labelled by its codice, its description below', () async {
    final dto = CommessaSyncDto(
      id: 'm1',
      tenantId: 't',
      createdAt: at,
      codice: 'CM-1',
      descrizione: 'Sostituzione filtri',
      customerId: 'cu1',
    );
    await repo.upsertCommesse([dto]);

    final opts = await container.read(localCommesseProvider('cu1').future);

    pin(
      opts.single,
      ReferenceOption.commessa(dto),
      label: 'CM-1',
      subtitle: 'Sostituzione filtri',
    );
  });

  test('a product falls back from codice to serialNumber', () async {
    final dto = ProdottoAssistenzaSyncDto(
      id: 'p1',
      tenantId: 't',
      createdAt: at,
      name: 'Caldaia Nord',
      customerId: 'cu1',
      locationId: 'l1',
      serialNumber: 'SN-7',
    );
    await repo.upsertProdottiAssistenza([dto]);

    final opts = await container.read(localProdottiProvider('cu1').future);

    pin(
      opts.single,
      ReferenceOption.prodotto(dto),
      label: 'Caldaia Nord',
      subtitle: 'SN-7',
    );
  });

  test('an agent shows the phone, falling back to the email', () async {
    final withPhone = AgentSyncDto(
      id: 'a1',
      tenantId: 't',
      createdAt: at,
      nome: 'Rossi',
      cellulare: '3331112222',
      email: 'rossi@x.it',
    );
    final onlyEmail = AgentSyncDto(
      id: 'a2',
      tenantId: 't',
      createdAt: at,
      nome: 'Bianchi',
      email: 'bianchi@x.it',
    );
    await repo.upsertAgents([withPhone, onlyEmail]);

    final opts = await container.read(localAgentsProvider('').future);

    pin(
      opts.firstWhere((o) => o.id == 'a1'),
      ReferenceOption.agent(withPhone),
      label: 'Rossi',
      subtitle: '3331112222',
    );
    pin(
      opts.firstWhere((o) => o.id == 'a2'),
      ReferenceOption.agent(onlyEmail),
      label: 'Bianchi',
      subtitle: 'bianchi@x.it',
    );
  });
}
