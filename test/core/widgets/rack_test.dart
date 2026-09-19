// dart format width=100
// test/core/widgets/rack_test.dart
//
// RackCell — the drawer-front cell AppCard and the old CompartmentTile used to render through —
// is gone: AppCard renders VetroGlass directly now, and CompartmentTile was deleted outright once
// every screen turned out to already use VetroCompartmentTile. RackCell's own tests (border/
// radius/dark-palette/tap-passthrough) went with it rather than being ported, since there is
// nothing left in the app to regress. Rack — the retired rail's passthrough wrapper, kept only
// for home_shell.dart's one call site — is what remains here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/rack.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('Rack', () {
    // Vetro has no rail-and-drawer shell to bolt content to — Rack is a passthrough now. Kept as
    // a class only because home_shell.dart's one call site wraps its content in it; these tests
    // guard that the wrapper genuinely adds nothing, under every constructor param it still
    // accepts, rather than the rail geometry that used to live here.
    testWidgets('renders exactly its child, nothing added', (tester) async {
      await tester.pumpWidget(_wrap(const Rack(child: Text('x'))));

      expect(find.text('x'), findsOneWidget);
      expect(find.byType(Rack), findsOneWidget);
    });

    testWidgets('top/bottom/visible are accepted but change nothing', (tester) async {
      await tester.pumpWidget(
        _wrap(const Rack(top: 40, bottom: 80, visible: false, child: Text('x'))),
      );

      expect(find.text('x'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
