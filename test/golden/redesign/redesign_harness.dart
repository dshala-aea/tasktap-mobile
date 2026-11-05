// test/golden/redesign/redesign_harness.dart
//
// Review-artifact screenshot harness for the "Il Documento" redesign swarm.
//
// Unlike the committed bottom-nav goldens in `test/golden/`, these are throwaway evidence images:
// they are written to `build/redesign/` (git-ignored), never compared, and never committed as
// baselines. The goal is a deterministic-enough phone frame that can be opened side by side with
// the prototype HTML screenshot produced by `tool/prototype_shot.mjs`.
//
// This lives under `test/golden/` so it inherits the existing alchemist wiring from
// `test/golden/flutter_test_config.dart`; the fonts come from alchemist's own `loadFonts()`,
// which loads the real bundled Archivo / Archivo Narrow / IBM Plex Mono assets declared in
// pubspec.yaml. No pubspec dependency is added.
//
// Usage:
//
//   import 'redesign_harness.dart';
//
//   void main() {
//     setUpAll(loadRedesignFonts);
//
//     testWidgets('cantiere detail', (tester) async {
//       await captureRedesign(
//         tester,
//         'cantiere_detail',
//         child: const CantiereDetailScreen(cantiereId: 'c1'),
//         overrides: [ ...provider overrides... ],
//       );
//     });
//   }
//
// The image is a 780×1688 PNG (390×844 logical px at DPR 2), with the app's real fonts.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alchemist/alchemist.dart' show loadFonts;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';

/// The phone frame every redesign capture uses.
const Size redesignViewportSize = Size(390, 844);

/// Retina capture scale. 2 keeps the PNGs large enough to inspect typography without turning a
/// review sheet into tens of megabytes.
const double redesignDevicePixelRatio = 2;

/// Git-ignored output directory. Deliberately not `test/golden/goldens/`.
const String redesignOutputDirectory = 'build/redesign';

bool _fontsLoaded = false;

/// Loads the app's bundled fonts once per test isolate. Safe to call from `setUpAll`.
Future<void> loadRedesignFonts() async {
  if (_fontsLoaded) return;
  await loadFonts();
  _fontsLoaded = true;
}

/// Pumps [child] in a 390×844 phone frame with [overrides], then writes
/// `build/redesign/<screenName>.png`.
///
/// [child] is the screen (or widget) under review. Put it in a `ProviderScope` via [overrides];
/// this helper owns the scope, the theme and the media query, so callers only pass the screen.
///
/// [settleFrames] defaults to two frames: one to resolve async providers, one to draw their
/// result. Screens with a live ticker should not use `pumpAndSettle`; this helper intentionally
/// never does.
Future<void> captureRedesign(
  WidgetTester tester,
  String screenName, {
  required Widget child,
  List<Override> overrides = const [],
  ThemeData? theme,
  Brightness brightness = Brightness.light,
  Size size = redesignViewportSize,
  double devicePixelRatio = redesignDevicePixelRatio,
  EdgeInsets padding = const EdgeInsets.only(top: 28, bottom: 24),
  TextScaler textScaler = TextScaler.noScaling,
  int settleFrames = 2,
  Duration frameInterval = const Duration(milliseconds: 50),
  Duration realAsyncSettle = const Duration(milliseconds: 100),
}) async {
  await loadRedesignFonts();

  tester.view.physicalSize = size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);

  final captureKey = ValueKey<String>('redesign-capture-$screenName');

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: captureKey,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: devicePixelRatio,
            padding: padding,
            textScaler: textScaler,
          ),
          child: MaterialApp(
            theme: theme ?? buildAppTheme(brightness: brightness),
            // A capture is evidence, not a debug session.
            debugShowCheckedModeBanner: false,
            home: child,
          ),
        ),
      ),
    ),
  );

  await tester.pump();
  for (var i = 1; i < settleFrames; i++) {
    await tester.pump(frameInterval);
  }

  // Drift-backed providers complete on real I/O, which the fake-async test clock does not advance.
  // Give the event loop a slot, then draw what arrived (names instead of raw ids, etc.).
  if (realAsyncSettle > Duration.zero) {
    await tester.runAsync(() => Future<void>.delayed(realAsyncSettle));
    await tester.pump();
  }

  await _writeBoundary(tester, captureKey, screenName, devicePixelRatio);

  // Tear down live tickers/timers before the next test in the same file.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _writeBoundary(
  WidgetTester tester,
  Key key,
  String screenName,
  double devicePixelRatio,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));

  late Uint8List bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: devicePixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('toByteData returned null for $screenName');
      }
      bytes = data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  });

  final directory = Directory(redesignOutputDirectory);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  final file = File('${directory.path}/$screenName.png');
  file.writeAsBytesSync(bytes, flush: true);

  // Useful in CI logs; harmless in local runs.
  // ignore: avoid_print
  print(
    'redesign capture: ${file.absolute.path} (${bytes.lengthInBytes} bytes)',
  );
}
