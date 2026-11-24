import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/accent_scheme.dart';
import 'package:tasktap_mobile/core/theme/tenant_accent_provider.dart';
import 'package:tasktap_mobile/data/branding/tenant_branding.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

AuthUser _user(String id) => AuthUser(
  id: id,
  email: '$id@test',
  accessToken: 't',
  refreshToken: 'r',
  expiresAt: DateTime.utc(2100),
);

ProviderContainer _container(Stream<TenantBranding?> branding) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [tenantBrandingProvider.overrideWith((ref) => branding)],
  );
  addTearDown(container.dispose);
  container.listen(tenantAccentProvider, (_, _) {});
  return container;
}

void main() {
  group('tenantAccentProvider', () {
    test('applies a tenant colour that passes the gate (trimmed)', () async {
      final container = _container(
        Stream.value(const TenantBranding(primaryColor: ' #1565C0 ')),
      );
      await container.read(tenantBrandingProvider.future);
      expect(container.read(tenantAccentProvider).fill, const Color(0xFF1565C0));
    });

    test('falls back to stamp red for a colour that fails the gate', () async {
      final container = _container(
        Stream.value(const TenantBranding(primaryColor: '#FFD700')),
      );
      await container.read(tenantBrandingProvider.future);
      expect(container.read(tenantAccentProvider), AccentScheme.stampRed);
    });

    test('is stamp red while branding is loading', () {
      final container = _container(const Stream<TenantBranding?>.empty());
      expect(container.read(tenantAccentProvider), AccentScheme.stampRed);
    });

    test('is stamp red when branding errored', () async {
      final container = _container(Stream<TenantBranding?>.error('boom'));
      await container.read(tenantBrandingProvider.future).then((_) {}, onError: (_) {});
      expect(container.read(tenantAccentProvider), AccentScheme.stampRed);
    });

    test('is stamp red for null branding', () async {
      final container = _container(Stream<TenantBranding?>.value(null));
      await container.read(tenantBrandingProvider.future);
      expect(container.read(tenantAccentProvider), AccentScheme.stampRed);
    });
  });

  group('tenantBrandingProvider auth keying', () {
    test('signed out yields null branding without any repository access', () async {
      // No dioProvider override: if the provider reached the repository it would build a Dio,
      // hit the network/prefs; the early return means it never does.
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<AuthUser?>.value(null)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authStateProvider, (_, _) {});
      container.listen(tenantAccentProvider, (_, _) {});
      await container.read(authStateProvider.future);
      expect(await container.read(tenantBrandingProvider.future), isNull);
      expect(container.read(tenantAccentProvider), AccentScheme.stampRed);
    });

    test('accent falls back to stamp red when the user signs out', () async {
      final auth = StreamController<AuthUser?>();
      addTearDown(auth.close);
      var repoReads = 0;
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authStateProvider.overrideWith((ref) => auth.stream),
          // Stand-in for the branding body: same auth keying, counts "repository" reads.
          tenantBrandingProvider.overrideWith((ref) async* {
            final uid = ref.watch(authStateProvider.select((a) => a.value?.id));
            if (uid == null) {
              yield null;
              return;
            }
            repoReads++;
            yield const TenantBranding(primaryColor: '#1565C0');
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authStateProvider, (_, _) {});
      container.listen(tenantAccentProvider, (_, _) {});

      auth.add(_user('a'));
      await pumpEventQueue();
      expect(container.read(tenantAccentProvider).fill, const Color(0xFF1565C0));
      expect(repoReads, 1);

      auth.add(null);
      await pumpEventQueue();
      expect(container.read(tenantAccentProvider), AccentScheme.stampRed);
      expect(repoReads, 1);
    });
  });
}
