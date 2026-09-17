// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether [userId] has completed the onboarding flow — per account, not per device, so a
/// technician signing into a shared/handed-down phone still gets it once for themselves.
///
/// Purely local device state with nothing to sync to a backend, unlike `impostazioniProvider`'s
/// settings — that's why this is its own small provider instead of folded into that one.
final onboardingCompletedProvider =
    AsyncNotifierProvider.family<OnboardingCompletedNotifier, bool, String>(
      OnboardingCompletedNotifier.new,
    );

class OnboardingCompletedNotifier extends FamilyAsyncNotifier<bool, String> {
  @override
  Future<bool> build(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  /// Marks onboarding done for this notifier's user. The router's redirect gate re-reads this
  /// provider on the next rebuild it triggers (see `_OnboardingStateListenable` in
  /// `app_router.dart`) and stops sending this user back here.
  Future<void> markCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(arg), true);
    } catch (_) {
      // A failed local write is not worth trapping the technician on this screen forever —
      // the worst case is onboarding shows again next login, which is recoverable; getting
      // stuck here is not.
    }
    state = const AsyncData(true);
  }

  static String _key(String userId) => 'onboarding.completed.$userId';
}
