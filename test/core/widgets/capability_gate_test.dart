// Tests for CapabilityGate (lib/core/widgets/capability_gate.dart) — the Flutter equivalent of
// the web's <Can>. Hides its child when the cached entitlement lacks the capability. cachedEntitlement
// -Provider is overridden directly, mirroring route_requirement_test.dart's own harness.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/capability_gate.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';

Entitlement _entitlementWith({Set<String> capabilities = const {}}) {
  return Entitlement(
    features: const {},
    capabilities: capabilities,
    seatType: 'office',
    fetchedAt: DateTime.utc(2026, 9, 23),
  );
}

Future<void> _pumpWith(
  WidgetTester tester, {
  Entitlement? entitlement,
  bool neverResolves = false,
}) async {
  final completer = Completer<Entitlement?>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cachedEntitlementProvider.overrideWith((ref) {
          return neverResolves ? completer.future : Future.value(entitlement);
        }),
      ],
      child: const MaterialApp(
        home: CapabilityGate(
          capability: 'clienti.customer.write',
          child: ElevatedButton(onPressed: null, child: Text('Nuovo Cliente')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the child when the cached entitlement holds the capability', (tester) async {
    await _pumpWith(tester, entitlement: _entitlementWith(capabilities: {'clienti.customer.write'}));

    expect(find.text('Nuovo Cliente'), findsOneWidget);
  });

  testWidgets('hides the child when the cached entitlement lacks the capability', (tester) async {
    await _pumpWith(tester, entitlement: _entitlementWith(capabilities: {'clienti.customer.read'}));

    expect(find.text('Nuovo Cliente'), findsNothing);
  });

  testWidgets('hides the child when nothing has ever been cached', (tester) async {
    await _pumpWith(tester, entitlement: null);

    expect(find.text('Nuovo Cliente'), findsNothing);
  });

  testWidgets('hides the child while the cache is still loading', (tester) async {
    await _pumpWith(tester, neverResolves: true);

    expect(find.text('Nuovo Cliente'), findsNothing);
  });
}
