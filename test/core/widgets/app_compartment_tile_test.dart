import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/app_compartment_tile.dart';

void main() {
  testWidgets('AppCompartmentTile has no BackdropFilter and calls onTap', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AppCompartmentTile(
            icon: Icons.build,
            label: 'Materiali',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.byType(AppCompartmentTile));
    expect(tapped, isTrue);
  });
}
