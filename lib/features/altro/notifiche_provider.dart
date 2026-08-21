import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../data/api/dio_client.dart';
import '../../data/local/app_database.dart';
import '../../data/notifications/notification_api_client.dart';
import '../../data/sync/sync_service.dart';

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
    this.tipo,
    this.relatedEntityId,
    this.relatedEntityType,
  });

  final String id;
  final String titolo;
  final String corpo;
  final DateTime timestamp;
  final bool letta;
  final String? tipo;
  final String? relatedEntityId;
  final String? relatedEntityType;

  AppNotifica copyWith({bool? letta}) {
    return AppNotifica(
      id: id,
      titolo: titolo,
      corpo: corpo,
      timestamp: timestamp,
      letta: letta ?? this.letta,
      tipo: tipo,
      relatedEntityId: relatedEntityId,
      relatedEntityType: relatedEntityType,
    );
  }

  /// Convert from the Drift-generated [AppNotification] row.
  factory AppNotifica.fromDrift(AppNotification row) {
    return AppNotifica(
      id: row.id,
      titolo: row.title,
      corpo: row.message,
      timestamp: row.createdAt,
      letta: row.isRead,
      tipo: row.type,
      relatedEntityId: row.relatedEntityId,
      relatedEntityType: row.relatedEntityType,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Provider
// ══════════════════════════════════════════════════════════════════════════════

// The database provider lives in sync_service.dart. This file used to declare a second one, and
// a second Provider means a second AppDatabase over the same file: two connections, two write
// paths, and the race Drift warns about —
//
//     It looks like you've created the database class AppDatabase multiple times. When these two
//     databases use the same QueryExecutor, race conditions will occur and might corrupt the
//     database.
//
// Notifications are cached offline, so the corruption would land on a technician's own device
// with no server copy to restore from.

/// Notifier that manages notifications backed by Drift cache + backend API.
///
/// On construction, loads from Drift cache (instant offline display).
/// On refresh, fetches from backend and upserts into Drift.
class NotificheNotifier extends StateNotifier<List<AppNotifica>> {
  NotificheNotifier(this._db, this._dio) : super(const []) {
    _loadFromCache();
  }

  final AppDatabase _db;
  final Dio _dio;

  /// Load notifications from Drift cache (fast, offline-first).
  Future<void> _loadFromCache() async {
    final rows =
        await (_db.select(_db.appNotifications)
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(50))
            .get();
    state = rows.map(AppNotifica.fromDrift).toList();
  }

  /// Fetch latest notifications from backend and upsert into Drift.
  Future<void> refresh() async {
    if (Env.apiBaseUrl.isEmpty) return;

    try {
      final client = NotificationApiClient(_dio);
      final page = await client.getNotifications(pageSize: 50);

      // Upsert into Drift cache.
      for (final dto in page.items) {
        await _db
            .into(_db.appNotifications)
            .insertOnConflictUpdate(
              AppNotificationsCompanion.insert(
                id: dto.id,
                tenantId: '',
                createdAt: DateTime.parse(dto.createdAt),
                userId: dto.userId,
                title: dto.title,
                message: dto.message,
                type: dto.type,
                deliveryType: dto.deliveryType,
                isRead: Value(dto.isRead),
                readAt: Value(
                  dto.readAt != null ? DateTime.tryParse(dto.readAt!) : null,
                ),
                relatedEntityId: Value(dto.relatedEntityId),
                relatedEntityType: Value(dto.relatedEntityType),
                scheduledFor: Value(
                  dto.scheduledFor != null
                      ? DateTime.tryParse(dto.scheduledFor!)
                      : null,
                ),
                sentAt: Value(
                  dto.sentAt != null ? DateTime.tryParse(dto.sentAt!) : null,
                ),
                isDelivered: Value(dto.isDelivered),
              ),
            );
      }

      // Reload from cache.
      await _loadFromCache();
    } catch (e) {
      // Offline: cache is already loaded, just keep it.
    }
  }

  /// Mark all notifications as read (local + backend).
  Future<void> segnaLette() async {
    // Update Drift.
    await (_db.update(
      _db.appNotifications,
    )..where((t) => t.isRead.equals(false))).write(
      const AppNotificationsCompanion(
        isRead: Value(true),
        readAt: Value.absent(),
      ),
    );

    // Update state.
    state = state.map((n) => n.copyWith(letta: true)).toList();

    // Sync to backend (best-effort).
    if (Env.apiBaseUrl.isEmpty) return;
    try {
      final client = NotificationApiClient(_dio);
      await client.markAllAsRead();
    } catch (_) {}
  }

  /// Mark a single notification as read (local + backend).
  Future<void> segnaLetta(String id) async {
    // Update Drift.
    await (_db.update(
      _db.appNotifications,
    )..where((t) => t.id.equals(id))).write(
      const AppNotificationsCompanion(
        isRead: Value(true),
        readAt: Value.absent(),
      ),
    );

    // Update state.
    state = state.map((n) => n.id == id ? n.copyWith(letta: true) : n).toList();

    // Sync to backend (best-effort).
    if (Env.apiBaseUrl.isEmpty) return;
    try {
      final client = NotificationApiClient(_dio);
      await client.markAsRead(id);
    } catch (_) {}
  }
}

/// Provider for the notification list.
final notificheProvider =
    StateNotifierProvider<NotificheNotifier, List<AppNotifica>>((ref) {
      final db = ref.watch(appDatabaseProvider);
      final dio = ref.watch(dioProvider);
      return NotificheNotifier(db, dio);
    });

/// Computed count of unread notifications.
final notificheUnreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificheProvider).where((n) => !n.letta).length;
});

/// Provider that triggers a refresh of notifications from the backend.
/// Call `ref.read(notificationRefreshProvider.future)` to refresh.
final notificationRefreshProvider = FutureProvider<void>((ref) async {
  final notifier = ref.read(notificheProvider.notifier);
  await notifier.refresh();
});
