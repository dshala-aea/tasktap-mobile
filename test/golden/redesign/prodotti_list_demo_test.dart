// test/golden/redesign/prodotti_list_demo_test.dart
//
// Review artifact for the wave-1 Prodotti in assistenza list redesign: renders the real screen
// with the prototype's three assets served by a fake API and writes
// `build/redesign/prodotti_list.png`. Nothing here compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/prodotti_list_demo_test.dart

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/prodotti/admin_prodotto_list_screen.dart';

import 'redesign_harness.dart';

final _fixedNow = DateTime.utc(2026, 11, 5, 12);

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient(this.prodotti) : super(Dio());

  final List<Map<String, dynamic>> prodotti;

  @override
  Future<List<Map<String, dynamic>>> fetchProdottiAssistenza({
    String? customerId,
    String? q,
  }) async => prodotti;
}

Map<String, dynamic> _row({
  required String id,
  required String name,
  required String customerId,
  required String customerName,
  required String serial,
  String? warrantyExpiryDate,
  String? prossimaManutenzione,
  String? ultimaManutenzione,
}) => {
  'id': id,
  'name': name,
  'customerId': customerId,
  'customerName': customerName,
  'locationId': 'loc-1',
  'isActive': true,
  'serialNumber': serial,
  'categoria': 'Caldaie',
  'warrantyExpiryDate': warrantyExpiryDate,
  'prossimaManutenzione': prossimaManutenzione,
  'ultimaManutenzione': ultimaManutenzione,
};

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
    await loadRedesignFonts();
  });

  testWidgets(
    'Prodotti in assistenza list — writes build/redesign/prodotti_list.png',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final api = _FakeAdminApiClient([
        _row(
          id: 'p1',
          name: 'Caldaia Vaillant',
          customerId: 'cust-rossi',
          customerName: 'Rossi Srl',
          serial: 'SN-9',
          warrantyExpiryDate: '2027-06-01',
          prossimaManutenzione: '2026-12-03',
        ),
        _row(
          id: 'p2',
          name: 'Climatizzatore Daikin',
          customerId: 'cust-bianchi',
          customerName: 'Bianchi Srl',
          serial: 'SN-14',
          warrantyExpiryDate: '2028-01-01',
          prossimaManutenzione: '2026-11-05',
        ),
        _row(
          id: 'p3',
          name: 'Caldaia Baxi',
          customerId: 'cust-verdi',
          customerName: 'Verdi Spa',
          serial: 'SN-2',
          warrantyExpiryDate: '2025-01-01',
          ultimaManutenzione: '2026-10-02',
        ),
      ]);

      await captureRedesign(
        tester,
        'prodotti_list',
        child: const AdminProdottoListScreen(),
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          adminApiClientProvider.overrideWithValue(api),
          isOnlineProvider.overrideWithValue(true),
          clockProvider.overrideWithValue(() => _fixedNow),
        ],
      );

      await db.close();
    },
  );
}
