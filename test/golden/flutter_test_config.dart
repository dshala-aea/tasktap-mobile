// test/golden/flutter_test_config.dart
//
// `flutter_test` auto-discovers this file for every test under `test/golden/` and wraps
// `main()` with `testExecutable` before it runs. This is how alchemist 0.12.x applies a shared
// `AlchemistConfig` — the package moved off the per-`goldenTest()`-call `config:` parameter that
// older alchemist versions (and this plan's brief) used, in favor of an ambient `Zone` value set
// via `AlchemistConfig.runWithConfig` (see alchemist's own `test/flutter_test_config.dart` and
// `README`, which use this exact pattern). `goldens_config.dart`'s `goldenConfig()` still holds
// the actual CI-vs-local settings; this file is just the (version-specific) wiring that applies
// it to every golden test in this directory.
import 'dart:async';

import 'package:alchemist/alchemist.dart';

import 'goldens_config.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  return AlchemistConfig.runWithConfig(
    config: goldenConfig(),
    run: () async => testMain(),
  );
}
