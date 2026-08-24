// test/features/agenda/agenda_form_screen_test.dart
//
// Widget tests for AgendaFormScreen (create/edit).
//
// Covers:
//   1. Create: fills in title/date/priority, calls createAgendaItem, refreshes the list, pops.
//   2. Edit: pre-fills from the passed-in item, calls updateAgendaItem with its id and the
//      item's own timeEnd preserved (AgendaApiClient.updateAgendaItem's contract note).
//   3. Empty title blocks submission — no API call.
//   4. A failed save surfaces a SnackBar instead of failing silently, and does not pop.
//   5. Offline blocks the save with the shared offline warning, before any API call.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/agenda/agenda_api_client.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/agenda/agenda_form_screen.dart';

class _FakeAgendaApiClient extends AgendaApiClient {
  _FakeAgendaApiClient() : super(Dio());

  final List<Map<String, dynamic>> createCalls = [];
  final List<Map<String, dynamic>> updateCalls = [];
  Object? throwOnCreate;
  Object? throwOnUpdate;

  @override
  Future<String> createAgendaItem({
    required DateTime date,
    String? timeStart,
    String? timeEnd,
    required String title,
    String? description,
    int priority = 0,
  }) async {
    createCalls.add({
      'date': date,
      'timeStart': timeStart,
      'timeEnd': timeEnd,
      'title': title,
      'priority': priority,
    });
    if (throwOnCreate != null) throw throwOnCreate!;
    return 'new-1';
  }

  @override
  Future<void> updateAgendaItem(
    String id, {
    required DateTime date,
    String? timeStart,
    String? timeEnd,
    required String title,
    String? description,
    int priority = 0,
  }) async {
    updateCalls.add({
      'id': id,
      'date': date,
      'timeStart': timeStart,
      'timeEnd': timeEnd,
      'title': title,
      'priority': priority,
    });
    if (throwOnUpdate != null) throw throwOnUpdate!;
  }
}

GoRouter _makeRouter({AgendaItemDto? item}) => GoRouter(
  initialLocation: '/list',
  routes: [
    GoRoute(path: '/list', builder: (_, _) => const Scaffold(body: Center(child: Text('LISTA')))),
    GoRoute(path: '/form', builder: (_, _) => AgendaFormScreen(item: item)),
  ],
);

Widget _buildApp(_FakeAgendaApiClient fake, GoRouter router, {bool online = true}) {
  return ProviderScope(
    overrides: [
      agendaApiClientProvider.overrideWithValue(fake),
      isOnlineProvider.overrideWithValue(online),
      cachedEntitlementProvider.overrideWith((ref) => null),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
  });

  testWidgets('creating fills the title and calls createAgendaItem, then pops back', (
    tester,
  ) async {
    final fake = _FakeAgendaApiClient();
    final router = _makeRouter();
    await tester.pumpWidget(_buildApp(fake, router));
    await tester.pumpAndSettle();

    router.push('/form');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Richiama il fornitore');
    await tester.tap(find.text('Crea task'));
    await tester.pumpAndSettle();

    expect(fake.createCalls, hasLength(1));
    expect(fake.createCalls.single['title'], 'Richiama il fornitore');
    expect(fake.createCalls.single['priority'], 0);
    // No time picked — timeStart stays null rather than defaulting to midnight.
    expect(fake.createCalls.single['timeStart'], isNull);

    // Popped back to the screen that pushed the form.
    expect(find.text('LISTA'), findsOneWidget);
  });

  testWidgets('editing pre-fills from the item and calls updateAgendaItem with its id', (
    tester,
  ) async {
    final fake = _FakeAgendaApiClient();
    final item = AgendaItemDto(
      id: 'a1',
      date: DateTime(2026, 8, 24),
      timeStart: '09:00:00',
      timeEnd: '10:00:00',
      title: 'Ordina i ricambi',
      priority: 2,
    );
    final router = _makeRouter(item: item);
    await tester.pumpWidget(_buildApp(fake, router));
    await tester.pumpAndSettle();

    router.push('/form');
    await tester.pumpAndSettle();

    // Pre-filled from the item.
    expect(find.text('Ordina i ricambi'), findsOneWidget);
    expect(find.text('Modifica task'), findsOneWidget);

    await tester.tap(find.text('Salva modifiche'));
    await tester.pumpAndSettle();

    expect(fake.updateCalls, hasLength(1));
    final call = fake.updateCalls.single;
    expect(call['id'], 'a1');
    expect(call['title'], 'Ordina i ricambi');
    expect(call['priority'], 2);
    // The item's existing timeEnd survives the round trip even though the form has no field for
    // it — see AgendaApiClient.updateAgendaItem's doc for why omitting it would clear it.
    expect(call['timeEnd'], '10:00:00');
  });

  testWidgets('an empty title blocks submission', (tester) async {
    final fake = _FakeAgendaApiClient();
    final router = _makeRouter();
    await tester.pumpWidget(_buildApp(fake, router));
    await tester.pumpAndSettle();

    router.push('/form');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crea task'));
    await tester.pumpAndSettle();

    expect(fake.createCalls, isEmpty);
    expect(find.text('Campo obbligatorio'), findsOneWidget);
  });

  testWidgets('a failed save shows a SnackBar and does not pop', (tester) async {
    final fake = _FakeAgendaApiClient()..throwOnCreate = Exception('boom');
    final router = _makeRouter();
    await tester.pumpWidget(_buildApp(fake, router));
    await tester.pumpAndSettle();

    router.push('/form');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Richiama il fornitore');
    await tester.tap(find.text('Crea task'));
    await tester.pumpAndSettle();

    expect(fake.createCalls, hasLength(1));
    expect(find.text('Impossibile salvare. Riprova.'), findsOneWidget);
    // Still on the form — did not pop back.
    expect(find.text('LISTA'), findsNothing);
  });

  testWidgets('offline blocks the save before any API call', (tester) async {
    final fake = _FakeAgendaApiClient();
    final router = _makeRouter();
    await tester.pumpWidget(_buildApp(fake, router, online: false));
    await tester.pumpAndSettle();

    router.push('/form');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Richiama il fornitore');
    await tester.tap(find.text('Crea task'));
    await tester.pumpAndSettle();

    expect(fake.createCalls, isEmpty);
    expect(find.textContaining('Sei offline'), findsOneWidget);
  });
}
