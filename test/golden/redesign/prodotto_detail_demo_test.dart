// test/golden/redesign/prodotto_detail_demo_test.dart
//
// Review artifact for the redesigned Prodotto in assistenza detail. Seeds the local Drift mirror
// with the prototype's customer, sede and intervention history, then writes
// `build/redesign/prodotto_detail.png`. Nothing here compares images.
//
// Run:
//   fvm flutter test --no-pub test/golden/redesign/prodotto_detail_demo_test.dart

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/prodotti/admin_prodotto_detail_screen.dart';

import 'redesign_harness.dart';

final _fixedNow = DateTime.utc(2026, 11, 5, 12);

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient() : super(Dio());

  @override
  Future<List<Map<String, dynamic>>> fetchMatricole(String prodottoId) async =>
      [
        {'id': 'm1', 'numero': 'SN-9', 'note': 'Matricola principale'},
      ];
}

Entitlement _entitlement() => Entitlement(
  features: const {},
  capabilities: const {'contratti.contract.write'},
  seatType: 'office',
  fetchedAt: DateTime.utc(2026, 1, 1),
);

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2021, 4, 12),
          companyName: 'Rossi Srl',
        ),
      );
  await db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: 'loc-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2022, 1, 1),
          customerId: 'cust-1',
          name: 'Sede Milano',
          address: const Value('Via Roma 1'),
          city: const Value('Milano'),
        ),
      );

  Future<void> status(int id, String name, {bool closed = false}) => db
      .into(db.ticketStatuses)
      .insertOnConflictUpdate(
        TicketStatusesCompanion.insert(
          id: Value(id),
          tenantId: 'tenant-1',
          name: name,
          isClosed: Value(closed),
        ),
      );
  await status(1, 'Chiuso', closed: true);
  await status(2, 'Aperto');

  Future<void> ticket({
    required String id,
    required String title,
    required String numero,
    required int statusId,
    required DateTime createdAt,
  }) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: createdAt,
          title: title,
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: statusId,
          typeId: 1,
          numero: Value(numero),
          prodottoAssistenzaIdsJson: const Value('["prod-1"]'),
          closedAt: Value(
            statusId == 1 ? createdAt.add(const Duration(days: 1)) : null,
          ),
        ),
      );

  await ticket(
    id: 't1',
    title: 'Sostituzione valvola',
    numero: 'INT-2026-0412',
    statusId: 1,
    createdAt: DateTime.utc(2026, 10, 3, 9),
  );
  await ticket(
    id: 't2',
    title: 'Controllo fumi',
    numero: 'INT-2026-0388',
    statusId: 2,
    createdAt: DateTime.utc(2026, 9, 12, 14),
  );
}

const _prodotto = {
  'id': 'prod-1',
  'name': 'Caldaia Vaillant',
  'codice': 'CAL-01',
  'serialNumber': 'SN-9',
  'marchio': 'Vaillant',
  'modello': 'EcoTEC Plus',
  'tipo': 'Caldaia',
  'categoria': 'Caldaie',
  'um': 'pz',
  'customerId': 'cust-1',
  'locationId': 'loc-1',
  'isActive': true,
  'warrantyExpiryDate': '2027-06-01T00:00:00Z',
  'ultimaManutenzione': '2026-10-03T00:00:00Z',
  'prossimaManutenzione': '2026-12-03T00:00:00Z',
  'dataInstallazione': '2024-05-10T00:00:00Z',
  'externalId': 'EXT-1',
  'description': 'Caldaia a condensazione installata in centrale termica.',
  'notes': 'Accesso dalla scala interna.',
};

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets(
    'Prodotto in assistenza detail — writes build/redesign/prodotto_detail.png',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seed(db);

      await captureRedesign(
        tester,
        'prodotto_detail',
        child: const AdminProdottoDetailScreen(prodotto: _prodotto),
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          adminApiClientProvider.overrideWithValue(_FakeAdminApiClient()),
          cachedEntitlementProvider.overrideWith(
            (ref) => Future.value(_entitlement()),
          ),
          clockProvider.overrideWithValue(() => _fixedNow),
          isOnlineProvider.overrideWithValue(false),
        ],
      );

      await captureRedesign(
        tester,
        'prodotto_detail_full',
        size: const Size(390, 1700),
        child: const AdminProdottoDetailScreen(prodotto: _prodotto),
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          adminApiClientProvider.overrideWithValue(_FakeAdminApiClient()),
          cachedEntitlementProvider.overrideWith(
            (ref) => Future.value(_entitlement()),
          ),
          clockProvider.overrideWithValue(() => _fixedNow),
          isOnlineProvider.overrideWithValue(false),
        ],
      );

      await db.close();
    },
  );
}
