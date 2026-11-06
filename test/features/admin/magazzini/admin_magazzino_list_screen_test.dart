// dart format width=100
// test/features/admin/magazzini/admin_magazzino_list_screen_test.dart
//
// The redesigned Magazzini list: shared list shell pieces, prototype chips, the real `Filtri`
// sheet, groups derived from `tipo`, and the online-first `magazziniProvider` states.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/magazzino/magazzino_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/magazzini/admin_magazzino_list_screen.dart';

class _FakeMagazzinoApiClient extends MagazzinoApiClient {
  _FakeMagazzinoApiClient(this.magazzini) : super(Dio());

  final List<MagazzinoDto> magazzini;

  @override
  Future<List<MagazzinoDto>> getMagazzini({bool? isActive, String? tipo}) async => magazzini;
}

class _FailingMagazzinoApiClient extends MagazzinoApiClient {
  _FailingMagazzinoApiClient() : super(Dio());

  @override
  Future<List<MagazzinoDto>> getMagazzini({bool? isActive, String? tipo}) async =>
      throw Exception('boom');
}

MagazzinoDto _sede(String id, String nome, {String? indirizzo, bool isActive = true}) =>
    MagazzinoDto(id: id, nome: nome, tipo: 'Sede', indirizzo: indirizzo, isActive: isActive);

MagazzinoDto _furgone(String id, String nome, {String? assegnatoUserId, bool isActive = true}) =>
    MagazzinoDto(
      id: id,
      nome: nome,
      tipo: 'Furgone',
      assegnatoUserId: assegnatoUserId,
      isActive: isActive,
    );

List<MagazzinoDto> _prototypeRows() => [
  _sede('m1', 'Magazzino Milano', indirizzo: 'Via Roma 1'),
  _sede('m2', 'Magazzino Monza', indirizzo: 'Via Manzoni 4'),
  _furgone('m3', 'Furgone 3', assegnatoUserId: 'u-daniel'),
];

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedColleagues(AppDatabase db) async {
  await db
      .into(db.colleagues)
      .insert(ColleaguesCompanion.insert(id: 'u-daniel', displayName: 'Daniel Shala'));
}

Widget _screen(
  AppDatabase db, {
  MagazzinoApiClient? api,
  bool online = true,
  Entitlement? entitlement,
}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    isOnlineProvider.overrideWithValue(online),
    magazzinoApiClientProvider.overrideWithValue(api ?? _FakeMagazzinoApiClient(_prototypeRows())),
    if (entitlement != null)
      cachedEntitlementProvider.overrideWith((ref) => Future.value(entitlement)),
  ],
  child: const MaterialApp(home: AdminMagazzinoListScreen()),
);

Entitlement _entitlement(Set<String> capabilities) => Entitlement(
  features: const {'magazzino'},
  capabilities: capabilities,
  seatType: 'office',
  fetchedAt: DateTime.utc(2026, 11, 5),
);

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db, {
  MagazzinoApiClient? api,
  bool online = true,
  Entitlement? entitlement,
}) async {
  await tester.pumpWidget(_screen(db, api: api, online: online, entitlement: entitlement));
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.text('FILTRI'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('groups principali/secondari with the prototype row anatomy', (tester) async {
    await _seedColleagues(db);
    await _pump(tester, db);

    expect(find.text('Principali'), findsOneWidget);
    expect(find.text('Secondari'), findsOneWidget);
    expect(find.text('Magazzino Milano'), findsOneWidget);
    expect(find.text('Via Roma 1'), findsOneWidget);
    expect(find.text('Assegnato a Daniel Shala'), findsOneWidget);
    expect(find.text('PRINCIPALE'), findsNWidgets(2));
    expect(find.text('SECONDARIO'), findsOneWidget);
    expect(find.text('3 MAGAZZINI'), findsOneWidget);
    expect(find.text('3 ATTIVI'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('the quick chips filter the two groups', (tester) async {
    await _seedColleagues(db);
    await _pump(tester, db);

    await tester.tap(find.text('SECONDARI'));
    await tester.pumpAndSettle();
    expect(find.text('Furgone 3'), findsOneWidget);
    expect(find.text('Magazzino Milano'), findsNothing);
    expect(find.text('Principali'), findsNothing);

    await tester.tap(find.text('PRINCIPALI'));
    await tester.pumpAndSettle();
    expect(find.text('Furgone 3'), findsNothing);
    expect(find.text('Magazzino Milano'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('search covers name, type, address and assigned technician', (tester) async {
    await _seedColleagues(db);
    await _pump(tester, db);

    await tester.enterText(find.byType(TextField), 'manzoni');
    await tester.pumpAndSettle();
    expect(find.text('Magazzino Monza'), findsOneWidget);
    expect(find.text('Magazzino Milano'), findsNothing);

    await tester.enterText(find.byType(TextField), 'furgone');
    await tester.pumpAndSettle();
    expect(find.text('Furgone 3'), findsOneWidget);
    expect(find.text('Magazzino Monza'), findsNothing);

    await tester.enterText(find.byType(TextField), 'daniel');
    await tester.pumpAndSettle();
    expect(find.text('Furgone 3'), findsOneWidget);
    expect(find.text('Magazzino Milano'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('the Filtri sheet filters by status and type, and Azzera clears it', (tester) async {
    await _seedColleagues(db);
    await _pump(tester, db);

    await _openFilters(tester);
    await tester.tap(find.byKey(const ValueKey('magazziniFilterStatus-secondari')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('magazziniFilterApply')));
    await tester.pumpAndSettle();

    expect(find.text('Furgone 3'), findsOneWidget);
    expect(find.text('Magazzino Milano'), findsNothing);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('magazziniFilterReset')));
    await tester.pumpAndSettle();
    expect(find.text('Magazzino Milano'), findsOneWidget);
    expect(find.text('Furgone 3'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('the Tipo field is the same facet as the status chips', (tester) async {
    await _seedColleagues(db);
    await _pump(tester, db);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('magazziniFilterTipo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Furgone').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('magazziniFilterApply')));
    await tester.pumpAndSettle();

    expect(find.text('Furgone 3'), findsOneWidget);
    expect(find.text('Magazzino Milano'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('an inactive warehouse keeps an Inattivo stamp and is not counted active', (
    tester,
  ) async {
    await _seedColleagues(db);
    final api = _FakeMagazzinoApiClient([
      _sede('m1', 'Magazzino Milano', indirizzo: 'Via Roma 1'),
      _sede('m2', 'Magazzino Chiuso', isActive: false),
      _furgone('m3', 'Furgone 3', assegnatoUserId: 'u-daniel'),
    ]);
    await _pump(tester, db, api: api);

    expect(find.text('INATTIVO'), findsOneWidget);
    expect(find.text('2 ATTIVI'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('never-synced offline says the warehouses were not downloaded', (tester) async {
    await _pump(tester, db, online: false);

    expect(find.text('Magazzini non disponibili offline'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('a fetch failure offers a retry', (tester) async {
    await _pump(tester, db, api: _FailingMagazzinoApiClient());

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('a genuinely empty catalogue shows the create hint', (tester) async {
    await _pump(tester, db, api: _FakeMagazzinoApiClient(const []));

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nessun magazzino'), findsOneWidget);
    expect(find.textContaining('Usa Nuovo'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('Nuovo is shown only with magazzino.warehouse.write', (tester) async {
    await _pump(tester, db, entitlement: _entitlement({'magazzino.warehouse.write'}));
    expect(find.byType(ListHeaderAction), findsOneWidget);

    await _dispose(tester);

    await _pump(tester, db, entitlement: _entitlement({'magazzino.warehouse.read'}));
    expect(find.byType(ListHeaderAction), findsNothing);

    await _dispose(tester);
  });

  testWidgets('renders without overflow at 320px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _seedColleagues(db);
    await _pump(tester, db);

    expect(tester.takeException(), null);
    expect(find.text('Magazzino Milano'), findsOneWidget);

    await _dispose(tester);
  });
}
