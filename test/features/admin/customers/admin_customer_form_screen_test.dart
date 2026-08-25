// test/features/admin/customers/admin_customer_form_screen_test.dart
//
// Gap 11 of the feature audit: the create/edit customer form had no isActive toggle even though
// `AdminApiClient.updateCustomer` already supports setting it.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/customers/admin_customer_form_screen.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio mockDio;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();
  });

  tearDown(() async => db.close());

  Widget wrap(Widget child) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(mockDio),
      isOnlineProvider.overrideWithValue(true),
    ],
    child: MaterialApp(home: child),
  );

  // Mirrors the `setSurfaceSize` + explicit-unmount convention documented in
  // admin_cantiere_detail_screen_test.dart: a tall surface so a field near the bottom of the
  // form's ListView isn't laid out below the fold, and an explicit unmount before the test ends
  // so any Drift stream subscription in the tree doesn't leave a pending Timer behind.
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    await tester.pumpWidget(wrap(child));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('AdminCustomerFormScreen — isActive toggle (Gap 11)', () {
    testWidgets('does not show the toggle in create mode', (tester) async {
      await pump(tester, const AdminCustomerFormScreen());

      expect(find.byType(AppToggle), findsNothing);

      await teardown(tester);
    });

    testWidgets('shows the toggle pre-filled from the cached customer in edit mode', (
      tester,
    ) async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'cust-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              companyName: 'ACME Srl',
              isActive: const Value(false),
            ),
          );

      await pump(tester, const AdminCustomerFormScreen(customerId: 'cust-1'));

      final toggle = tester.widget<AppToggle>(find.byType(AppToggle));
      expect(toggle.value, isFalse);

      await teardown(tester);
    });

    testWidgets('toggling and saving sends the flipped isActive to updateCustomer', (
      tester,
    ) async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'cust-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              companyName: 'ACME Srl',
              isActive: const Value(true),
            ),
          );
      when(
        () => mockDio.put<dynamic>('/api/customers/cust-1', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/customers/cust-1'));

      await pump(tester, const AdminCustomerFormScreen(customerId: 'cust-1'));

      await tester.tap(find.byType(AppToggle));
      await tester.pumpAndSettle();
      expect(tester.widget<AppToggle>(find.byType(AppToggle)).value, isFalse);

      await tester.tap(find.text('Salva modifiche'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.put<dynamic>('/api/customers/cust-1', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['isActive'], isFalse);

      await teardown(tester);
    });
  });
}
