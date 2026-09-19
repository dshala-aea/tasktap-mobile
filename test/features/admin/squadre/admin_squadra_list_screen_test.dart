// dart format width=100
// test/features/admin/squadre/admin_squadra_list_screen_test.dart
//
// Gap 7 of the feature audit: the squadra list row showed no member count (the backend has no
// `membriCount` field on `/api/squadre`, so it has to be derived client-side). This pins that the
// count is derived from ONE bulk `allUsersWithSquadraProvider` fetch — grouping users by their
// derived `squadraId` — rather than one `/api/squadre/{id}/membri` call per row, which would be an
// N+1 over the squadra list just to answer "how many".

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({
    bool activeOnly = true,
  }) async {
    usersCallCount++;
    return users;
  }
}

Widget _buildView(_FakeAdminApiClient api) {
  return ProviderScope(
    overrides: [adminApiClientProvider.overrideWithValue(api)],
    child: const MaterialApp(home: AdminSquadraListScreen()),
  );
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

    await tester.pumpWidget(_buildView(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 membri'), findsOneWidget); // Squadra Nord
    expect(find.textContaining('1 membro'), findsOneWidget); // Squadra Sud
    expect(find.textContaining('0 membri'), findsOneWidget); // Squadra Est, no members at all

    // One request for the whole list, not one per squadra row.
    expect(api.usersCallCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
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
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
