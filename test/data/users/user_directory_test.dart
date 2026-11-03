import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/users/user_directory.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';

class _FakeAdminApi extends AdminApiClient {
  _FakeAdminApi(this.rows, {this.error}) : super(Dio());

  final List<Map<String, dynamic>> rows;
  final Object? error;

  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({
    bool activeOnly = true,
  }) async {
    if (error != null) throw error!;
    return rows;
  }
}

void main() {
  test('userDisplayName_prefers_displayName_then_fullName_then_parts', () {
    expect(userDisplayName({'displayName': 'Mario Rossi'}), 'Mario Rossi');
    expect(userDisplayName({'fullName': 'Mario Rossi'}), 'Mario Rossi');
    expect(userDisplayName({'firstName': 'Mario', 'lastName': 'Rossi'}), 'Mario Rossi');
    expect(userDisplayName({'firstName': '', 'lastName': ''}), 'Utente senza nome');
  });

  test('userNameByIdProvider_maps_ids_and_falls_back_to_empty_on_error', () async {
    final rows = [
      {'id': 'u1', 'fullName': 'Mario Rossi'},
      {'id': 'u2', 'firstName': 'Anna', 'lastName': 'Bianchi'},
      {'fullName': 'No id'},
    ];

    final ok = ProviderContainer(
      overrides: [adminApiClientProvider.overrideWithValue(_FakeAdminApi(rows))],
    );
    addTearDown(ok.dispose);
    expect(await ok.read(userNameByIdProvider.future), {
      'u1': 'Mario Rossi',
      'u2': 'Anna Bianchi',
    });

    final failed = ProviderContainer(
      overrides: [
        adminApiClientProvider.overrideWithValue(
          _FakeAdminApi(const [], error: Exception('403')),
        ),
      ],
    );
    addTearDown(failed.dispose);
    expect(await failed.read(userNameByIdProvider.future), isEmpty);
  });
}
