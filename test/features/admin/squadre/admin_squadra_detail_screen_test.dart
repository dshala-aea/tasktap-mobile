// dart format width=100
// test/features/admin/squadre/admin_squadra_detail_screen_test.dart
//
// Two things regression-tested here:
//   1. GET /api/squadre/{id} wraps the squadra's own fields under a "squadra" key
//      (backend record SquadraDetailResponse(Squadra, Membri)) — reading fields off the
//      un-unwrapped envelope left nome/descrizione/specializzazione blank on every real fetch.
//   2. The backend derives capSquadraNome on every /api/squadre/{id} response
//      (PopulateCapiSquadraAsync) but mobile never displayed it — item 8b of the audit.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/squadre/admin_squadra_detail_screen.dart';

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient(this._detail) : super(Dio());

  final Map<String, dynamic>? _detail;

  @override
  Future<Map<String, dynamic>?> fetchSquadraDetail(String id) async => _detail;
}

Widget _buildView({required Map<String, dynamic>? detail, required Map<String, dynamic> squadra}) {
  return ProviderScope(
    overrides: [adminApiClientProvider.overrideWithValue(_FakeAdminApiClient(detail))],
    child: MaterialApp(home: AdminSquadraDetailScreen(squadra: squadra)),
  );
}

void main() {
  testWidgets('unwraps the "squadra" envelope and shows capo squadra name', (tester) async {
    await tester.pumpWidget(
      _buildView(
        detail: {
          'squadra': {
            'id': 'sq-1',
            'nome': 'Squadra Nord',
            'descrizione': 'Zona nord',
            'specializzazione': 'Elettrico',
            'capSquadraNome': 'Mario Rossi',
          },
          'membri': <Map<String, dynamic>>[],
        },
        squadra: {'id': 'sq-1', 'nome': 'Squadra Nord'},
      ),
    );
    await tester.pumpAndSettle();

    // Nome/descrizione/specializzazione all come from the unwrapped envelope.
    expect(find.text('Zona nord'), findsOneWidget);
    expect(find.text('Elettrico'), findsWidgets);
    // The new capo-squadra row.
    expect(find.text('CAPO SQUADRA'), findsOneWidget);
    expect(find.text('Mario Rossi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('falls back to em-dash when no capo squadra is assigned', (tester) async {
    await tester.pumpWidget(
      _buildView(
        detail: {
          'squadra': {'id': 'sq-2', 'nome': 'Squadra Sud', 'specializzazione': 'Idraulico'},
          'membri': <Map<String, dynamic>>[],
        },
        squadra: {'id': 'sq-2', 'nome': 'Squadra Sud'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CAPO SQUADRA'), findsOneWidget);
    expect(find.text('—'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
