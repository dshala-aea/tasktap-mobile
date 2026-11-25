// dart format width=100
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api/app_version_policy_api.dart';
import 'app_version_evaluator.dart';

/// The installed build judged against the last known policy.
class AppVersionStatus {
  const AppVersionStatus({
    this.policy,
    this.verdict = AppVersionVerdict.ok,
    this.bannerDismissed = false,
  });

  /// No policy known yet (first launch, nothing cached): nothing is required or recommended.
  static const none = AppVersionStatus();

  final AppVersionPolicy? policy;
  final AppVersionVerdict verdict;

  /// The "update available" banner was dismissed for this build within the last 7 days.
  final bool bannerDismissed;

  bool get updateRequired => verdict == AppVersionVerdict.updateRequired;
  bool get updateAvailable => verdict == AppVersionVerdict.updateAvailable;
  String? get storeUrl => policy?.storeUrl;
  String? get message => policy?.message;

  AppVersionStatus copyWith({bool? bannerDismissed}) => AppVersionStatus(
    policy: policy,
    verdict: verdict,
    bannerDismissed: bannerDismissed ?? this.bannerDismissed,
  );
}

/// Outcome of [AppVersionPolicyRepository.refresh]. [fresh] is true only when the server answered
/// in this call; false means [status] was computed from the cache.
typedef AppVersionRefresh = ({AppVersionStatus status, bool fresh});

/// Persists the last good policy and the banner dismissal. Every access is guarded: an unreadable
/// store reads as "nothing cached" and a failed write is dropped.
class AppVersionPolicyStore {
  AppVersionPolicyStore({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  static const policyKey = 'app_version_policy_v1';
  static const dismissedKeyPrefix = 'update_banner_dismissed_at:';

  final Future<SharedPreferences> Function() _prefs;

  Future<AppVersionPolicy?> readPolicy() async {
    try {
      final raw = (await _prefs()).getString(policyKey);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is Map) return AppVersionPolicy.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {}
    return null;
  }

  Future<void> writePolicy(AppVersionPolicy policy) async {
    try {
      await (await _prefs()).setString(policyKey, jsonEncode(policy.toJson()));
    } catch (_) {}
  }

  Future<DateTime?> readDismissedAt(String token) async {
    try {
      final ms = (await _prefs()).getInt('$dismissedKeyPrefix$token');
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDismissedAt(String token, DateTime at) async {
    try {
      await (await _prefs()).setInt('$dismissedKeyPrefix$token', at.millisecondsSinceEpoch);
    } catch (_) {}
  }
}

/// Fetches the version policy, caches the last good answer, and judges the installed build against
/// it locally. A failed fetch never blocks anything: the cached policy (or none) is used.
class AppVersionPolicyRepository {
  AppVersionPolicyRepository({
    required this.fetchPolicy,
    required this.store,
    required this.installedVersion,
    required this.platform,
    DateTime Function()? now,
    this.dismissFor = const Duration(days: 7),
  }) : _now = now ?? DateTime.now;

  final Future<AppVersionPolicy> Function(String platform) fetchPolicy;
  final AppVersionPolicyStore store;

  /// The running build as `1.0.11+42`; null when it cannot be read (then nothing is judged).
  final Future<String?> Function() installedVersion;
  final String platform;
  final DateTime Function() _now;
  final Duration dismissFor;

  /// Status from the cache only (no network): what to show at launch before the fetch returns, and
  /// offline.
  Future<AppVersionStatus> loadCached() async => _statusFor(await store.readPolicy());

  /// Fetches the policy, caches it, and returns the status. On any failure returns the cached
  /// status with `fresh: false`; never throws.
  Future<AppVersionRefresh> refresh() async {
    try {
      final policy = await fetchPolicy(platform);
      await store.writePolicy(policy);
      return (status: await _statusFor(policy), fresh: true);
    } catch (_) {
      return (status: await loadCached(), fresh: false);
    }
  }

  /// Hides the "update available" banner for [dismissFor] (7 days) for this build and policy.
  Future<void> dismissAvailable(AppVersionStatus status) async {
    final token = await _dismissToken(status.policy);
    if (token == null) return;
    await store.writeDismissedAt(token, _now());
  }

  Future<AppVersionStatus> _statusFor(AppVersionPolicy? policy) async {
    if (policy == null) return AppVersionStatus.none;
    final installed = await _installed();
    final verdict = AppVersionEvaluator.evaluate(
      installed,
      policy.minimumVersion,
      policy.recommendedVersion,
    );
    var dismissed = false;
    if (verdict == AppVersionVerdict.updateAvailable) {
      final token = await _dismissToken(policy);
      final at = token == null ? null : await store.readDismissedAt(token);
      if (at != null) {
        final age = _now().difference(at);
        dismissed = !age.isNegative && age < dismissFor;
      }
    }
    return AppVersionStatus(policy: policy, verdict: verdict, bannerDismissed: dismissed);
  }

  // Per installed build and per recommended version: installing the next build, or a newer
  // recommendation, shows the banner again.
  Future<String?> _dismissToken(AppVersionPolicy? policy) async {
    final installed = await _installed();
    if (installed == null) return null;
    return '$installed|${policy?.recommendedVersion ?? ''}';
  }

  Future<String?> _installed() async {
    try {
      return await installedVersion();
    } catch (_) {
      return null;
    }
  }
}
