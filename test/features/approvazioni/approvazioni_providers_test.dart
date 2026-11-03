import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/ferie/absence_request_api_client.dart';
import 'package:tasktap_mobile/data/smart_working/smart_working_request_api_client.dart';
import 'package:tasktap_mobile/features/approvazioni/approvazioni_providers.dart';

class _MockAbsenceClient extends Mock implements AbsenceRequestApiClient {}

class _MockSmartWorkingClient extends Mock implements SmartWorkingRequestApiClient {}

void main() {
  test('absence queue reads the tenant-wide pending endpoint', () async {
    final client = _MockAbsenceClient();
    when(() => client.fetchPendingForApproval()).thenAnswer((_) async => const []);

    final container = ProviderContainer(
      overrides: [absenceRequestApiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    expect(await container.read(absenceApprovalQueueProvider.future), isEmpty);
    verify(() => client.fetchPendingForApproval()).called(1);
  });

  test('smart-working queue reads the tenant-wide pending endpoint', () async {
    final client = _MockSmartWorkingClient();
    when(() => client.fetchPendingForApproval()).thenAnswer((_) async => const []);

    final container = ProviderContainer(
      overrides: [smartWorkingRequestApiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    expect(await container.read(smartWorkingApprovalQueueProvider.future), isEmpty);
    verify(() => client.fetchPendingForApproval()).called(1);
  });
}
