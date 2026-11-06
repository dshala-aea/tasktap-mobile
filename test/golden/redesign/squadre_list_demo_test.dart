// test/golden/redesign/squadre_list_demo_test.dart
//
// Review artifact for the redesigned Squadre list. Feeds the prototype's three squadre and their
// members through the screen's existing online providers, then writes `build/redesign/squadre_list.png`.
// Nothing here compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/squadre_list_demo_test.dart

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/squadre/admin_squadra_list_screen.dart';

import 'redesign_harness.dart';

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient({required this.squadre, required this.users})
    : super(Dio());

  final List<Map<String, dynamic>> squadre;
  final List<Map<String, dynamic>> users;

  @override
  Future<List<Map<String, dynamic>>> fetchSquadre() async => squadre;

  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({
    bool activeOnly = true,
  }) async => users;
}

List<Map<String, dynamic>> _squadre() => [
  {
    'id': 'sq-nord',
    'nome': 'Squadra Nord',
    'specializzazione': 'Elettrico',
    'capSquadraNome': 'Daniel',
    'isActive': true,
  },
  {
    'id': 'sq-sud',
    'nome': 'Squadra Sud',
    'specializzazione': '',
    'capSquadraNome': 'Marco',
    'isActive': true,
  },
  {
    'id': 'sq-est',
    'nome': 'Squadra Est',
    'specializzazione': '',
    'capSquadraNome': 'Luca',
    'isActive': false,
  },
];

List<Map<String, dynamic>> _users() => [
  {'id': 'u1', 'squadraId': 'sq-nord', 'displayName': 'Daniel'},
  {'id': 'u2', 'squadraId': 'sq-nord', 'displayName': 'Giulia'},
  {'id': 'u3', 'squadraId': 'sq-nord', 'displayName': 'Anna'},
  {'id': 'u4', 'squadraId': 'sq-nord', 'displayName': 'Paolo'},
  {'id': 'u5', 'squadraId': 'sq-sud', 'displayName': 'Marco'},
  {'id': 'u6', 'squadraId': 'sq-sud', 'displayName': 'Sara'},
  {'id': 'u7', 'squadraId': 'sq-sud', 'displayName': 'Elena'},
  {'id': 'u8', 'squadraId': 'sq-est', 'displayName': 'Luca'},
  {'id': 'u9', 'squadraId': 'sq-est', 'displayName': 'Marta'},
];

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Squadre list — writes build/redesign/squadre_list.png', (
    tester,
  ) async {
    await captureRedesign(
      tester,
      'squadre_list',
      child: const AdminSquadraListScreen(),
      overrides: [
        adminApiClientProvider.overrideWithValue(
          _FakeAdminApiClient(squadre: _squadre(), users: _users()),
        ),
        isOnlineProvider.overrideWithValue(true),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {},
              capabilities: const {'team.squadra.write'},
              seatType: 'office',
              fetchedAt: DateTime.utc(2026, 9, 23),
            ),
          ),
        ),
      ],
    );
  });
}
