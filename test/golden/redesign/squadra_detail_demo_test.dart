// test/golden/redesign/squadra_detail_demo_test.dart
//
// Review artifact for the redesigned Squadra detail. Writes
// `build/redesign/squadra_detail.png`; nothing here compares images.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/squadre/admin_squadra_detail_screen.dart';

import 'redesign_harness.dart';

class _DemoAdminApiClient extends AdminApiClient {
  _DemoAdminApiClient() : super(Dio());

  @override
  Future<Map<String, dynamic>?> fetchSquadraDetail(String id) async => {
    'squadra': {
      'id': 'sq-nord',
      'nome': 'Squadra Nord',
      'descrizione':
          'Interventi elettrici e manutenzione impianti nella zona nord.',
      'specializzazione': 'Elettrico',
      'note': 'Pronta disponibilità nei festivi.',
      'capSquadraNome': 'Daniel Shala',
      'isActive': true,
    },
    'membri': [
      {'userId': 'u2', 'ruolo': 0},
      {'userId': 'u1', 'ruolo': 1},
      {'userId': 'u3', 'ruolo': 0},
      {'userId': 'u4', 'ruolo': 0},
    ],
  };

  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({
    bool activeOnly = true,
  }) async => [
    {
      'id': 'u1',
      'displayName': 'Daniel Shala',
      'squadraId': 'sq-nord',
      'lastAccessAt': '2026-11-06T08:12:00Z',
    },
    {
      'id': 'u2',
      'displayName': 'Giulia Verdi',
      'squadraId': 'sq-nord',
      'lastAccessAt': '2026-11-05T17:40:00Z',
    },
    {
      'id': 'u3',
      'displayName': 'Anna Neri',
      'squadraId': 'sq-nord',
      'lastAccessAt': null,
    },
    {
      'id': 'u4',
      'displayName': 'Paolo Galli',
      'squadraId': 'sq-nord',
      'lastAccessAt': '2026-11-03T09:05:00Z',
    },
  ];
}

void main() {
  setUpAll(() async {
    await loadRedesignFonts();
    await initializeDateFormatting('it');
  });

  testWidgets('Squadra detail — writes build/redesign/squadra_detail.png', (
    tester,
  ) async {
    await captureRedesign(
      tester,
      'squadra_detail',
      child: const AdminSquadraDetailScreen(
        squadra: {'id': 'sq-nord', 'nome': 'Squadra Nord'},
      ),
      overrides: [
        adminApiClientProvider.overrideWithValue(_DemoAdminApiClient()),
        isOnlineProvider.overrideWithValue(true),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {},
              capabilities: const {'team.squadra.write'},
              seatType: 'office',
              fetchedAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        ),
      ],
    );
  });

  testWidgets(
    'Squadra detail full scroll — writes build/redesign/squadra_detail_full.png',
    (tester) async {
      await captureRedesign(
        tester,
        'squadra_detail_full',
        size: const Size(390, 1200),
        child: const AdminSquadraDetailScreen(
          squadra: {'id': 'sq-nord', 'nome': 'Squadra Nord'},
        ),
        overrides: [
          adminApiClientProvider.overrideWithValue(_DemoAdminApiClient()),
          isOnlineProvider.overrideWithValue(true),
          cachedEntitlementProvider.overrideWith(
            (ref) => Future.value(
              Entitlement(
                features: const {},
                capabilities: const {'team.squadra.write'},
                seatType: 'office',
                fetchedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
        ],
      );
    },
  );
}
