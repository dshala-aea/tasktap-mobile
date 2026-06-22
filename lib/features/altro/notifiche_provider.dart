import 'package:flutter_riverpod/flutter_riverpod.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Domain model
// ══════════════════════════════════════════════════════════════════════════════

/// A single app notification row.
class AppNotifica {
  const AppNotifica({
    required this.id,
    required this.titolo,
    required this.corpo,
    required this.timestamp,
    this.letta = false,
  });

  final String id;
  final String titolo;
  final String corpo;
  final DateTime timestamp;
  final bool letta;

  AppNotifica copyWith({bool? letta}) {
    return AppNotifica(
      id: id,
      titolo: titolo,
      corpo: corpo,
      timestamp: timestamp,
      letta: letta ?? this.letta,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Provider seam
// ══════════════════════════════════════════════════════════════════════════════

// TODO(backend): wire SignalR / GET /api/notifications when available.
// For now this returns an empty list so the screen shows the EmptyState.

/// Notifier that holds the in-memory list of notifications.
///
/// Replace this with a Drift/SignalR-backed implementation once the backend
/// notifications endpoint is available on mobile.
class NotificheNotifier extends StateNotifier<List<AppNotifica>> {
  NotificheNotifier() : super(const []);

  /// Mark all notifications as read.
  void segnaLette() {
    state = state.map((n) => n.copyWith(letta: true)).toList();
  }

  /// Mark a single notification as read by [id].
  void segnaLetta(String id) {
    state =
        state.map((n) => n.id == id ? n.copyWith(letta: true) : n).toList();
  }
}

/// Provider for the in-memory notification list.
///
/// Seam: override with a real implementation once the backend is ready.
// TODO(backend): replace with an async/stream provider backed by SignalR.
final notificheProvider =
    StateNotifierProvider<NotificheNotifier, List<AppNotifica>>(
  (ref) => NotificheNotifier(),
);

/// Computed count of unread notifications.
final notificheUnreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificheProvider).where((n) => !n.letta).length;
});
