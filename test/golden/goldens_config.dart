// test/golden/goldens_config.dart
import 'package:alchemist/alchemist.dart';

/// Shared alchemist config: CI renders and compares against committed goldens; local runs
/// (developer machines) render but don't fail on mismatch, since local font rendering varies by
/// OS — matches alchemist's own documented CI-vs-local split, the reason this package was chosen
/// over golden_toolkit (see this plan's spec, Testing section).
AlchemistConfig goldenConfig() {
  return AlchemistConfig(
    platformGoldensConfig: const PlatformGoldensConfig(enabled: true),
    ciGoldensConfig: const CiGoldensConfig(enabled: true),
  );
}
