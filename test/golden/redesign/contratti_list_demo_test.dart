// test/golden/redesign/contratti_list_demo_test.dart
//
// Review artifact for the wave-1 Contratti list redesign. Seeds the local customer mirror and a
// fake server payload (the mirror cannot carry autoRenewal/scadenzaGiorni), then writes
// `build/redesign/contratti_list.png`; nothing here compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/contratti_list_demo_test.dart

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart'
    show BusinessTime, formatDateOnly;
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/contracts/admin_contract_list_screen.dart';

import 'redesign_harness.dart';

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient(this.contracts) : super(Dio());

  final List<Map<String, dynamic>> contracts;

  @override
  Future<List<Map<String, dynamic>>> fetchContracts({
    String? customerId,
  }) async => contracts;
}

Future<void> _seedCustomers(AppDatabase db) async {
  Future<void> customer(String id, String name) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: name,
        ),
      );

  await customer('cust-rossi', 'Rossi Srl');
  await customer('cust-bianchi', 'Bianchi Srl');
  await customer('cust-verdi', 'Verdi Spa');
}

List<Map<String, dynamic>> _serverRows() {
  final today = BusinessTime.fallback().businessToday();
  String date(int offsetDays) =>
      formatDateOnly(today.add(Duration(days: offsetDays)))!;

  return [
    {
      'id': 'ctr-1',
      'name': 'Full service',
      'customerId': 'cust-rossi',
      'endDate': date(20),
      'isActive': true,
      'autoRenewal': true,
      'scadenzaGiorni': 30,
    },
    {
      'id': 'ctr-2',
      'name': 'Manutenzione caldaie',
      'customerId': 'cust-bianchi',
      'endDate': date(15),
      'isActive': true,
      'autoRenewal': false,
    },
    {
      'id': 'ctr-3',
      'name': 'Assistenza impianti',
      'customerId': 'cust-verdi',
      'endDate': date(400),
      'isActive': true,
      'autoRenewal': true,
    },
  ];
}

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Contratti list — writes build/redesign/contratti_list.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seedCustomers(db);

    await captureRedesign(
      tester,
      'contratti_list',
      child: const AdminContractListScreen(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        adminApiClientProvider.overrideWithValue(
          _FakeAdminApiClient(_serverRows()),
        ),
        isOnlineProvider.overrideWithValue(true),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {},
              capabilities: const {'contratti.contract.write'},
              seatType: 'office',
              fetchedAt: DateTime.utc(2026, 9, 23),
            ),
          ),
        ),
      ],
    );

    await db.close();
  });
}
