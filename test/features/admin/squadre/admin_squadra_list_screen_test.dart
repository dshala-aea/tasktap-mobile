// dart format width=100
// test/features/admin/squadre/admin_squadra_list_screen_test.dart
//
// The redesigned Squadre list: prototype groups/chips/rows/summary, one bulk users fetch for the
// member counts and member-name search, the real Filtri sheet, and the `team.squadra.write` gate
// on `Nuovo` (moved from the FAB into the header).

import 'dart:ui' show SemanticsAction;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/squadre/admin_squadra_list_screen.dart';

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient({required this.squadre, required this.users}) : super(Dio());

  final List<Map<String, dynamic>> squadre;
  final List<Map<String, dynamic>> users;
  int usersCallCount = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchSquadre() async => squadre;

  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({bool activeOnly = true}) async {
    usersCallCount++;
    return users;
  }
}

/// Squadre are not in the sync payload, so a network failure is the only way this screen ever
/// errors. What it says then is a product decision, not a detail: "impossibile caricare" reads as
/// "your squadre may be gone", which the screen has no grounds for.
class _FailingAdminApiClient extends AdminApiClient {
  _FailingAdminApiClient() : super(Dio());

  int usersCallCount = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchSquadre() async =>
      throw DioException(requestOptions: RequestOptions(path: '/api/squadre'));

  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({bool activeOnly = true}) async {
    usersCallCount++;
    return const [];
  }
}

Widget _buildView(AdminApiClient api, {bool? online, Set<String> capabilities = const {}}) {
  return ProviderScope(retry: (_, _) => null, 
    overrides: [
      adminApiClientProvider.overrideWithValue(api),
      if (online != null) isOnlineProvider.overrideWithValue(online),
      cachedEntitlementProvider.overrideWith(
        (ref) => Future.value(
          Entitlement(
            features: const {},
            capabilities: capabilities,
            seatType: 'office',
            fetchedAt: DateTime.utc(2026, 9, 23),
          ),
        ),
      ),
    ],
    child: const MaterialApp(home: AdminSquadraListScreen()),
  );
}

List<Map<String, dynamic>> _prototypeSquadre() => [
  {
    'id': 'sq-nord',
    'nome': 'Squadra Nord',
    'specializzazione': 'Elettrico',
    'capSquadraNome': 'Daniel Shala',
    'isActive': true,
  },
  {
    'id': 'sq-sud',
    'nome': 'Squadra Sud',
    'specializzazione': 'Idraulico',
    'capSquadraNome': 'Marco Rossi',
    'isActive': true,
  },
  {
    'id': 'sq-est',
    'nome': 'Squadra Est',
    'specializzazione': '',
    'capSquadraNome': 'Luca Bianchi',
    'isActive': false,
  },
];

List<Map<String, dynamic>> _prototypeUsers() => [
  {'id': 'u1', 'squadraId': 'sq-nord', 'displayName': 'Daniel Shala'},
  {'id': 'u2', 'squadraId': 'sq-nord', 'displayName': 'Giulia Verdi'},
  {'id': 'u3', 'squadraId': 'sq-nord', 'displayName': 'Anna Neri'},
  {'id': 'u4', 'squadraId': 'sq-nord', 'displayName': 'Paolo Galli'},
  {'id': 'u5', 'squadraId': 'sq-sud', 'displayName': 'Marco Rossi'},
  {'id': 'u6', 'squadraId': 'sq-sud', 'displayName': 'Sara Conti'},
  {'id': 'u7', 'squadraId': 'sq-sud', 'displayName': 'Elena Ferri'},
  {'id': 'u8', 'squadraId': 'sq-est', 'displayName': 'Luca Bianchi'},
  {'id': 'u9', 'squadraId': 'sq-est', 'displayName': 'Marta Riva'},
  {'id': 'u10', 'squadraId': null, 'displayName': 'Senza squadra'},
];

_FakeAdminApiClient _fakeApi() =>
    _FakeAdminApiClient(squadre: _prototypeSquadre(), users: _prototypeUsers());

Future<void> _pump(
  WidgetTester tester,
  AdminApiClient api, {
  bool? online,
  Set<String> capabilities = const {},
}) async {
  await tester.pumpWidget(_buildView(api, online: online, capabilities: capabilities));
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.text('FILTRI'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a derived member count per row from a single bulk users fetch', (
    tester,
  ) async {
    final api = _FakeAdminApiClient(
      squadre: [
        {'id': 'sq-1', 'nome': 'Squadra Nord', 'specializzazione': 'Elettrico'},
        {'id': 'sq-2', 'nome': 'Squadra Sud', 'specializzazione': 'Idraulico'},
        {'id': 'sq-3', 'nome': 'Squadra Est', 'specializzazione': ''},
      ],
      users: [
        {'id': 'u1', 'squadraId': 'sq-1'},
        {'id': 'u2', 'squadraId': 'sq-1'},
        {'id': 'u3', 'squadraId': 'sq-2'},
        {'id': 'u4', 'squadraId': null},
      ],
    );

    await _pump(tester, api);

    expect(find.textContaining('2 membri'), findsOneWidget); // Squadra Nord
    expect(find.textContaining('1 membro'), findsOneWidget); // Squadra Sud
    expect(find.textContaining('0 membri'), findsOneWidget); // Squadra Est, no members at all

    // One request for the whole list, not one per squadra row.
    expect(api.usersCallCount, 1);

    await _dispose(tester);
  });

  testWidgets('member count survives while the bulk fetch is still loading', (tester) async {
    final api = _FakeAdminApiClient(
      squadre: [
        {'id': 'sq-1', 'nome': 'Squadra Nord', 'specializzazione': 'Elettrico'},
      ],
      users: const [],
    );

    await tester.pumpWidget(_buildView(api));
    // Deliberately not settled — the row must still render something sane before the users
    // fetch resolves rather than throwing on a null/incomplete provider value.
    await tester.pump();

    expect(find.text('Squadra Nord'), findsOneWidget);

    await tester.pumpAndSettle();
    await _dispose(tester);
  });

  testWidgets('groups Attive and Inattive with the prototype row anatomy', (tester) async {
    await _pump(tester, _fakeApi());

    expect(find.text('Attive'), findsOneWidget);
    expect(find.text('Inattive'), findsOneWidget);

    expect(find.text('Squadra Nord'), findsOneWidget);
    expect(find.text('Lead Daniel Shala · 4 membri'), findsOneWidget);
    expect(find.text('Squadra Sud'), findsOneWidget);
    expect(find.text('Lead Marco Rossi · 3 membri'), findsOneWidget);
    expect(find.text('Squadra Est'), findsOneWidget);
    expect(find.text('Lead Luca Bianchi · 2 membri'), findsOneWidget);

    expect(find.text('ATTIVA'), findsNWidgets(2));
    expect(find.text('INATTIVA'), findsOneWidget);

    // The prototype's active-cantiere line has no data source; the squadra's own specializzazione
    // takes the third line instead of inventing a count.
    expect(find.text('Elettrico'), findsOneWidget);
    expect(find.text('Idraulico'), findsOneWidget);

    expect(find.text('3 SQUADRE'), findsOneWidget);
    expect(find.text('2 ATTIVE'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('an empty status group is omitted', (tester) async {
    final api = _FakeAdminApiClient(
      squadre: [
        {'id': 'sq-1', 'nome': 'Squadra Nord', 'isActive': true},
      ],
      users: const [],
    );

    await _pump(tester, api);

    expect(find.text('Attive'), findsOneWidget);
    expect(find.text('Inattive'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('quick chips filter Attive, Tutte and Inattive', (tester) async {
    await _pump(tester, _fakeApi());

    await tester.tap(find.text('INATTIVE'));
    await tester.pumpAndSettle();
    expect(find.text('Squadra Est'), findsOneWidget);
    expect(find.text('Squadra Nord'), findsNothing);
    expect(find.text('Squadra Sud'), findsNothing);
    expect(find.text('Attive'), findsNothing);

    await tester.tap(find.text('ATTIVE'));
    await tester.pumpAndSettle();
    expect(find.text('Squadra Nord'), findsOneWidget);
    expect(find.text('Squadra Sud'), findsOneWidget);
    expect(find.text('Squadra Est'), findsNothing);
    expect(find.text('Inattive'), findsNothing);

    await tester.tap(find.text('TUTTE'));
    await tester.pumpAndSettle();
    expect(find.text('Squadra Nord'), findsOneWidget);
    expect(find.text('Squadra Sud'), findsOneWidget);
    expect(find.text('Squadra Est'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('search covers squadra name, lead and member name', (tester) async {
    await _pump(tester, _fakeApi());

    await tester.enterText(find.byType(TextField), 'giulia');
    await tester.pumpAndSettle();
    expect(find.text('Squadra Nord'), findsOneWidget);
    expect(find.text('Squadra Sud'), findsNothing);

    await tester.enterText(find.byType(TextField), 'marco');
    await tester.pumpAndSettle();
    expect(find.text('Squadra Sud'), findsOneWidget);
    expect(find.text('Squadra Nord'), findsNothing);

    await tester.enterText(find.byType(TextField), 'est');
    await tester.pumpAndSettle();
    expect(find.text('Squadra Est'), findsOneWidget);
    expect(find.text('Squadra Nord'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('a search with no match says no result', (tester) async {
    await _pump(tester, _fakeApi());

    await tester.enterText(find.byType(TextField), 'inesistente');
    await tester.pumpAndSettle();

    expect(find.text('Nessun risultato'), findsOneWidget);
    expect(find.textContaining('Nessuna squadra corrisponde'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('the Filtri sheet filters by status and lead and Azzera clears both', (tester) async {
    await _pump(tester, _fakeApi());

    await _openFilters(tester);
    expect(find.text('Restringi per stato e lead.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('squadreFilterStatus-inattive')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applica filtri'));
    await tester.pumpAndSettle();

    expect(find.text('Squadra Est'), findsOneWidget);
    expect(find.text('Squadra Nord'), findsNothing);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('squadreFilterLead')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daniel Shala').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applica filtri'));
    await tester.pumpAndSettle();

    // The sheet keeps both facets, so Inattive + Lead Daniel is genuinely empty.
    expect(find.text('Nessun risultato'), findsOneWidget);

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('squadreFilterReset')));
    await tester.pumpAndSettle();

    expect(find.text('Squadra Nord'), findsOneWidget);
    expect(find.text('Squadra Sud'), findsOneWidget);
    expect(find.text('Squadra Est'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('the Filtri sheet can show only one lead', (tester) async {
    await _pump(tester, _fakeApi());

    await _openFilters(tester);
    await tester.tap(find.byKey(const Key('squadreFilterLead')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daniel Shala').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applica filtri'));
    await tester.pumpAndSettle();

    expect(find.text('Squadra Nord'), findsOneWidget);
    expect(find.text('Squadra Sud'), findsNothing);
    expect(find.text('Squadra Est'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('sheet status chips are 44px targets with a semantic tap action', (tester) async {
    await _pump(tester, _fakeApi());
    await _openFilters(tester);

    final chipFinder = find.byKey(const ValueKey('squadreFilterStatus-inattive'));
    final size = tester.getSize(chipFinder);
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));

    final semantics = tester.getSemantics(chipFinder).getSemanticsData();
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);
    expect(semantics.flagsCollection.isButton, isTrue);

    await _dispose(tester);
  });

  testWidgets('the bulk users fetch is not made while the squadre list cannot load', (
    tester,
  ) async {
    final api = _FailingAdminApiClient();
    await _pump(tester, api, online: true);

    expect(api.usersCallCount, 0);

    await _dispose(tester);
  });

  testWidgets('Nuovo is hidden without team.squadra.write and shown with it', (tester) async {
    await _pump(tester, _fakeApi());
    expect(find.text('NUOVO'), findsNothing);

    await _dispose(tester);

    await _pump(tester, _fakeApi(), capabilities: const {'team.squadra.write'});
    expect(find.text('NUOVO'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('offline, a failed load names the offline case instead of a retry error', (
    tester,
  ) async {
    await _pump(tester, _FailingAdminApiClient(), online: false);

    expect(find.text('Squadre non disponibili offline'), findsOneWidget);
    expect(find.textContaining('Impossibile caricare'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('online, a failed load keeps the ordinary retryable error', (tester) async {
    await _pump(tester, _FailingAdminApiClient(), online: true);

    expect(find.text('Squadre non disponibili offline'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('narrow 320px layout does not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pump(tester, _fakeApi());

    expect(tester.takeException(), isNull);
    expect(find.text('Squadra Nord'), findsOneWidget);

    await _dispose(tester);
  });
}
