import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/data/kiosk/kiosk_credentials_store.dart';
import 'package:tasktap_mobile/presentation/providers/kiosk_providers.dart';

/// A kiosk credentials store that answers "never activated" immediately.
///
/// The real one reads FlutterSecureStorage over a platform channel that never answers in a
/// widget-test host. `KioskModeNotifier._init` bounds that read with a 5s timeout, whose pending
/// Timer would fail any test that mounts `TaskTapApp`/the router at its end. Tests that mount the
/// real app tree include this override so kiosk mode settles to `{loading: false, active: false}`
/// right away (same pattern as app_router_route_requirement_redirect_test.dart).
class NoKioskCredentialsStore extends KioskCredentialsStore {
  @override
  Future<KioskCredentials?> read() async => null;
}

class _SignedOutAuthRepository extends Mock implements IAuthRepository {
  _SignedOutAuthRepository() {
    when(() => authStateChanges).thenAnswer((_) => Stream<AuthUser?>.value(null));
    when(() => currentUser).thenReturn(null);
  }
}

/// A signed-out auth repository that settles immediately.
///
/// The real `ZitadelAuthRepository` starts a session restore from its constructor; its keychain
/// read never answers in a widget-test host, so the restore's bounded 5s timeout leaves a pending
/// Timer that fails any test reaching `authRepositoryProvider` without overriding it.
Override signedOutAuthOverride() =>
    authRepositoryProvider.overrideWithValue(_SignedOutAuthRepository());

final Override noKioskCredentialsOverride = kioskCredentialsStoreProvider.overrideWithValue(
  NoKioskCredentialsStore(),
);
