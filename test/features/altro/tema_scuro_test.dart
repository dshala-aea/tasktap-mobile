import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/features/altro/impostazioni_provider.dart';

/// The "Tema scuro" switch.
///
/// It existed, it was persisted to SharedPreferences, and nothing read it — the app rendered light
/// whatever it said. That is the same defect as a save button that reports success without saving,
/// and it is the one this file exists to keep from coming back: the assertion is not "a dark theme
/// is defined" but "the setting reaches the rendered widget tree".
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// A stand-in for main.dart's MaterialApp: same wiring, no router or Firebase.
  Widget app() => Consumer(
        builder: (context, ref, _) {
          final dark = ref.watch(impostazioniProvider.select((s) => s.temaScuro));
          return MaterialApp(
            theme: buildAppTheme(),
            darkTheme: buildAppTheme(brightness: Brightness.dark),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: Text('x', style: TextStyle(color: context.colors.ink)),
              ),
            ),
          );
        },
      );

  /// Warms the SharedPreferences plugin before the widget tree exists.
  ///
  /// The notifier calls `getInstance()` in its constructor, which the first time round waits on a
  /// platform channel — and a future created inside the test's fake-async zone does not advance
  /// during `runAsync`. Resolving it up front makes the notifier's call hit the cached instance,
  /// which then completes on a microtask that a plain `pump` flushes.
  Future<void> warmPrefs(WidgetTester tester) =>
      tester.runAsync(() => SharedPreferences.getInstance());

  AppPalette paletteOf(WidgetTester tester) {
    final ctx = tester.element(find.text('x'));
    return Theme.of(ctx).extension<AppPalette>()!;
  }

  testWidgets('defaults to light', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(child: app()));
    await tester.pumpAndSettle();

    expect(paletteOf(tester), AppPalette.light);
  });

  testWidgets('a persisted preference is honoured on launch', (tester) async {
    SharedPreferences.setMockInitialValues({'settings.tema_scuro': true});
    await warmPrefs(tester);
    await tester.pumpWidget(ProviderScope(child: app()));
    await tester.pumpAndSettle();

    expect(paletteOf(tester), AppPalette.dark,
        reason: 'the setting was saved on a previous run and must survive a restart');
  });

  testWidgets('toggling repaints without a restart', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late WidgetRef capturedRef;

    await tester.pumpWidget(ProviderScope(
      child: Consumer(builder: (context, ref, _) {
        capturedRef = ref;
        return app();
      }),
    ));
    await tester.pumpAndSettle();
    expect(paletteOf(tester), AppPalette.light);

    capturedRef.read(impostazioniProvider.notifier).toggle(key: 'temaScuro');
    await tester.pumpAndSettle();

    expect(paletteOf(tester), AppPalette.dark);
  });

  testWidgets('the rendered text colour actually changes, not just the theme object',
      (tester) async {
    SharedPreferences.setMockInitialValues({'settings.tema_scuro': true});
    await warmPrefs(tester);
    await tester.pumpWidget(ProviderScope(child: app()));
    await tester.pumpAndSettle();

    // The end of the chain: a widget reading context.colors under the dark theme paints dark ink.
    // Asserting on the theme alone would pass even if nothing consumed it.
    expect(tester.widget<Text>(find.text('x')).style!.color, AppPalette.dark.ink);
  });

  /// The tests above run against `app()`, which mirrors main.dart's wiring rather than being it —
  /// pumping the real `TaskTapApp` would drag in Firebase and the router. A mirror proves the
  /// mechanism works and proves nothing about the app, which is the exact shape of bug this whole
  /// pass keeps finding, so the wiring itself is asserted here on the source.
  test('main.dart wires themeMode to the setting', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('impostazioniProvider'),
        reason: 'MaterialApp must read the persisted preference');
    expect(source, contains('darkTheme: buildAppTheme(brightness: Brightness.dark)'),
        reason: 'a themeMode with no darkTheme silently renders light');
    expect(source, contains('themeMode:'),
        reason: 'without themeMode the setting reaches nothing — the defect this replaced');
  });
}
