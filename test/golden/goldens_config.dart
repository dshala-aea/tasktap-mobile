// test/golden/goldens_config.dart
import 'package:alchemist/alchemist.dart';

/// Shared alchemist config: the CI variant (Ahem font, platform-independent) is the real gate —
/// it always renders and compares against `goldens/ci/`, identically on every host. The platform
/// variant renders human-readable text and is ALSO always compared in alchemist 0.12.x (no
/// CI-vs-local skip exists, despite the package's own docs describing an older "generated but
/// never compared" behavior for it) — so it's restricted to `HostPlatform.linux`, the only OS this
/// repo has a committed baseline for (`goldens/linux/`). Without this restriction, any non-Linux
/// CI machine (e.g. Codemagic's macOS runner for the iOS release workflow) fails every golden
/// test with a missing-golden-file error, since alchemist looks for a `goldens/macos/` (or
/// `goldens/windows/`) baseline this repo never generates.
AlchemistConfig goldenConfig() {
  return AlchemistConfig(
    platformGoldensConfig: PlatformGoldensConfig(
      enabled: true,
      platforms: {HostPlatform.linux},
    ),
    ciGoldensConfig: const CiGoldensConfig(enabled: true),
  );
}
