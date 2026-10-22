// dart format width=100
// test/features/ticket/ticket_materiali_editor_test.dart
//
// Widget tests for TicketMaterialiEditor — the Fabbisogno tab's edit mode, closing the gap where
// mobile could only VIEW a ticket's planned materials, never add/edit/remove a row (web's
// TicketMaterialiEditor.tsx already allowed this via the ticket detail page's Materials tab).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';
import 'package:tasktap_mobile/features/ticket/ticket_materiali_editor.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

Widget _wrap(Widget child, {required Dio dio}) {
  return ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

void main() {
  late MockDio mockDio;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    mockDio = MockDio();
  });

  testWidgets('starts with one row per initial dto, pre-filled', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [
            TicketMaterialeDto(
              id: 'row-1',
              materialeId: 'mat-1',
              codice: 'V-001',
              nome: 'Valvola',
              quantita: 2,
              unitaMisura: 'pz',
              disponibile: true,
            ),
          ],
          onSave: (_) async {},
          onCancel: () {},
        ),
        dio: mockDio,
      ),
    );

    expect(find.text('Valvola'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('pz'), findsOneWidget);
  });

  testWidgets('"Aggiungi materiale" appends a new empty row', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(initialRows: const [], onSave: (_) async {}, onCancel: () {}),
        dio: mockDio,
      ),
    );

    expect(find.byType(TextFormField), findsNothing);

    await tester.tap(find.text('Aggiungi materiale'));
    await tester.pumpAndSettle();

    // Article-search + quantity + unit + notes fields — one new row's worth.
    expect(find.byType(TextFormField), findsNWidgets(4));
  });

  testWidgets('remove button deletes the row', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [
            TicketMaterialeDto(
              id: 'row-1',
              nome: 'Guarnizione generica',
              quantita: 1,
              disponibile: true,
            ),
          ],
          onSave: (_) async {},
          onCancel: () {},
        ),
        dio: mockDio,
      ),
    );

    expect(find.text('Guarnizione generica'), findsOneWidget);

    await tester.tap(find.byTooltip('Rimuovi materiale'));
    await tester.pumpAndSettle();

    expect(find.text('Guarnizione generica'), findsNothing);
  });

  testWidgets('Salva calls onSave with the edited rows, mapped to the write shape', (
    tester,
  ) async {
    List<TicketMaterialeWriteRow>? savedRows;

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [
            TicketMaterialeDto(
              id: 'row-1',
              materialeId: 'mat-1',
              nome: 'Valvola',
              quantita: 2,
              unitaMisura: 'pz',
              disponibile: true,
            ),
          ],
          onSave: (rows) async => savedRows = rows,
          onCancel: () {},
        ),
        dio: mockDio,
      ),
    );

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(savedRows, isNotNull);
    expect(savedRows!.single.materialeId, 'mat-1');
    expect(savedRows!.single.freeTextName, isNull);
    expect(savedRows!.single.quantity, 2);
    expect(savedRows!.single.unitOfMeasure, 'pz');
  });

  testWidgets('Salva is disabled when a row has neither an article nor free text', (
    tester,
  ) async {
    var saveCalled = false;

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(initialRows: const [], onSave: (_) async {}, onCancel: () {}),
        dio: mockDio,
      ),
    );

    await tester.tap(find.text('Aggiungi materiale'));
    await tester.pumpAndSettle();

    // Empty row: neither an article nor free text — save must not run.
    final salvaFinder = find.text('Salva');
    await tester.tap(salvaFinder);
    await tester.pumpAndSettle();

    expect(saveCalled, isFalse);
  });

  testWidgets('Annulla calls onCancel', (tester) async {
    var cancelled = false;

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [],
          onSave: (_) async {},
          onCancel: () => cancelled = true,
        ),
        dio: mockDio,
      ),
    );

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
  });

  testWidgets('typing free text into a new row and saving sends freeTextName, not materialeId', (
    tester,
  ) async {
    List<TicketMaterialeWriteRow>? savedRows;
    when(
      () => mockDio.get<dynamic>('/Materiali', queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => _okResponse<dynamic>({'items': []}, '/Materiali'));

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [],
          onSave: (rows) async => savedRows = rows,
          onCancel: () {},
        ),
        dio: mockDio,
      ),
    );

    await tester.tap(find.text('Aggiungi materiale'));
    await tester.pumpAndSettle();

    // Field order within a row: Articolo (0), Quantità (1), Unità (2), Note (3) — see
    // _MaterialeRowEditorState.build.
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Guarnizione custom');
    await tester.pump();
    await tester.enterText(fields.at(1), '3');
    await tester.pump();

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(savedRows, isNotNull);
    expect(savedRows!.single.materialeId, isNull);
    expect(savedRows!.single.freeTextName, 'Guarnizione custom');
    expect(savedRows!.single.quantity, 3);
  });

  group('barcode scan', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.materiali)
          .insert(
            MaterialiCompanion.insert(
              id: 'mat-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              code: 'ART001',
              name: 'Valvola idraulica',
              unitOfMeasure: const Value('pz'),
            ),
          );
      await db
          .into(db.materialeBarcodes)
          .insert(
            MaterialeBarcodesCompanion.insert(
              id: 'bc-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              materialeId: 'mat-1',
              barcode: '8001234567890',
            ),
          );
    });

    tearDown(() => db.close());

    // Offline on purpose: an unknown code must resolve from the local mirror alone, with no
    // live-lookup call (the MockDio has no stub for it).
    Widget wrapScan(
      TicketMaterialiEditor editor,
    ) {
      return ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(mockDio),
          appDatabaseProvider.overrideWithValue(db),
          isOnlineProvider.overrideWithValue(false),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: editor))),
      );
    }

    TicketMaterialiEditor editorScanning(
      String? code,
      void Function(List<TicketMaterialeWriteRow>) onSaved,
    ) {
      return TicketMaterialiEditor(
        initialRows: const [],
        scanner: (_) async => code,
        onSave: (rows) async => onSaved(rows),
        onCancel: () {},
      );
    }

    testWidgets('shows the scan button', (tester) async {
      await tester.pumpWidget(wrapScan(editorScanning(null, (_) {})));

      expect(find.text('Scansiona codice'), findsOneWidget);

      // Disposes the toast overlay so its auto-dismiss Timer doesn't outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a known code adds the article as a row', (tester) async {
      List<TicketMaterialeWriteRow>? saved;
      await tester.pumpWidget(wrapScan(editorScanning('8001234567890', (r) => saved = r)));

      await tester.tap(find.text('Scansiona codice'));
      await tester.pumpAndSettle();

      expect(find.text('Valvola idraulica'), findsOneWidget);

      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(saved!.single.materialeId, 'mat-1');
      expect(saved!.single.freeTextName, isNull);
      expect(saved!.single.quantity, 1);
      expect(saved!.single.unitOfMeasure, 'pz');

      // Disposes the toast overlay so its auto-dismiss Timer doesn't outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('scanning the same code again increments the quantity, no second row', (
      tester,
    ) async {
      List<TicketMaterialeWriteRow>? saved;
      await tester.pumpWidget(wrapScan(editorScanning('8001234567890', (r) => saved = r)));

      await tester.tap(find.text('Scansiona codice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scansiona codice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(saved!.length, 1);
      expect(saved!.single.quantity, 2);

      // Disposes the toast overlay so its auto-dismiss Timer doesn't outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an unknown code becomes a free-text row and says so', (tester) async {
      List<TicketMaterialeWriteRow>? saved;
      await tester.pumpWidget(wrapScan(editorScanning('999000', (r) => saved = r)));

      await tester.tap(find.text('Scansiona codice'));
      await tester.pumpAndSettle();

      expect(find.textContaining('non in catalogo'), findsOneWidget);

      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(saved!.single.materialeId, isNull);
      expect(saved!.single.freeTextName, '999000');

      // Disposes the toast overlay so its auto-dismiss Timer doesn't outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('backing out of the scanner adds nothing', (tester) async {
      await tester.pumpWidget(wrapScan(editorScanning(null, (_) {})));

      await tester.tap(find.text('Scansiona codice'));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNothing);

      // Disposes the toast overlay so its auto-dismiss Timer doesn't outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('catalogue search', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.materiali)
          .insert(
            MaterialiCompanion.insert(
              id: 'mat-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              code: 'ART001',
              name: 'Valvola idraulica',
              unitOfMeasure: const Value('pz'),
            ),
          );
      await db
          .into(db.materiali)
          .insert(
            MaterialiCompanion.insert(
              id: 'mat-2',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              code: 'GUA002',
              name: 'Guarnizione testata',
            ),
          );
      // Retired by the office: it must not come back as a suggestion just because the row is
      // still in the mirror.
      await db
          .into(db.materiali)
          .insert(
            MaterialiCompanion.insert(
              id: 'mat-3',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              code: 'OLD003',
              name: 'Valvola dismessa',
              isActive: const Value(false),
            ),
          );
    });

    tearDown(() => db.close());

    /// Offline on purpose: the article field used to be a bare `GET /Materiali`, so on site it
    /// threw out of the debounce timer and silently offered nothing. MockDio has no stub here, so
    /// a live call would fail the test as well as the verifyNever below.
    Widget wrapSearch({Future<void> Function(List<TicketMaterialeWriteRow>)? onSave}) =>
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(mockDio),
            appDatabaseProvider.overrideWithValue(db),
            isOnlineProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TicketMaterialiEditor(
                  initialRows: const [],
                  onSave: onSave ?? (_) async {},
                  onCancel: () {},
                ),
              ),
            ),
          ),
        );

    Future<void> typeArticle(WidgetTester tester, String text) async {
      await tester.tap(find.text('Aggiungi materiale'));
      await tester.pumpAndSettle();

      // Articolo is the first field of the row — see _MaterialeRowEditorState.build.
      await tester.enterText(find.byType(TextFormField).at(0), text);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('offline it searches the mirrored catalogue and never calls the API', (
      tester,
    ) async {
      await tester.pumpWidget(wrapSearch());
      await typeArticle(tester, 'valvola');

      expect(find.text('Valvola idraulica'), findsWidgets);
      expect(find.text('Valvola dismessa'), findsNothing);
      verifyNever(
        () => mockDio.get<dynamic>(
          '/Materiali',
          queryParameters: any(named: 'queryParameters'),
        ),
      );
    });

    testWidgets('offline the code matches too — a technician may know the code, not the name', (
      tester,
    ) async {
      await tester.pumpWidget(wrapSearch());
      await typeArticle(tester, 'GUA002');

      expect(find.text('Guarnizione testata'), findsWidgets);
    });

    testWidgets('picking a mirrored article keeps its id and its unit', (tester) async {
      List<TicketMaterialeWriteRow>? saved;
      await tester.pumpWidget(wrapSearch(onSave: (rows) async => saved = rows));
      await typeArticle(tester, 'idraulica');

      await tester.tap(find.text('Valvola idraulica').last);
      await tester.pumpAndSettle();

      // Quantity is required before Salva does anything.
      await tester.enterText(find.byType(TextFormField).at(1), '2');
      await tester.pump();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.single.materialeId, 'mat-1');
      expect(saved!.single.unitOfMeasure, 'pz');
    });
  });
}
