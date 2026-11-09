// test/golden/redesign/materiale_detail_demo_test.dart
//
// Review artifact for the redesigned Materiale detail. Writes
// `build/redesign/materiale_detail.png`; nothing here compares images.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/materiali/admin_materiale_detail_screen.dart';

import 'redesign_harness.dart';

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.materiali)
      .insert(
        MaterialiCompanion.insert(
          id: 'm1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          code: 'ART-040',
          name: 'Sifone 40 mm',
          category: const Value('Idraulica'),
          unitOfMeasure: const Value('pz'),
          marca: const Value('Acme'),
          purchasePrice: const Value(2.10),
          salePrice: const Value(4.20),
          description: const Value(
            'Sifone in ottone cromato con guarnizione rinforzata, compatibile con lavabi da '
            '40 mm. Include il kit di montaggio.',
          ),
        ),
      );
}

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Materiale detail — writes build/redesign/materiale_detail.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'materiale_detail',
      child: const AdminMaterialeDetailScreen(materialeId: 'm1'),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(false),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {},
              capabilities: const {'magazzino.article.write'},
              seatType: 'office',
              fetchedAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        ),
      ],
    );

    await db.close();
  });
}
