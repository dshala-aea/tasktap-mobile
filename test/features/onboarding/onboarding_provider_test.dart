import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/features/onboarding/onboarding_provider.dart';

void main() {
  test('defaults to not completed for a user who has never finished onboarding', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final result = await container.read(onboardingCompletedProvider('user-1').future);

    expect(result, isFalse);
  });

  test('markCompleted persists per user id', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(onboardingCompletedProvider('user-1').future);
    await container.read(onboardingCompletedProvider('user-1').notifier).markCompleted();

    expect(await container.read(onboardingCompletedProvider('user-1').future), isTrue);
    // A different user on the same device has not completed it.
    expect(await container.read(onboardingCompletedProvider('user-2').future), isFalse);
  });

  test('reflects a flag already set by a previous app run', () async {
    SharedPreferences.setMockInitialValues({'onboarding.completed.user-3': true});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(onboardingCompletedProvider('user-3').future), isTrue);
  });
}
