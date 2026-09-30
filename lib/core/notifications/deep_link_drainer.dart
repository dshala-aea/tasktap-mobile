import 'notification_service.dart';

/// Turns a stored push-tap intent into a navigation, but only once the app can honour it.
///
/// A push tap can arrive before the router is usable: on cold start `getInitialMessage` resolves
/// while auth is still loading, and an authenticated destination pushed then would be bounced to
/// /login by the redirect guard, losing the intent. So the intent stays parked in the source
/// ([take] only consumes it when [isReady]) and [drain] is called again whenever readiness may
/// have changed (a new tap, auth resolving).
class DeepLinkDrainer {
  DeepLinkDrainer({
    required this.take,
    required this.isReady,
    required this.push,
  });

  /// Consumes the pending intent (e.g. `NotificationService.consumePendingDeepLink`).
  final DeepLinkIntent? Function() take;

  /// True once the user is authenticated and the router can take a `push`.
  final bool Function() isReady;

  /// Pushes a route on top of the current stack (never `go`: it would discard the stack).
  final void Function(String route) push;

  void drain() {
    if (!isReady()) return;
    final route = take()?.resolveRoute();
    if (route != null) push(route);
  }
}
