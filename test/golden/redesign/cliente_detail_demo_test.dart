// test/golden/redesign/cliente_detail_demo_test.dart
//
// Review artifact for the redesigned Cliente detail. Seeds the local Drift mirror with the
// prototype's cliente — Rossi Srl in Milano, its sedi, referenti, contratti, interventi and asset —
// then writes `build/redesign/cliente_detail.png` (390×844) and
// `build/redesign/cliente_detail_full.png` (tall, so Documenti is visible too). Nothing here
// compares images, so the tests pass in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/cliente_detail_demo_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/customers/admin_customer_detail_screen.dart';

import 'redesign_harness.dart';

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-rossi',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2021, 4, 12),
          companyName: 'Rossi Srl',
          city: const Value('Milano'),
          address: const Value('Via Roma 1'),
          postalCode: const Value('20121'),
          country: const Value('Italia'),
          province: const Value('MI'),
          phone: const Value('02 1234567'),
          cellulare: const Value('333 1234567'),
          email: const Value('info@rossi.it'),
          contactPerson: const Value('Mario Rossi'),
          taxId: const Value('01234567890'),
          fiscalCode: const Value('01234567890'),
          sdiCode: const Value('M5UXCR1'),
          pec: const Value('rossi@pec.it'),
          notes: const Value(
            'Accesso dal cancello laterale. Chiedere di Mario.',
          ),
        ),
      );

  Future<void> location(String id, String name, String city) => db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2022, 1, 1),
          customerId: 'cust-rossi',
          name: name,
          city: Value(city),
        ),
      );
  await location('loc-milano', 'Sede Milano', 'Milano');
  await location('loc-sesto', 'Sede Sesto', 'Sesto San Giovanni');
  await location('loc-monza', 'Magazzino Monza', 'Monza');

  Future<void> contact(String id, String name, String role, String phone) => db
      .into(db.customerContacts)
      .insert(
        CustomerContactsCompanion.insert(
          id: id,
          customerId: 'cust-rossi',
          name: name,
          role: Value(role),
          phone: Value(phone),
        ),
      );
  await contact('ct-1', 'Mario Rossi', 'Titolare', '333 1234567');
  await contact('ct-2', 'Anna Bianchi', 'Amministrazione', '02 7654321');
  await contact('ct-3', 'Luca Verdi', 'Responsabile impianti', '348 9988776');

  Future<void> contract(String id, String name, {bool active = true}) => db
      .into(db.contracts)
      .insert(
        ContractsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2025, 1, 1),
          name: name,
          customerId: 'cust-rossi',
          startDate: DateTime.utc(2025, 1, 1),
          isActive: Value(active),
        ),
      );
  await contract('contr-1', 'Full service caldaie');
  await contract('contr-2', 'Manutenzione ascensori');
  await contract('contr-3', 'Contratto cessato', active: false);

  Future<void> ticket(
    String id,
    String title,
    String numero,
    DateTime createdAt,
  ) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: createdAt,
          title: title,
          numero: Value(numero),
          customerId: 'cust-rossi',
          locationId: 'loc-milano',
          statusId: 1,
          typeId: 1,
        ),
      );
  await ticket(
    't-1',
    'Perdita acqua caldaia',
    'INT-2026-0412',
    DateTime.utc(2026, 10, 28),
  );
  await ticket(
    't-2',
    'Sostituzione sifone bagno',
    'INT-2026-0388',
    DateTime.utc(2026, 10, 12),
  );
  await ticket(
    't-3',
    'Controllo annuale ascensore',
    'INT-2026-0351',
    DateTime.utc(2026, 9, 30),
  );

  await db
      .into(db.prodottiAssistenza)
      .insert(
        ProdottiAssistenzaCompanion.insert(
          id: 'prod-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2024, 1, 1),
          name: 'Caldaia Vaillant',
          customerId: 'cust-rossi',
          locationId: 'loc-milano',
          serialNumber: const Value('SN-9'),
          categoria: const Value('Caldaie'),
        ),
      );
}

List<Override> _overrides(AppDatabase db) => [
  appDatabaseProvider.overrideWithValue(db),
  isOnlineProvider.overrideWithValue(false),
];

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Cliente detail — writes build/redesign/cliente_detail.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'cliente_detail',
      child: const AdminCustomerDetailScreen(customerId: 'cust-rossi'),
      overrides: _overrides(db),
    );

    await db.close();
  });

  testWidgets(
    'Cliente detail full page — writes build/redesign/cliente_detail_full.png',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seed(db);

      await captureRedesign(
        tester,
        'cliente_detail_full',
        size: const Size(390, 1750),
        child: const AdminCustomerDetailScreen(customerId: 'cust-rossi'),
        overrides: _overrides(db),
      );

      await db.close();
    },
  );
}
