// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart' show internalUserIdPrefsKey;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/trasferta/trasferta_request_api_client.dart';
import 'package:tasktap_mobile/features/trasferta/trasferta_form_screen.dart';
import 'package:tasktap_mobile/features/trasferta/trasferta_list_screen.dart';

class _Fake extends TrasfertaRequestApiClient {
  _Fake() : super(Dio());

  final List<Map<String, dynamic>> creates = [];
  final List<String> cancels = [];
  List<TrasfertaRequestDto> items = [];
  Object? throwOnCreate;
  Object? throwOnFetch;

  @override
  Future<List<TrasfertaRequestDto>> fetchMine({String? userId}) async {
    if (throwOnFetch != null) throw throwOnFetch!;
    return List.of(items);
  }

  @override
  Future<void> create({
    required DateTime date,
    required int startHour,
    required int startMinute,
    required double hours,
    String? reason,
  }) async {
    creates.add({
      'date': date,
      'h': startHour,
      'm': startMinute,
      'hours': hours,
      'reason': reason,
    });
    if (throwOnCreate != null) throw throwOnCreate!;
  }

  @override
  Future<void> cancel(String id) async => cancels.add(id);
}

const _formPath = '/altro/trasferta/nuovo';

Widget _harness(
  _Fake fake, {
  bool online = true,
  TimeOfDay? start = const TimeOfDay(hour: 8, minute: 0),
  String? hours,
  Widget? home,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (c, s) =>
            home ??
            Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => c.push(_formPath),
                  child: const Text('Apri form'),
                ),
              ),
            ),
      ),
      GoRoute(
        path: _formPath,
        builder: (c, s) => TrasfertaFormScreen(
          initialDate: DateTime(2026, 11, 3),
          initialStartTime: start,
          initialHours: hours,
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      trasfertaRequestApiClientProvider.overrideWithValue(fake),
      isOnlineProvider.overrideWithValue(online),
      cachedEntitlementProvider.overrideWith((ref) => null),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _open(WidgetTester t, _Fake fake, {bool online = true, TimeOfDay? start = const TimeOfDay(hour: 8, minute: 0), String? hours}) async {
  await t.pumpWidget(_harness(fake, online: online, start: start, hours: hours));
  await t.pumpAndSettle();
  await t.tap(find.text('Apri form'));
  await t.pumpAndSettle();
}

Future<void> _submit(WidgetTester t) async {
  await t.dragUntilVisible(
    find.text('Registra trasferta'),
    find.byType(ListView),
    const Offset(0, -200),
  );
  await t.tap(find.text('Registra trasferta'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async => initializeDateFormatting('it', null));
  setUp(() => SharedPreferences.setMockInitialValues({internalUserIdPrefsKey: 'user-1'}));

  testWidgets('valid input files the trasferta with the typed values (decimal comma)', (t) async {
    final fake = _Fake();
    await _open(t, fake, hours: '1,5');
    await _submit(t);
    expect(fake.creates, hasLength(1));
    expect(fake.creates.single['date'], DateTime(2026, 11, 3));
    expect(fake.creates.single['h'], 8);
    expect(fake.creates.single['m'], 0);
    expect(fake.creates.single['hours'], 1.5);
    expect(fake.creates.single['reason'], isNull);
  });

  testWidgets('hours off the 0.25 step are refused before the round trip', (t) async {
    final fake = _Fake();
    await _open(t, fake, hours: '1,3');
    await _submit(t);
    expect(find.text(kTrasfertaHoursInvalid), findsOneWidget);
    expect(fake.creates, isEmpty);
  });

  testWidgets('more than 24 hours is refused', (t) async {
    final fake = _Fake();
    await _open(t, fake, hours: '25');
    await _submit(t);
    expect(find.text(kTrasfertaHoursInvalid), findsOneWidget);
    expect(fake.creates, isEmpty);
  });

  testWidgets('empty hours are refused', (t) async {
    final fake = _Fake();
    await _open(t, fake);
    await _submit(t);
    expect(find.text(kTrasfertaHoursInvalid), findsOneWidget);
    expect(fake.creates, isEmpty);
  });

  testWidgets('start + hours past midnight is refused', (t) async {
    final fake = _Fake();
    await _open(t, fake, start: const TimeOfDay(hour: 23, minute: 0), hours: '2');
    await _submit(t);
    expect(find.text(kTrasfertaCrossesMidnight), findsOneWidget);
    expect(fake.creates, isEmpty);
  });

  testWidgets('a missing start time is asked for', (t) async {
    final fake = _Fake();
    await _open(t, fake, start: null, hours: '1');
    await _submit(t);
    expect(find.text("Indica l'ora di inizio."), findsOneWidget);
    expect(fake.creates, isEmpty);
  });

  testWidgets('409 duplicate day shows the server sentence', (t) async {
    final fake = _Fake()
      ..throwOnCreate = const TrasfertaRuleError(
        'Esiste già una trasferta per questa persona in questa data.',
      );
    await _open(t, fake, hours: '1');
    await _submit(t);
    expect(
      find.text('Esiste già una trasferta per questa persona in questa data.'),
      findsOneWidget,
    );
    expect(find.text('Registra trasferta'), findsOneWidget, reason: 'the form stays open');
  });

  testWidgets('offline shows the needs-connection notice and never calls the api', (t) async {
    final fake = _Fake();
    await _open(t, fake, online: false, hours: '1');
    await _submit(t);
    expect(find.textContaining('Sei offline'), findsOneWidget);
    expect(fake.creates, isEmpty);
  });

  testWidgets('list: own trasferta renders and can be cancelled; office-filed has no cancel', (t) async {
    final fake = _Fake()
      ..items = [
        TrasfertaRequestDto(
          id: 'a',
          requestedByUserId: 'user-1',
          createdByUserId: 'user-1',
          date: DateTime.utc(2026, 11, 3),
          startTime: '07:30',
          hours: 1.5,
          reason: 'Cantiere',
          status: 1,
        ),
        TrasfertaRequestDto(
          id: 'b',
          requestedByUserId: 'user-1',
          createdByUserId: 'office',
          date: DateTime.utc(2026, 11, 2),
          startTime: '08:00',
          hours: 2,
          status: 1,
        ),
      ];
    await t.pumpWidget(_harness(fake, home: const TrasfertaListScreen()));
    await t.pumpAndSettle();
    expect(find.textContaining('dalle 07:30 · 1,5 h'), findsOneWidget);
    expect(find.textContaining('dalle 08:00 · 2 h'), findsOneWidget);
    expect(find.byTooltip('Annulla trasferta'), findsOneWidget);
  });

  testWidgets('list: an unreachable server says it needs a connection, not "empty"', (t) async {
    final fake = _Fake()..throwOnFetch = DioException(requestOptions: RequestOptions(path: '/x'));
    await t.pumpWidget(_harness(fake, home: const TrasfertaListScreen()));
    await t.pumpAndSettle();
    expect(find.text('Serve la connessione'), findsOneWidget);
    expect(find.text('Nessuna trasferta'), findsNothing);
  });
}
