// test/golden/redesign/magazzino_detail_demo_test.dart
//
// Review artifact for the wave-1 Magazzino detail redesign. Writes
// `build/redesign/magazzino_detail.png`; nothing here compares images.
//
// The capture is the screen at open: hero + Modifica, the two on-demand online sections and the
// address map card. Stock/movimenti rows intentionally need a tap, so they are covered by the
// widget test rather than this review image.
//
// Run:
//   fvm flutter test test/golden/redesign/magazzino_detail_demo_test.dart

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/magazzino/magazzino_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/admin/magazzini/admin_magazzino_detail_screen.dart';
import 'package:tasktap_mobile/features/ticket/steps/step_assegnazione.dart'
    show techniciansProvider;

import 'redesign_harness.dart';

class _NoopMagazzinoApiClient extends MagazzinoApiClient {
  _NoopMagazzinoApiClient() : super(Dio());
}

const _sede = MagazzinoDto(
  id: 'm1',
  nome: 'Magazzino Milano',
  tipo: 'Sede',
  indirizzo: 'Via Roma 1',
  note: 'Accesso dal cortile interno.',
  isActive: true,
);

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('Magazzino detail — writes build/redesign/magazzino_detail.png', (
    tester,
  ) async {
    await captureRedesign(
      tester,
      'magazzino_detail',
      child: const AdminMagazzinoDetailScreen(magazzino: _sede),
      overrides: [
        magazzinoApiClientProvider.overrideWithValue(_NoopMagazzinoApiClient()),
        isOnlineProvider.overrideWithValue(true),
        cachedEntitlementProvider.overrideWith(
          (ref) => Future.value(
            Entitlement(
              features: const {},
              capabilities: const {'magazzino.warehouse.write'},
              seatType: 'office',
              fetchedAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        ),
        techniciansProvider.overrideWith((ref) async => const []),
      ],
    );
  });
}
