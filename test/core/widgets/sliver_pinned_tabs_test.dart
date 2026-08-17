import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/app_tabs.dart';

/// The strip stays reachable.
///
/// The ticket detail screen put its tabs in a `SliverToBoxAdapter`, so they scrolled away with the
/// timer and the fact card above them. Reading anything in a tab meant scrolling past all of it,
/// and switching then meant scrolling back up to find the control, choosing, and scrolling down
/// again — on every switch. With seven tabs that round trip *is* the screen, which is why it read
/// as "too many tabs" when the count was not the problem.
///
/// These tests scroll first and assert afterwards, because the whole defect only appears once the
/// page has moved. A test that checks the strip exists at rest passes either way.
void main() {
  const tabs = [
    AppTab(label: 'Report'),
    AppTab(label: 'Controllo'),
    AppTab(label: 'Allegati'),
    AppTab(label: 'Ore'),
  ];

  /// A page shaped like ticket detail: a tall block above the strip, a long list below it.
  Widget harness({
    required bool pinned,
    int selectedIndex = 0,
    ValueChanged<int>? onSelected,
    ScrollController? controller,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 400, child: Text('intestazione'))),
            if (pinned)
              SliverPinnedTabs(
                tabs: tabs,
                selectedIndex: selectedIndex,
                onSelected: onSelected ?? (_) {},
              )
            else
              SliverToBoxAdapter(
                child: AppTabs(
                  tabs: tabs,
                  selectedIndex: selectedIndex,
                  onSelected: onSelected ?? (_) {},
                ),
              ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => SizedBox(height: 80, child: Text('riga $i')),
                childCount: 30,
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('the strip is still on screen after scrolling into the content', (tester) async {
    await tester.pumpWidget(harness(pinned: true));
    await tester.pumpAndSettle();

    expect(find.text('Report'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    // The header is long gone; the strip has not moved.
    expect(find.text('intestazione'), findsNothing);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Ore'), findsOneWidget);
  });

  testWidgets('the unpinned arrangement is the one that loses it', (tester) async {
    // The old behaviour, kept as a control. Without it the test above proves the strip renders,
    // not that pinning is what keeps it there.
    await tester.pumpWidget(harness(pinned: false));
    await tester.pumpAndSettle();

    expect(find.text('Report'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('Report'), findsNothing);
  });

  testWidgets('a tab can be chosen from deep in the content', (tester) async {
    var chosen = -1;
    await tester.pumpWidget(harness(pinned: true, onSelected: (i) => chosen = i));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Allegati'));
    await tester.pumpAndSettle();

    expect(chosen, 2);
  });

  testWidgets('the pinned strip hides the content passing under it', (tester) async {
    // A pinned header is drawn over what scrolls beneath, so a transparent one shows the rows
    // sliding through the labels. Asserted as an opaque background rather than by eye, since this
    // environment cannot render a screenshot.
    await tester.pumpWidget(harness(pinned: true));
    await tester.pumpAndSettle();

    final decorated = tester.widget<DecoratedBox>(
      find
          .ancestor(of: find.byType(AppTabs), matching: find.byType(DecoratedBox))
          .first,
    );
    final decoration = decorated.decoration as BoxDecoration;
    expect(decoration.color, isNotNull);
    expect(decoration.color!.a, 1.0, reason: 'a translucent pinned header shows content through it');
  });

  testWidgets('the strip keeps its selection while the page scrolls', (tester) async {
    await tester.pumpWidget(harness(pinned: true, selectedIndex: 3));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    // Which tab you are in is the thing a pinned strip is for; losing it while scrolling would
    // make the strip decorative.
    //
    // Asserted against the Semantics widget rather than the merged node: AppTabs labels each tab
    // and its Text child carries the same string, so the composed node's label is not reliably a
    // bare 'Ore' to match on.
    final selected = tester.widgetList<Semantics>(find.byType(Semantics)).where(
      (s) => s.properties.label == 'Ore' && s.properties.selected == true,
    );
    expect(selected, hasLength(1));
  });
}
