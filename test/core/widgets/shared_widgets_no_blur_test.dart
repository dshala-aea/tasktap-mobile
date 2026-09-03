import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/app_fab.dart';
import 'package:tasktap_mobile/core/widgets/empty_state.dart';
import 'package:tasktap_mobile/core/widgets/screen_header.dart';

void main() {
  testWidgets('AppFab has no gradient fill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: AppFab(onPressed: () {}, icon: Icons.add),
        ),
      ),
    );
    final decoratedBoxes = tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    );
    for (final box in decoratedBoxes) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration) expect(decoration.gradient, isNull);
    }
    // AppFab paints its own fill on a Container (not a DecoratedBox), so also assert directly on
    // the Container it uses for the circle.
    final containers = tester.widgetList<Container>(find.byType(Container));
    for (final container in containers) {
      final decoration = container.decoration;
      if (decoration is BoxDecoration) expect(decoration.gradient, isNull);
    }
  });

  testWidgets('EmptyState has no BackdropFilter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(icon: Icons.inbox, title: 'Nothing', body: 'Empty'),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('ScreenHeader has no BackdropFilter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ScreenHeader(title: 'Test')),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
