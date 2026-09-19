// test/golden/shell_tabs_golden_test.dart
//
// Note: alchemist 0.12.1's `goldenTest()` no longer accepts a `config:` argument directly (that
// was an older alchemist API). The shared `goldenConfig()` from `goldens_config.dart` is applied
// ambiently instead, via `flutter_test_config.dart` in this same directory — see that file's
// comment for why.
//
// Note: each scenario's `MaterialApp`/`Scaffold` needs an explicit size. `goldenTest`'s default
// image sizing (`BoxConstraints()`, fully unconstrained — see alchemist's README, "Automatic/
// custom image sizing") wraps the whole tree in an `OverflowBox` with unbounded max width/height,
// and `GoldenTestGroup`'s default `Table` layout only bounds a scenario cell once its content
// reports a finite intrinsic size. A `Scaffold` with a `SizedBox.expand()` body does neither under
// those unbounded constraints, so without `scenarioConstraints` this throws
// "RenderCustomMultiChildLayoutBox object was given an infinite size during layout" instead of
// rendering. `scenarioConstraints` below pins each scenario to a fixed phone-width box.
//
// That box constrains layout, but not `MediaQuery.sizeOf(context)` — Flutter's `MediaQuery` comes
// from the test binding's own simulated window (`tester.view.physicalSize`), which alchemist only
// resizes to match the rendered widget *after* the first pump/layout pass, i.e. too late for
// [AppBottomNav]'s own `wideBreakpoint` check, which reads `MediaQuery.sizeOf` during that first
// build. Left alone, the ambient test window is wide enough to pick the rail layout, which then
// overflows the 120px-tall box above. The explicit `MediaQuery` override below is what actually
// selects the compact bar — the widget this task is meant to snapshot.
import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/bottom_nav.dart';

void main() {
  goldenTest(
    'AppBottomNav — all 5 tabs, each as active',
    fileName: 'bottom_nav_tabs',
    builder: () => GoldenTestGroup(
      scenarioConstraints: const BoxConstraints.tightFor(width: 402, height: 120),
      children: [
        for (var i = 0; i < AppBottomNav.defaultItems.length; i++)
          GoldenTestScenario(
            name: AppBottomNav.defaultItems[i].label,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: MediaQuery(
                data: const MediaQueryData(size: Size(402, 120)),
                child: Scaffold(
                  bottomNavigationBar: AppBottomNav(currentIndex: i, onTap: (_) {}),
                  body: const SizedBox.expand(),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
