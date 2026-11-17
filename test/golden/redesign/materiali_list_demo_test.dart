// test/golden/redesign/materiali_list_demo_test.dart
//
// Review artifact for the redesigned Materiali list. Seeds the local Drift mirror with the
// prototype's catalogue rows (stock facts dropped — they have no local source) and writes
// `build/redesign/materiali_list.png`; nothing here compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/materiali_list_demo_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/materiali/admin_materiale_list_screen.dart';

import 'redesign_harness.dart';

Future<void> _seed(AppDatabase db) async {
  Future<void> add({
    required String id,
    required String code,
    required String name,
    required String category,
    required double salePrice,
    bool active = true,
  }) => db
      .into(db.materiali)
      .insert(
        MaterialiCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          code: code,
          name: name,
          category: Value(category),
          salePrice: Value(salePrice),
          isActive: Value(active),
        ),
      );

  await add(
    id: 'm1',
    code: 'IDR-040',
    name: 'Sifone 40 mm',
    category: 'Idraulica',
    salePrice: 4.20,
  );
  await add(
    id: 'm2',
    code: 'IDR-012',
    name: 'Guarnizione 1/2',
    category: 'Idraulica',
    salePrice: 1.10,
  );
  await add(
    id: 'm3',
    code: 'IDR-015',
    name: 'Tubo rame 15',
    category: 'Idraulica',
    salePrice: 6.80,
  );
  await add(
    id: 'm4',
    code: 'ELE-030',
    name: 'Interruttore bipolare',
    category: 'Elettrica',
    salePrice: 3.00,
  );
  await add(
    id: 'm5',
    code: 'IDR-034',
    name: 'Raccordo 3/4',
    category: 'Idraulica',
    salePrice: 2.30,
    active: false,
  );
}

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Materiali list — writes build/redesign/materiali_list.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);
    await db.setLastSync(DateTime.utc(2026, 11, 5));

    await captureRedesign(
      tester,
      'materiali_list',
      child: const AdminMaterialeListScreen(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {},
              capabilities: const {'magazzino.article.write'},
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
