// Tests for RouteRequirement.isSatisfied (lib/core/router/route_requirement.dart) — the guard
// `buildRouter`'s `redirect` callback reads for routes listed in `_routeRequirements`.
//
// isSatisfied takes a real WidgetRef (not a bare Ref), so each case pumps a bare [Consumer]
// inside a ProviderScope the same way test/core/dictation/dictation_capability_test.dart already
// does, rather than inventing a new harness. cachedEntitlementProvider is overridden directly —
// the exact provider RouteRequirement reads — with a controllable Future so both the resolved
// (data) and never-resolved (loading, e.g. cold start before the cache has ever been read) cases
// can be exercised deterministically.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/router/route_requirement.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';

Entitlement _entitlementWith({Set<String> features = const {}, Set<String> capabilities = const {}}) {
  return Entitlement(
    features: features,
    capabilities: capabilities,
    seatType: 'office',
    fetchedAt: DateTime.utc(2026, 9, 17),
  );
}

/// Pumps a bare [Consumer] with [cachedEntitlementProvider] overridden to [future] (or, when
/// [neverResolves] is true, a [Completer] whose future is never completed — cold start, cache not
/// yet read), watches the provider so the widget rebuilds once it settles, and returns the last
/// value [requirement.isSatisfied] read off the real [WidgetRef].
Future<bool?> _isSatisfiedWith(
  WidgetTester tester,
  RouteRequirement requirement, {
  Entitlement? entitlement,
  bool neverResolves = false,
}) async {
  bool? result;
  final completer = Completer<Entitlement?>();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cachedEntitlementProvider.overrideWith((ref) {
          return neverResolves ? completer.future : Future.value(entitlement);
        }),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            // Watch so this Consumer rebuilds once the overridden future settles.
            ref.watch(cachedEntitlementProvider);
            result = requirement.isSatisfied(ref);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('RouteRequirement.module', () {
    testWidgets('true when the cached entitlement offers the module', (tester) async {
      final result = await _isSatisfiedWith(
        tester,
        const RouteRequirement.module('pianificazione'),
        entitlement: _entitlementWith(features: {'pianificazione'}),
      );

      expect(result, isTrue);
    });

    testWidgets('false when the cached entitlement does not offer the module', (tester) async {
      final result = await _isSatisfiedWith(
        tester,
        const RouteRequirement.module('pianificazione'),
        entitlement: _entitlementWith(features: {'rapportini'}),
      );

      expect(result, isFalse);
    });

    testWidgets('null while the cache is still loading — never a bare deny', (tester) async {
      final result = await _isSatisfiedWith(
        tester,
        const RouteRequirement.module('pianificazione'),
        neverResolves: true,
      );

      expect(result, isNull);
    });
  });

  group('RouteRequirement.capability', () {
    testWidgets('true when the cached entitlement holds the capability', (tester) async {
      final result = await _isSatisfiedWith(
        tester,
        const RouteRequirement.capability('pianificazione.schedule.write'),
        entitlement: _entitlementWith(capabilities: {'pianificazione.schedule.write'}),
      );

      expect(result, isTrue);
    });

    testWidgets('false when the cached entitlement lacks the capability', (tester) async {
      final result = await _isSatisfiedWith(
        tester,
        const RouteRequirement.capability('pianificazione.schedule.write'),
        entitlement: _entitlementWith(capabilities: {'pianificazione.schedule.read'}),
      );

      expect(result, isFalse);
    });

    testWidgets('false, not null, when nothing has ever been cached — deny, not "unknown"', (
      tester,
    ) async {
      // Distinct from the loading case: the FutureProvider *resolved* to null (no row has ever
      // been written), which is different from "still resolving". A capability has no safe
      // baseline to guess at (see EntitlementRepository.hasCapability's own doc comment), so this
      // denies rather than stays unresolved.
      final result = await _isSatisfiedWith(
        tester,
        const RouteRequirement.capability('pianificazione.schedule.write'),
        entitlement: null,
      );

      expect(result, isFalse);
    });

    testWidgets('null while the cache is still loading — never a bare deny', (tester) async {
      final result = await _isSatisfiedWith(
        tester,
        const RouteRequirement.capability('pianificazione.schedule.write'),
        neverResolves: true,
      );

      expect(result, isNull);
    });
  });
}
