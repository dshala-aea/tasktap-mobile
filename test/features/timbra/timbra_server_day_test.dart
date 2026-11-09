import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class _CapturingClient extends WorklogApiClient {
  _CapturingClient() : super(Dio());

  int calls = 0;
  String? capturedUserId;

  @override
  Future<List<DayWorkLogEntry>> fetchDayEntries({
    required String userId,
    required DateTime day,
    BusinessTime? businessTime,
  }) async {
    calls++;
    capturedUserId = userId;
    return const [];
  }
}

void main() {
  test('serverDayProvider uses the internal user Guid, not the OIDC sub', () async {
    final client = _CapturingClient();
    final user = AuthUser(
      id: 'oidc-sub-123',
      email: 'tech@example.test',
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final container = ProviderContainer(
      overrides: [
        worklogApiClientProvider.overrideWithValue(client),
        currentUserProvider.overrideWithValue(user),
        internalUserIdProvider.overrideWith((ref) async => 'internal-guid-456'),
        businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
      ],
    );
    addTearDown(container.dispose);

    // The id is a FutureProvider; warm it so serverDayProvider sees the resolved value.
    await container.read(internalUserIdProvider.future);
    await container.read(serverDayProvider.future);

    expect(client.calls, 1);
    expect(client.capturedUserId, 'internal-guid-456');
  });
}
