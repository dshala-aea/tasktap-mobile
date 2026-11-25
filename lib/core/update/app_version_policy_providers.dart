// dart format width=100
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api/app_version_policy_api.dart';
import '../../data/api/dio_client.dart';
import '../config/app_info_provider.dart';
import 'app_version_policy_repository.dart';
import 'store_url.dart';
import 'update_required_state.dart';

final appVersionPolicyRepositoryProvider = Provider<AppVersionPolicyRepository>((ref) {
  final api = AppVersionPolicyApi(ref.watch(dioProvider));
  return AppVersionPolicyRepository(
    fetchPolicy: api.fetch,
    store: AppVersionPolicyStore(),
    installedVersion: () async => (await ref.read(appInfoProvider.future)).displayVersion,
    platform: Platform.isIOS ? 'ios' : 'android',
  );
});

/// The installed build judged against the server's version policy.
///
/// Reading it starts the work: the cached policy is applied at once (offline launch works), then a
/// refresh runs in the background. [refresh] is also called when the app returns to the foreground.
/// Nothing here can block the app on a failed fetch.
class AppVersionStatusNotifier extends Notifier<AppVersionStatus> {
  bool _disposed = false;
  bool _refreshing = false;

  AppVersionPolicyRepository get _repo => ref.read(appVersionPolicyRepositoryProvider);

  @override
  AppVersionStatus build() {
    ref.onDispose(() => _disposed = true);
    Future<void>.microtask(_start);
    return AppVersionStatus.none;
  }

  Future<void> _start() async {
    try {
      final cached = await _repo.loadCached();
      if (_disposed) return;
      _apply(cached, fresh: false);
    } catch (_) {}
    await refresh();
  }

  /// Fetches the policy again (launch, resume). Never throws; a failure keeps the cached verdict.
  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    try {
      final result = await _repo.refresh();
      if (_disposed) return;
      _apply(result.status, fresh: result.fresh);
    } catch (_) {
      // The repository does not throw; nothing here may break the shell either way.
    } finally {
      _refreshing = false;
    }
  }

  /// Hides the "update available" banner for 7 days for this build.
  Future<void> dismissAvailable() async {
    final current = state;
    state = current.copyWith(bannerDismissed: true);
    await _repo.dismissAvailable(current);
  }

  void _apply(AppVersionStatus status, {required bool fresh}) {
    state = status;
    final requiredState = ref.read(updateRequiredProvider.notifier);
    final availableState = ref.read(updateAvailableProvider.notifier);
    if (status.updateRequired) {
      requiredState.markRequired();
    } else if (fresh) {
      // The server just said this build is fine (the minimum was lowered): release a running app
      // that an earlier 426/header had marked. A cache-only answer never clears.
      requiredState.clear();
    }
    if (status.updateAvailable) {
      availableState.markAvailable();
    } else if (fresh) {
      availableState.clear();
    }
  }
}

final appVersionStatusProvider = NotifierProvider<AppVersionStatusNotifier, AppVersionStatus>(
  AppVersionStatusNotifier.new,
);

/// Where the "Aggiorna" buttons go: the policy's store URL, else the platform's generic store page.
final storeUriProvider = Provider<Uri>((ref) {
  final storeUrl = ref.watch(appVersionStatusProvider.select((s) => s.storeUrl));
  final packageName = ref.watch(appInfoProvider.select((a) => a.value?.packageName));
  return resolveStoreUri(
    policyUrl: storeUrl,
    isIos: Platform.isIOS,
    androidPackageName: packageName,
  );
});

/// Opens a URL outside the app. A provider so widget tests can record the call.
final storeLauncherProvider = Provider<Future<bool> Function(Uri)>((ref) {
  return (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  };
});
