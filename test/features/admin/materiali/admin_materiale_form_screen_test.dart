// dart format width=100
// test/features/admin/materiali/admin_materiale_form_screen_test.dart
//
// The barcode section used to be gated behind edit mode entirely (`if (_isEditing) ...`), so
// creating a new materiale had no barcode UI at all to open — the ticket's "the modal is broken"
// was really "the modal doesn't exist yet during creation". These tests cover the fix: barcodes
// can be added while creating (held locally, flushed to the server right after create), and the
// add-barcode dialog's Barcode field now has a scan-icon entry point.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/materiali/admin_materiale_form_screen.dart';

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

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    await tester.pumpWidget(wrap(child));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('AdminMaterialeFormScreen — barcodes in create mode', () {
    testWidgets('shows the barcode section and add button while creating', (tester) async {
      await pump(tester, const AdminMaterialeFormScreen());

      expect(find.text('Barcode'), findsOneWidget);
      expect(find.text('Aggiungi barcode'), findsOneWidget);
      expect(find.text('Nessun barcode.'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('does not show the image section while creating', (tester) async {
      await pump(tester, const AdminMaterialeFormScreen());

      expect(find.text('Immagine'), findsNothing);

      await teardown(tester);
    });

    testWidgets('adding a barcode via the dialog shows it locally without calling the API', (
      tester,
    ) async {
      await pump(tester, const AdminMaterialeFormScreen());

      await tester.tap(find.text('Aggiungi barcode'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('add-barcode-dialog-barcode-field')),
        '8001234567890',
      );
      await tester.tap(find.text('Aggiungi').last);
      await tester.pumpAndSettle();

      expect(find.text('8001234567890'), findsOneWidget);
      // Distinguishes the barcode landing in _barcodes (rendered by _BarcodesSection, which
      // replaces this placeholder) from it merely still showing inside the dialog's own field.
      expect(find.text('Nessun barcode.'), findsNothing);
      verifyNever(() => mockDio.post<dynamic>(any(), data: any(named: 'data')));

      await teardown(tester);
    });

    testWidgets('saving flushes pending barcodes to the new materiale id', (tester) async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/materiali', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => _okResponse<Map<String, dynamic>>({'id': 'new-mat-1'}, '/api/materiali'),
      );
      when(
        () => mockDio.post<dynamic>(
          '/api/materiali/new-mat-1/barcodes',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okResponse(null, '/api/materiali/new-mat-1/barcodes'));

      await pump(tester, const AdminMaterialeFormScreen());

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'CODE1');
      await tester.enterText(fields.at(1), 'Materiale di test');

      await tester.tap(find.text('Aggiungi barcode'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add-barcode-dialog-barcode-field')),
        '8001234567890',
      );
      await tester.tap(find.text('Aggiungi').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crea materiale'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.post<dynamic>(
          '/api/materiali/new-mat-1/barcodes',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['barcode'], '8001234567890');

      await teardown(tester);
    });
  });
}
