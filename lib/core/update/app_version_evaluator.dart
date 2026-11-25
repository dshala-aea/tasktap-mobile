// dart format width=100
/// Dart port of the API's `AppVersionEvaluator` (`TaskTapAPI.Api.AppVersioning`). Keep the two in
/// step: the same rules decide whether the server answers 426 and whether this app shows the
/// blocking screen, so a drift would show a block the server does not enforce (or the reverse).
library;

enum AppVersionVerdict { ok, updateAvailable, updateRequired }

/// A parsed `X.Y.Z` or `X.Y.Z+N`. [build] is null when there was no `+N`.
class ParsedVersion {
  const ParsedVersion(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;
  final int? build;
}

/// Pure version gate. Semver (before `+`) decides first; the build number only matters when the
/// semver is equal AND the policy carries a `+N` (a client without `+N` counts as build 0).
/// Anything unparseable, client or policy, never blocks: the gate fails open.
abstract final class AppVersionEvaluator {
  static const _maxLength = 64;

  // ASCII digits only ([0-9], not \d) and `$` anchors at the very end: no full-width digits, no
  // trailing newline, no pre-release suffix. The build group allows 10 digits: Android release
  // builds use `--build-number=$(date +%s)` (epoch seconds, ~1.8e9). Dart ints are 64-bit.
  static final _pattern = RegExp(r'^([0-9]{1,9})\.([0-9]{1,9})\.([0-9]{1,9})(?:\+([0-9]{1,10}))?$');

  static ParsedVersion? tryParse(String? v) {
    if (v == null || v.isEmpty || v.length > _maxLength) return null;
    final m = _pattern.firstMatch(v);
    if (m == null) return null;
    final major = int.tryParse(m.group(1)!);
    final minor = int.tryParse(m.group(2)!);
    final patch = int.tryParse(m.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    int? build;
    final rawBuild = m.group(4);
    if (rawBuild != null) {
      build = int.tryParse(rawBuild);
      if (build == null) return null;
    }
    return ParsedVersion(major, minor, patch, build);
  }

  static AppVersionVerdict evaluate(String? clientVersion, String? minimum, String? recommended) {
    final client = tryParse(clientVersion);
    if (client == null) return AppVersionVerdict.ok;

    final min = tryParse(minimum);
    if (min != null && _isBelow(client, min)) return AppVersionVerdict.updateRequired;
    final rec = tryParse(recommended);
    if (rec != null && _isBelow(client, rec)) return AppVersionVerdict.updateAvailable;
    return AppVersionVerdict.ok;
  }

  static bool _isBelow(ParsedVersion client, ParsedVersion policy) {
    final c = _compare(
      [client.major, client.minor, client.patch],
      [policy.major, policy.minor, policy.patch],
    );
    if (c != 0) return c < 0;
    final policyBuild = policy.build;
    return policyBuild != null && (client.build ?? 0) < policyBuild;
  }

  static int _compare(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0) return c;
    }
    return 0;
  }
}
