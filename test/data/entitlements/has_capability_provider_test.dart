// Tests for hasCapabilityProvider (lib/data/entitlements/entitlement_providers.dart) — the
// provider CapabilityGate reads. Mirrors hasFeatureProvider's own shape (a FutureProvider.family
// delegating to the repository) but the underlying rule is EntitlementRepository.hasCapability's
// fail-closed one, not hasFeature's fail-open baseline — see that method's doc comment.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('true once the cached entitlement holds the capability', () async {
    await container
        .read(entitlementRepositoryProvider)
        .write(
          features: const [],
          capabilities: const ['clienti.customer.write'],
          seatType: 'office',
          fetchedAt: DateTime.utc(2026, 9, 23),
        );

    final result = await container.read(hasCapabilityProvider('clienti.customer.write').future);

    expect(result, isTrue);
  });

  test('false when the cached entitlement lacks the capability', () async {
    await container
        .read(entitlementRepositoryProvider)
        .write(
          features: const [],
          capabilities: const ['clienti.customer.read'],
          seatType: 'office',
          fetchedAt: DateTime.utc(2026, 9, 23),
        );

    final result = await container.read(hasCapabilityProvider('clienti.customer.write').future);

    expect(result, isFalse);
  });

  test('false, not an exception, when nothing has ever been cached', () async {
    final result = await container.read(hasCapabilityProvider('clienti.customer.write').future);

    expect(result, isFalse);
  });
}
