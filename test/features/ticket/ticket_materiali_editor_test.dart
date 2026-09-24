// dart format width=100
// test/features/ticket/ticket_materiali_editor_test.dart
//
// Widget tests for TicketMaterialiEditor — the Fabbisogno tab's edit mode, closing the gap where
// mobile could only VIEW a ticket's planned materials, never add/edit/remove a row (web's
// TicketMaterialiEditor.tsx already allowed this via the ticket detail page's Materials tab).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
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
}
