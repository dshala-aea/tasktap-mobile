// test/golden/redesign/pianificazioni_demo_test.dart
//
// Review artifacts for the redesigned Pianificazioni list and detail. Seeds the local Drift
// mirror with the prototype's people, sedi, ticket and contract, then writes
// `build/redesign/pianificazioni_list.png` and `build/redesign/pianificazione_detail.png`.
// Nothing here compares images, so the tests pass in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/pianificazioni_demo_test.dart

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
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/schedules/admin_schedule_detail_screen.dart';
import 'package:tasktap_mobile/features/admin/schedules/admin_schedule_list_screen.dart';

import 'redesign_harness.dart';

/// Wednesday 4 November 2026, 12:00 Rome — the prototype's "Oggi 14:00".
final _now = DateTime.utc(2026, 11, 4, 11);

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-rossi',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2021, 4, 12),
          companyName: 'Rossi Srl',
        ),
      );
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: 'cust-verdi',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2021, 4, 12),
          companyName: 'Verdi Spa',
        ),
      );

  Future<void> colleague(String id, String name) => db
      .into(db.colleagues)
      .insert(ColleaguesCompanion.insert(id: id, displayName: name));
  await colleague('u-daniel', 'Daniel Shala');
  await colleague('u-marco', 'Marco Rossi');
  await colleague('u-luca', 'Luca Bianchi');

  Future<void> location(String id, String customerId, String name) => db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2022, 1, 1),
          customerId: customerId,
          name: name,
        ),
      );
  await location('loc-milano', 'cust-rossi', 'Sede Milano');
  await location('loc-sesto', 'cust-rossi', 'Sede Sesto');
  await location('loc-monza', 'cust-verdi', 'Sede Monza');

  await db
      .into(db.contracts)
      .insert(
        ContractsCompanion.insert(
          id: 'contract-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2025, 1, 1),
          name: 'Full service',
          customerId: 'cust-rossi',
          startDate: DateTime.utc(2025, 1, 1),
        ),
      );

  await db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: 'ticket-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10, 28),
          title: 'Perdita acqua caldaia',
          customerId: 'cust-rossi',
          locationId: 'loc-milano',
          statusId: 1,
          typeId: 1,
          contractId: const Value('contract-1'),
        ),
      );

  Future<void> schedule({
    required String id,
    required DateTime date,
    required int start,
    required int end,
    required String userId,
    required String locationId,
    required String title,
    int statusId = 1,
    String? ticketId,
  }) => db
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 10, 20),
          activityDate: date,
          timeStartMinutes: start,
          timeEndMinutes: end,
          userId: userId,
          statusId: statusId,
          locationId: locationId,
          title: title,
          description: id == 'sched-1'
              ? 'Portare i dispositivi di protezione. Accesso dal cancello laterale.'
              : '',
          ticketId: Value(ticketId),
        ),
      );

  await schedule(
    id: 'sched-1',
    date: DateTime.utc(2026, 11, 4),
    start: 840,
    end: 900,
    userId: 'u-daniel',
    locationId: 'loc-milano',
    title: 'Sopralluogo Rossi',
    ticketId: 'ticket-1',
  );
  await schedule(
    id: 'sched-2',
    date: DateTime.utc(2026, 11, 4),
    start: 990,
    end: 1050,
    userId: 'u-marco',
    locationId: 'loc-sesto',
    title: 'Manutenzione Bianchi',
  );
  await schedule(
    id: 'sched-3',
    date: DateTime.utc(2026, 11, 5),
    start: 540,
    end: 600,
    userId: 'u-luca',
    locationId: 'loc-monza',
    title: 'Installazione Verdi',
    statusId: 999,
  );
}

List<Override> _overrides(AppDatabase db) => [
  appDatabaseProvider.overrideWithValue(db),
  businessTimeProvider.overrideWithValue(
    BusinessTime('Europe/Rome', clock: () => _now),
  ),
  cachedEntitlementProvider.overrideWith(
    (ref) => Future.value(
      Entitlement(
        features: const {},
        capabilities: const {'pianificazione.schedule.write'},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
    ),
  ),
];

Future<void> _writeBoundary(
  WidgetTester tester,
  Key key,
  String screenName,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  late Uint8List bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: redesignDevicePixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('toByteData returned null for $screenName');
      }
      bytes = data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  });

  final directory = Directory(redesignOutputDirectory);
  if (!directory.existsSync()) directory.createSync(recursive: true);
  File('${directory.path}/$screenName.png')
      .writeAsBytesSync(bytes, flush: true);
  // ignore: avoid_print
  print(
    'redesign capture: ${File('${directory.path}/$screenName.png').absolute.path}',
  );
}

/// Captures the elenco tab. The shared harness writes immediately after pumping, so this shot
/// opens the tab first and then writes the same phone frame.
Future<void> _captureElenco(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = redesignViewportSize * redesignDevicePixelRatio;
  tester.view.devicePixelRatio = redesignDevicePixelRatio;
  addTearDown(tester.view.reset);

  const key = ValueKey<String>('pianificazioni-list-capture');
  await tester.pumpWidget(
    ProviderScope(retry: (_, _) => null, 
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
            home: const AdminScheduleListScreen(),
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

  await tester.tap(find.text('Elenco'));
  await tester.pumpAndSettle();

  await _writeBoundary(tester, key, 'pianificazioni_list');

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
    ensureTimeZonesInitialized();
    await loadRedesignFonts();
  });

  testWidgets(
    'Pianificazioni list — writes build/redesign/pianificazioni_list.png',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seed(db);
      await _captureElenco(tester, db);
      await db.close();
    },
  );

  testWidgets(
    'Pianificazione detail — writes build/redesign/pianificazione_detail.png',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seed(db);

      await captureRedesign(
        tester,
        'pianificazione_detail',
        child: const AdminScheduleDetailScreen(scheduleId: 'sched-1'),
        overrides: _overrides(db),
      );

      await db.close();
    },
  );
}
