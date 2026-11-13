// test/golden/redesign/sedi_list_demo_test.dart
//
// Review artifact for the redesigned Sedi list. Seeds the local Drift mirror with the prototype's
// customers, sedi and open/closed tickets, then writes `build/redesign/sedi_list.png`. Nothing
// here compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/sedi_list_demo_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/time/business_time.dart' show BusinessTime;
import 'package:tasktap_mobile/core/time/business_time_providers.dart'
    show businessTimeProvider;
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/locations/admin_location_list_screen.dart';

import 'redesign_harness.dart';

Future<void> _seed(AppDatabase db) async {
  Future<void> customer(String id, String name) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2021, 4, 12),
          companyName: name,
        ),
      );
  await customer('cust-rossi', 'Rossi Srl');
  await customer('cust-bianchi', 'Bianchi Srl');

  Future<void> location(
    String id,
    String customerId,
    String name,
    String address,
    String city,
  ) => db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2022, 1, 1),
          customerId: customerId,
          name: name,
          address: Value(address),
          city: Value(city),
        ),
      );
  await location(
    'loc-milano',
    'cust-rossi',
    'Sede Milano',
    'Via Roma 1',
    'Milano',
  );
  await location(
    'loc-monza',
    'cust-rossi',
    'Sede Monza',
    'Via Manzoni 4',
    'Monza',
  );
  await location(
    'loc-sesto',
    'cust-bianchi',
    'Sede Sesto',
    'Via Verdi 8',
    'Sesto',
  );

  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(1),
          tenantId: 'tenant-1',
          name: 'Aperto',
        ),
      );
  await db
      .into(db.ticketStatuses)
      .insert(
        TicketStatusesCompanion.insert(
          id: const Value(2),
          tenantId: 'tenant-1',
          name: 'Chiuso',
          isClosed: const Value(true),
        ),
      );

  Future<void> ticket(
    String id,
    String customerId,
    String locationId,
    int statusId,
  ) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10, 1),
          title: 'Ticket $id',
          customerId: customerId,
          locationId: locationId,
          statusId: statusId,
          typeId: 1,
        ),
      );
  await ticket('t1', 'cust-rossi', 'loc-milano', 1);
  await ticket('t2', 'cust-rossi', 'loc-milano', 1);
  await ticket('t3', 'cust-rossi', 'loc-milano', 2);
  await ticket('t4', 'cust-bianchi', 'loc-sesto', 1);
  // No ticket for Monza: the prototype's `0 ticket` row also says `Nessuna attività recente`.
}

List<Override> _overrides(AppDatabase db) => [
  appDatabaseProvider.overrideWithValue(db),
  businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
  cachedEntitlementProvider.overrideWith(
    (ref) => Future.value(
      Entitlement(
        features: const {},
        capabilities: const {'clienti.location.write'},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 9, 23),
      ),
    ),
  ),
];

/// Captures the open `Filtri` sheet. The shared harness captures `home` only and has no post-pump
/// hook, so this shot uses the same phone frame and writes a second review artifact.
Future<void> _captureFiltersSheet(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = redesignViewportSize * redesignDevicePixelRatio;
  tester.view.devicePixelRatio = redesignDevicePixelRatio;
  addTearDown(tester.view.reset);

  const key = ValueKey<String>('sedi-filters-capture');
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(db),
      child: RepaintBoundary(
        key: key,
        child: MediaQuery(
          data: const MediaQueryData(
            size: redesignViewportSize,
            devicePixelRatio: redesignDevicePixelRatio,
            padding: EdgeInsets.only(top: 28, bottom: 24),
            textScaler: TextScaler.noScaling,
          ),
          child: MaterialApp(
            theme: buildAppTheme(),
            debugShowCheckedModeBanner: false,
            home: const AdminLocationListScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();

  await tester.tap(find.text('FILTRI'));
  await tester.pumpAndSettle();

  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  late Uint8List bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: redesignDevicePixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('toByteData returned null for the filters sheet');
      }
      bytes = data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  });

  final directory = Directory(redesignOutputDirectory);
  if (!directory.existsSync()) directory.createSync(recursive: true);
  File('${directory.path}/sedi_list_filters.png')
      .writeAsBytesSync(bytes, flush: true);
  // ignore: avoid_print
  print(
    'redesign capture: ${File('${directory.path}/sedi_list_filters.png').absolute.path}',
  );

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Sedi list — writes build/redesign/sedi_list.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);

    await captureRedesign(
      tester,
      'sedi_list',
      child: const AdminLocationListScreen(),
      overrides: _overrides(db),
    );

    await db.close();
  });

  testWidgets('Sedi filters — writes build/redesign/sedi_list_filters.png', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seed(db);
    await _captureFiltersSheet(tester, db);
    await db.close();
  });
}
