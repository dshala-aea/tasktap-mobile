// test/golden/redesign/magazzini_list_demo_test.dart
//
// Review artifact for the wave-1 Magazzini list redesign. Serves the prototype's four warehouses
// through a fake API (the list is online-first) and writes `build/redesign/magazzini_list.png`.
// Nothing here compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/magazzini_list_demo_test.dart

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/magazzino/magazzino_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/magazzini/admin_magazzino_list_screen.dart';

import 'redesign_harness.dart';

class _FakeMagazzinoApiClient extends MagazzinoApiClient {
  _FakeMagazzinoApiClient(this.magazzini) : super(Dio());

  final List<MagazzinoDto> magazzini;

  @override
  Future<List<MagazzinoDto>> getMagazzini({
    bool? isActive,
    String? tipo,
  }) async => magazzini;
}

MagazzinoDto _sede(String id, String nome, String indirizzo) => MagazzinoDto(
  id: id,
  nome: nome,
  tipo: 'Sede',
  indirizzo: indirizzo,
  isActive: true,
);

MagazzinoDto _furgone(
  String id,
  String nome, {
  String? assegnatoUserId,
  bool isActive = true,
}) => MagazzinoDto(
  id: id,
  nome: nome,
  tipo: 'Furgone',
  assegnatoUserId: assegnatoUserId,
  isActive: isActive,
);

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Magazzini list — writes build/redesign/magazzini_list.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.colleagues)
        .insert(
          ColleaguesCompanion.insert(
            id: 'u-daniel',
            displayName: 'Daniel Shala',
          ),
        );

    final api = _FakeMagazzinoApiClient([
      _sede('m1', 'Magazzino Milano', 'Via Roma 1'),
      _sede('m2', 'Magazzino Monza', 'Via Manzoni 4'),
      _furgone('m3', 'Furgone 3', assegnatoUserId: 'u-daniel'),
      // The prototype footer says "4 magazzini · 3 attivi"; the fourth is the inactive one.
      _furgone('m4', 'Furgone 7', isActive: false),
    ]);

    await captureRedesign(
      tester,
      'magazzini_list',
      child: const AdminMagazzinoListScreen(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        magazzinoApiClientProvider.overrideWithValue(api),
        isOnlineProvider.overrideWithValue(true),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {'magazzino'},
              capabilities: const {'magazzino.warehouse.write'},
              seatType: 'office',
              fetchedAt: DateTime.utc(2026, 11, 5),
            ),
          ),
        ),
      ],
    );

    await db.close();
  });
}
