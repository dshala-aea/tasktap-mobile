import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/env.dart';
import '../../data/api/dio_client.dart';
import '../../data/entitlements/entitlement_service.dart'
    show internalUserIdPrefsKey;
import '../../data/local/app_database.dart';
import '../../data/notifications/notification_api_client.dart';
import '../../data/sync/sync_service.dart';
import '../../presentation/providers/auth_providers.dart'
    show currentUserProvider;

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
// Pending read-state
//
// `PUT /api/notifications/{id}/read` is best-effort: a technician marking a notification read in
// a basement gets a failed request and nothing else. Before this marker existed, the next
// `refresh()` upserted the server's still-false `isRead` straight back over the local row, so the
// notification silently became unread again.
//
// The marker is written BEFORE the request (the same rule as
// `impostazioni_provider.dart`'s `_kNotifichePending`): a process killed mid-flight must not leave
// a read that is local-only with nothing recording that it was never sent.
//
// One SharedPreferences list per internal user id. The ids are globally unique, but keying by
// owner keeps a retained-data device from flushing (or preserving) a previous account's markers
// under the next account's identity. No Drift schema step.
// ══════════════════════════════════════════════════════════════════════════════

const _kPendingReadPrefix = 'notifications.pending_read';

String _pendingReadKey(String userId) => '$_kPendingReadPrefix.$userId';

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
///
/// ## Every row is scoped to the current internal user
///
/// `SessionEnder.endForced` deliberately KEEPS the local database across a forced sign-out (audit
/// F1: unsent work must survive a dead refresh token), so on a shared van tablet a second
/// technician can land on the same Drift file. Every read and every write here is therefore
/// filtered by `AppNotifications.userId`; with no known user id the list is empty rather than
/// "everything", because "everything" is exactly what leaked before.
class NotificheNotifier extends StateNotifier<List<AppNotifica>> {
  /// [apiBaseUrl] exists so unit tests can exercise [refresh] — `Env.apiBaseUrl` is a
  /// `String.fromEnvironment` constant that is empty under `flutter test`, which would otherwise
  /// turn every refresh into the "unconfigured build" early return. Production callers omit it.
  NotificheNotifier(
    this._db,
    this._dio,
    this._ref, {
    String? apiBaseUrl,
  }) : _apiBaseUrl = apiBaseUrl ?? Env.apiBaseUrl,
       super(const []) {
    _loadFromCache();
  }

  final AppDatabase _db;
  final Dio _dio;
  final Ref _ref;
  final String _apiBaseUrl;

  /// The backend caps `pageSize` at 100; the cache and the screen show the newest 50.
  static const _pageSize = 50;

  /// The signed-in user's INTERNAL database id (`Users.Id`), the value
  /// `AppNotifications.userId` holds.
  ///
  /// Read from the same SharedPreferences key `internalUserIdProvider` reads
  /// ([internalUserIdPrefsKey], persisted by `EntitlementService.refresh` from `/api/Auth/me`).
  /// Deliberately not `ref.read(internalUserIdProvider.future)`: that FutureProvider caches its
  /// first value for the container's lifetime, and on a shared device the key can change under it
  /// (forced sign-out keeps prefs; the next account's `/me` rewrites the key). The key stays the
  /// single source of truth — this just reads it fresh.
  ///
  /// Null before the first successful `/me`, or after a consented sign-out wiped prefs.
  Future<String?> _currentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(internalUserIdPrefsKey);
  }

  Future<Set<String>> _pendingReadIds(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_pendingReadKey(userId)) ?? const <String>[])
        .toSet();
  }

  Future<void> _setPendingReadIds(String userId, Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await prefs.remove(_pendingReadKey(userId));
    } else {
      await prefs.setStringList(_pendingReadKey(userId), ids.toList());
    }
  }

  /// Load notifications from Drift cache (fast, offline-first).
  Future<void> _loadFromCache() async {
    try {
      final userId = await _currentUserId();
      if (!mounted) return;
      if (userId == null || userId.isEmpty) {
        // No identity → nothing of anybody's. Falling back to "all rows" here is what made one
        // technician's notifications visible to the next on a shared device.
        state = const [];
        return;
      }

      final rows =
          await (_db.select(_db.appNotifications)
                ..where((t) => t.userId.equals(userId))
                ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
                ..limit(_pageSize))
              .get();
      if (!mounted) return;
      state = rows.map(AppNotifica.fromDrift).toList();
    } catch (e) {
      // Fail closed. An unreadable identity or cache must show nothing, never an unscoped list.
      debugPrint('NotificheNotifier._loadFromCache failed: $e');
      if (mounted) state = const [];
    }
  }

  /// Fetch latest notifications from backend and upsert into Drift.
  Future<void> refresh() async {
    if (_apiBaseUrl.isEmpty) return;

    final userId = await _currentUserId();
    if (!mounted) return;
    if (userId == null || userId.isEmpty) {
      // Nothing can be scoped to an owner we do not know, and the endpoint's answer cannot be
      // attributed either. Show an empty list — never another account's rows.
      state = const [];
      return;
    }

    try {
      final client = NotificationApiClient(_dio);
      final page = await client.getNotifications(pageSize: _pageSize);

      // A read the server has not confirmed yet survives this fetch: the upsert keeps the local
      // `true` instead of writing the page's stale `false` back over it.
      final pending = await _pendingReadIds(userId);
      final pageIds = <String>{};

      for (final dto in page.items) {
        // The endpoint is user-scoped (`GetUserNotificationsAsync(currentUserId, …)`), so a row
        // for anyone else can only mean a server bug — never write it into this local cache.
        if (dto.userId.toLowerCase() != userId.toLowerCase()) continue;
        pageIds.add(dto.id);

        final locallyRead = pending.contains(dto.id);
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
                isRead: Value(locallyRead || dto.isRead),
                readAt: Value(
                  locallyRead
                      ? null
                      : (dto.readAt != null
                            ? DateTime.tryParse(dto.readAt!)
                            : null),
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

      // Retry whatever the server never acknowledged. Before pruning, so an id that flushes
      // successfully is no longer a "pending" reason to keep an old row.
      await _flushPendingReads(client, userId, pending);

      // Prune rows the authoritative page no longer contains.
      //
      // The page is the whole set only while it covers the user's total: `GET /api/notifications`
      // is `page=1, pageSize=50` ordered `createdAt desc` over the user's InApp rows, counted with
      // the same predicate. With more than 50 rows the page is a window, and deleting everything
      // outside it would throw away rows that still exist — so pruning only happens when the page
      // covers the total.
      if (page.totalItems <= pageIds.length) {
        final stillPending = await _pendingReadIds(userId);
        final keep = {...pageIds, ...stillPending};
        // One predicate: `DeleteStatement.where` replaces rather than ANDs, so the ownership
        // filter must live in the same closure as the id filter.
        await (_db.delete(_db.appNotifications)..where(
          (t) => keep.isEmpty
              ? t.userId.equals(userId)
              : t.userId.equals(userId) & t.id.isNotIn(keep.toList()),
        )).go();
      }

      // Reload from cache.
      await _loadFromCache();
      if (mounted) {
        _ref.read(notificheHasErrorProvider.notifier).state = false;
      }
    } catch (e) {
      // The cache (already loaded) is kept either way — this isn't only "offline", it also
      // catches a 401/403 from a stale token or a revoked permission, which used to look
      // identical to "no notifications" with nothing to tell the two apart. The flag lets the
      // screen show a distinct error state instead of a silently-empty inbox.
      debugPrint('NotificheNotifier.refresh failed: $e');
      if (mounted) {
        _ref.read(notificheHasErrorProvider.notifier).state = true;
      }
    }
  }

  /// The one place the pending-read rule is defined: a marker is dropped when the server gives a
  /// DEFINITIVE answer, and kept for anything less.
  ///
  /// - 2xx — applied; there is nothing left to send.
  /// - 404 — there is no such notification server-side. That is definitive, not a transient
  ///   failure: the local read has nothing left to protect, so the marker goes and the server's
  ///   page is the authority from the next fetch on (if the page still lists the row, it shows as
  ///   unread again — the server said two contradictory things, and the page wins once no marker
  ///   is in force). Treating 404 as "keep retrying" would pin the row read forever and block
  ///   pruning it.
  /// - Anything else (timeout, no network, 5xx, auth) — a non-answer. The marker stays, so the
  ///   locally applied read survives the next refresh's upsert and is retried.
  Future<void> _flushPendingReads(
    NotificationApiClient client,
    String userId,
    Set<String> pending,
  ) async {
    if (pending.isEmpty) return;

    final confirmed = <String>{};
    for (final id in pending) {
      try {
        await client.markAsRead(id);
        confirmed.add(id);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          confirmed.add(id);
        } else {
          debugPrint(
            'NotificheNotifier.markAsRead($id) failed: '
            '${e.response?.statusCode ?? e.message}',
          );
        }
      } catch (e) {
        debugPrint('NotificheNotifier.markAsRead($id) failed: $e');
      }
    }

    if (confirmed.isEmpty) return;
    // Re-read rather than writing the [pending] snapshot back: a concurrent `segnaLetta` may have
    // added a marker after this refresh started, and dropping it would revert that read.
    final current = await _pendingReadIds(userId);
    await _setPendingReadIds(userId, current.difference(confirmed));
  }

  /// Mark all notifications as read (local + backend).
  Future<void> segnaLette() async {
    final userId = await _currentUserId();
    if (!mounted) return;
    if (userId == null || userId.isEmpty) return;

    // Captured before the write: these are the rows this call changes, so they are exactly the
    // ones a server read-all has to acknowledge.
    final unreadIds = state
        .where((n) => !n.letta)
        .map((n) => n.id)
        .toList();

    // Update Drift — only this user's rows.
    await (_db.update(
      _db.appNotifications,
    )..where((t) => t.userId.equals(userId) & t.isRead.equals(false))).write(
      const AppNotificationsCompanion(
        isRead: Value(true),
        readAt: Value.absent(),
      ),
    );

    // Update state.
    if (mounted) {
      state = state.map((n) => n.copyWith(letta: true)).toList();
    }

    if (unreadIds.isNotEmpty) {
      // Written before the request — see this file's pending-marker comment.
      await _setPendingReadIds(userId, {
        ...await _pendingReadIds(userId),
        ...unreadIds,
      });
    }

    // Sync to backend (best-effort).
    if (_apiBaseUrl.isEmpty) return;
    try {
      final client = NotificationApiClient(_dio);
      await client.markAllAsRead();
      // Read-all applied to every row that existed when it ran, so the rows this call changed are
      // settled. Re-read and remove only those, so a marker a concurrent tap added meanwhile
      // survives.
      final current = await _pendingReadIds(userId);
      await _setPendingReadIds(
        userId,
        current.difference(unreadIds.toSet()),
      );
    } on DioException catch (e) {
      // A 404 here is NOT "already applied" — it means the route is missing, nothing was marked,
      // and claiming success would make the list lie about the server. Keep the markers.
      debugPrint('NotificheNotifier.segnaLette sync failed: ${e.response?.statusCode ?? e.message}');
    } catch (e) {
      debugPrint('NotificheNotifier.segnaLette sync failed: $e');
    }
  }

  /// Mark a single notification as read (local + backend).
  Future<void> segnaLetta(String id) async {
    final userId = await _currentUserId();
    if (!mounted) return;
    if (userId == null || userId.isEmpty) return;

    // Update Drift — the id must belong to this user, or a stale tap could mark someone else's
    // retained row.
    await (_db.update(
      _db.appNotifications,
    )..where((t) => t.id.equals(id) & t.userId.equals(userId))).write(
      const AppNotificationsCompanion(
        isRead: Value(true),
        readAt: Value.absent(),
      ),
    );

    // Update state.
    if (mounted) {
      state = state.map((n) => n.id == id ? n.copyWith(letta: true) : n).toList();
    }

    // Written before the request — see this file's pending-marker comment.
    await _setPendingReadIds(userId, {
      ...await _pendingReadIds(userId),
      id,
    });

    // Sync to backend (best-effort). Same rule as every other flush — see
    // [_flushPendingReads]: 2xx or 404 settles this id, anything else keeps its marker.
    if (_apiBaseUrl.isEmpty) return;
    try {
      await _flushPendingReads(
        NotificationApiClient(_dio),
        userId,
        {id},
      );
    } catch (e) {
      debugPrint('NotificheNotifier.segnaLetta sync failed: $e');
    }
  }
}

/// Provider for the notification list.
///
/// Rebuilt whenever the signed-in OIDC identity changes (sign-out, or a different account
/// signing in). Without this the notifier — and its in-memory list — outlived the session, so a
/// forced sign-out that keeps the local data could leave the previous technician's notifications
/// in memory for the next one.
final notificheProvider =
    StateNotifierProvider<NotificheNotifier, List<AppNotifica>>((ref) {
      ref.watch(currentUserProvider.select((u) => u?.id));
      final db = ref.watch(appDatabaseProvider);
      final dio = ref.watch(dioProvider);
      return NotificheNotifier(db, dio, ref);
    });

/// Computed count of unread notifications.
final notificheUnreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificheProvider).where((n) => !n.letta).length;
});

/// Whether the last [NotificheNotifier.refresh] call failed. The Drift cache still shows
/// whatever it had before the failure — this just lets the screen tell "genuinely no
/// notifications" apart from "couldn't reach the server".
final notificheHasErrorProvider = StateProvider<bool>((ref) => false);

/// Provider that triggers a refresh of notifications from the backend.
/// Call `ref.read(notificationRefreshProvider.future)` to refresh.
final notificationRefreshProvider = FutureProvider<void>((ref) async {
  final notifier = ref.read(notificheProvider.notifier);
  await notifier.refresh();
});
