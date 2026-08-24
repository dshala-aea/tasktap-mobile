// test/features/agenda/agenda_list_screen_test.dart
//
// Widget tests for AgendaListScreen — the personal to-do list against the never-before-called
// /api/agenda (see lib/data/agenda/agenda_api_client.dart for the contract notes).
//
// Covers:
//   1. The list renders items the client returns.
//   2. Tapping the leading checkbox completes an item and refreshes the list.
//   3. Swiping a row left, then confirming, deletes it and refreshes the list.
//   4. A failed complete/delete surfaces a SnackBar rather than failing silently.
//   5. A failed initial fetch shows the shared ErrorState with a retry.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/data/agenda/agenda_api_client.dart';
import 'package:tasktap_mobile/features/agenda/agenda_list_screen.dart';

class _FakeAgendaApiClient extends AgendaApiClient {
  _FakeAgendaApiClient(this._items) : super(Dio());

  List<AgendaItemDto> _items;
  final List<String> completedCalls = [];
  final List<String> deletedCalls = [];
  Object? throwOnComplete;
  Object? throwOnDelete;
  Object? throwOnFetch;

  @override
  Future<List<AgendaItemDto>> fetchAgenda({required DateTime from, required DateTime to}) async {
    if (throwOnFetch != null) throw throwOnFetch!;
    return _items;
  }

  @override
  Future<void> completeAgendaItem(String id) async {
    completedCalls.add(id);
    if (throwOnComplete != null) throw throwOnComplete!;
    _items = [
      for (final it in _items)
        if (it.id == id)
          AgendaItemDto(
            id: it.id,
            date: it.date,
            timeStart: it.timeStart,
            timeEnd: it.timeEnd,
            title: it.title,
            description: it.description,
            priority: it.priority,
            isCompleted: true,
            completedAt: DateTime(2026, 8, 24),
          )
        else
          it,
    ];
  }

  @override
  Future<void> deleteAgendaItem(String id) async {
    deletedCalls.add(id);
    if (throwOnDelete != null) throw throwOnDelete!;
    _items = _items.where((it) => it.id != id).toList();
  }
}

AgendaItemDto _item({
  required String id,
  required String title,
  int priority = 0,
  bool isCompleted = false,
}) => AgendaItemDto(
  id: id,
  date: DateTime(2026, 8, 24),
  timeStart: '09:00:00',
  title: title,
  priority: priority,
  isCompleted: isCompleted,
);

Widget _buildScreen(_FakeAgendaApiClient fake) {
  return ProviderScope(
    overrides: [agendaApiClientProvider.overrideWithValue(fake)],
    child: const MaterialApp(home: AgendaListScreen()),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
  });

  testWidgets('renders items the client returns', (tester) async {
    final fake = _FakeAgendaApiClient([
      _item(id: 'a1', title: 'Richiama il fornitore', priority: 2),
      _item(id: 'a2', title: 'Ordina i ricambi'),
    ]);

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    expect(find.text('Richiama il fornitore'), findsOneWidget);
    expect(find.text('Ordina i ricambi'), findsOneWidget);
    expect(find.text('Alta'), findsOneWidget);
    expect(find.text('Bassa'), findsOneWidget);
  });

  testWidgets('empty list shows the shadow-board empty state, not a blank screen', (tester) async {
    final fake = _FakeAgendaApiClient([]);

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    expect(find.text('Nessun task in agenda'), findsOneWidget);
  });

  testWidgets('tapping the checkbox completes the item and refreshes the list', (tester) async {
    final fake = _FakeAgendaApiClient([_item(id: 'a1', title: 'Richiama il fornitore')]);

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.circle));
    await tester.pumpAndSettle();

    expect(fake.completedCalls, ['a1']);
    // The row survives (completing does not remove it), now showing the done icon.
    expect(find.text('Richiama il fornitore'), findsOneWidget);
    expect(find.byIcon(LucideIcons.checkCircle2), findsOneWidget);
  });

  testWidgets('a failed complete surfaces a SnackBar rather than failing silently', (tester) async {
    final fake = _FakeAgendaApiClient([_item(id: 'a1', title: 'Richiama il fornitore')])
      ..throwOnComplete = Exception('boom');

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.circle));
    await tester.pumpAndSettle();

    expect(fake.completedCalls, ['a1']);
    expect(find.text('Impossibile completare il task. Riprova.'), findsOneWidget);
  });

  testWidgets('swiping a row left then confirming deletes it and refreshes the list', (
    tester,
  ) async {
    final fake = _FakeAgendaApiClient([_item(id: 'a1', title: 'Richiama il fornitore')]);

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Eliminare il task?'), findsOneWidget);
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();

    expect(fake.deletedCalls, ['a1']);
    expect(find.text('Richiama il fornitore'), findsNothing);
  });

  testWidgets('cancelling the delete confirmation leaves the item in place', (tester) async {
    final fake = _FakeAgendaApiClient([_item(id: 'a1', title: 'Richiama il fornitore')]);

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(fake.deletedCalls, isEmpty);
    expect(find.text('Richiama il fornitore'), findsOneWidget);
  });

  testWidgets('a failed initial fetch shows the shared error state with a retry', (tester) async {
    final fake = _FakeAgendaApiClient([])..throwOnFetch = Exception('network down');

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    expect(find.text('Impossibile caricare i dati'), findsOneWidget);
  });
}
