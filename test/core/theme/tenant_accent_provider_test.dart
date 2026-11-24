import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/accent_scheme.dart';
import 'package:tasktap_mobile/core/theme/tenant_accent_provider.dart';
import 'package:tasktap_mobile/data/branding/tenant_branding.dart';

AccentScheme _accentFor(AsyncValue<TenantBranding?> branding) {
  final container = ProviderContainer(
    overrides: [
      tenantBrandingProvider.overrideWith((ref) {
        return switch (branding) {
          AsyncData(:final value) => Stream<TenantBranding?>.value(value),
          AsyncError(:final error) => Stream<TenantBranding?>.error(error),
          _ => const Stream<TenantBranding?>.empty(),
        };
      }),
    ],
  );
  addTearDown(container.dispose);
  return container.read(tenantAccentProvider);
}

void main() {
  group('tenantAccentProvider', () {
    test('applies a tenant colour that passes the gate', () async {
      final container = ProviderContainer(
        overrides: [
          tenantBrandingProvider.overrideWith(
            (ref) => Stream.value(const TenantBranding(primaryColor: ' #C03221 ')),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(tenantAccentProvider, (_, _) {});
      await container.read(tenantBrandingProvider.future);
      final expected = AccentScheme.fromHex('#C03221')!;
      expect(container.read(tenantAccentProvider).fill, expected.fill);
    });

    test('falls back to stamp red for a colour that fails the gate', () async {
      final container = ProviderContainer(
        overrides: [
          tenantBrandingProvider.overrideWith(
            (ref) => Stream.value(const TenantBranding(primaryColor: '#FFD700')),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(tenantAccentProvider, (_, _) {});
      await container.read(tenantBrandingProvider.future);
      expect(container.read(tenantAccentProvider), AccentScheme.stampRed);
    });

    test('is stamp red while branding is loading', () {
      expect(_accentFor(const AsyncValue.loading()), AccentScheme.stampRed);
    });

    test('is stamp red when branding errored', () async {
      final container = ProviderContainer(
        overrides: [
          tenantBrandingProvider.overrideWith((ref) => Stream<TenantBranding?>.error('boom')),
        ],
      );
      addTearDown(container.dispose);
      container.listen(tenantAccentProvider, (_, _) {});
      await container.read(tenantBrandingProvider.future).then((_) {}, onError: (_) {});
      expect(container.read(tenantAccentProvider), AccentScheme.stampRed);
    });

    test('is stamp red for null branding', () async {
      final container = ProviderContainer(
        overrides: [
          tenantBrandingProvider.overrideWith((ref) => Stream<TenantBranding?>.value(null)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(tenantAccentProvider, (_, _) {});
      await container.read(tenantBrandingProvider.future);
      expect(container.read(tenantAccentProvider), AccentScheme.stampRed);
    });
  });
}
