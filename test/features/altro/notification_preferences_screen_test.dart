// NOT RUN when written: the authoring machine has no Flutter toolchain. CI is the first run.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/settings/notification_preferences_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/altro/notification_preferences_screen.dart';

NotificationPreferenceDto _pref(int type, String key, {bool enabled = true}) =>
    NotificationPreferenceDto(type: type, key: key, enabled: enabled, defaultEnabled: true);

class _FakeApi implements NotificationPreferencesApiClient {
  _FakeApi(this.items);

  List<NotificationPreferenceDto> items;
  NotificationPreferencesFailure? failWith;
  int fetches = 0;
  final updates = <Map<int, bool>>[];

  @override
  Future<List<NotificationPreferenceDto>> fetch() async {
    fetches++;
    return items;
  }

  @override
  Future<List<NotificationPreferenceDto>> update(Map<int, bool> changes) async {
    updates.add(changes);
    if (failWith != null) throw failWith!;
    items = [
      for (final i in items)
        changes.containsKey(i.type) ? i.copyWith(enabled: changes[i.type]) : i,
    ];
    return items;
  }
}

Widget _host(_FakeApi api, {bool online = true}) => ProviderScope(
  overrides: [
    notificationPreferencesApiClientProvider.overrideWithValue(api),
    isOnlineProvider.overrideWithValue(online),
  ],
  child: const MaterialApp(home: NotificationPreferencesScreen()),
);

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  late _FakeApi api;

  setUp(() {
    api = _FakeApi([
      _pref(0, 'TicketAssigned'),
      _pref(5, 'ScheduleReminder'),
      _pref(25, 'ReportSubmitted'),
      _pref(13, 'LowStock', enabled: false),
      _pref(99, 'BrandNewType'),
    ]);
  });

  testWidgets('renders one row per listed type, grouped, with an unknown ordinal by its key', (tester) async {
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    expect(find.text('INTERVENTI'), findsOneWidget);
    expect(find.text('PIANIFICAZIONE'), findsOneWidget);
    expect(find.text('RAPPORTI DI LAVORO E ORE'), findsOneWidget);
    expect(find.text('MAGAZZINO'), findsOneWidget);
    expect(find.text('Intervento assegnato'), findsOneWidget);
    expect(find.text('Rapporto di lavoro inviato'), findsOneWidget);
    // Unknown ordinal: rendered under "Altro" with the server's key, not dropped, not a crash.
    expect(find.text('ALTRO'), findsOneWidget);
    expect(find.text('BrandNewType'), findsOneWidget);
    expect(find.byType(AppToggle), findsNWidgets(5));
    await _drain(tester);
  });

  testWidgets('tapping a row flips it and PUTs only that ordinal', (tester) async {
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rapporto di lavoro inviato'));
    await tester.pumpAndSettle();

    expect(api.updates, [
      {25: false},
    ]);
    final toggles = tester.widgetList<AppToggle>(find.byType(AppToggle)).toList();
    // Order: Interventi (0), Pianificazione (5), Rapportini (25), Magazzino (13), Altro (99).
    expect(toggles.map((t) => t.value), [true, true, false, false, true]);
    await _drain(tester);
  });

  testWidgets('a failed write puts the switch back and toasts the reason', (tester) async {
    api.failWith = const NotificationPreferencesFailure('Impossibile salvare la preferenza.');
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Intervento assegnato'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.updates, [
      {0: false},
    ]);
    final first = tester.widgetList<AppToggle>(find.byType(AppToggle)).first;
    expect(first.value, isTrue, reason: 'rolled back to what the server holds');
    expect(find.text('Impossibile salvare la preferenza.'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('offline shows the unavailable state and never fetches', (tester) async {
    await tester.pumpWidget(_host(api, online: false));
    await tester.pumpAndSettle();

    expect(find.text('Preferenze non disponibili offline'), findsOneWidget);
    expect(find.byType(AppToggle), findsNothing);
    expect(api.fetches, 0);
    await _drain(tester);
  });

  testWidgets('a failed first load shows an error state with a working Riprova', (tester) async {
    final failing = _FailingFetchApi();
    await tester.pumpWidget(_host(failing));
    await tester.pumpAndSettle();

    expect(find.text('Impossibile caricare le preferenze'), findsOneWidget);
    failing.ok = true;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(find.text('Intervento assegnato'), findsOneWidget);
    await _drain(tester);
  });
}

class _FailingFetchApi extends _FakeApi {
  _FailingFetchApi() : super([_pref(0, 'TicketAssigned')]);
  bool ok = false;

  @override
  Future<List<NotificationPreferenceDto>> fetch() async {
    if (!ok) throw const NotificationPreferencesFailure('Errore di prova.');
    return items;
  }
}
