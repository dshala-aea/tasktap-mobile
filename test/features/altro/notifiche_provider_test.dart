// test/features/altro/notifiche_provider_test.dart
//
// G2 — notification cache scoping, offline read-state and pruning.
//
// Why this file exists: `SessionEnder.endForced` deliberately keeps the local Drift database
// across a forced sign-out, so on a shared van tablet a second technician can land on the same
// cache. Before G2, `_loadFromCache()` read every cached row with no user filter and
// `segnaLette()` marked every unread row read — both regardless of owner — and an offline
// "segna come letta" was silently reverted by the next refresh's upsert of the server's still
// false `isRead`.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/altro/notifiche_provider.dart';

class MockDio extends Mock implements Dio {}

const _me = 'user-a';
const _other = 'user-b';

String _pendingKey(String userId) => 'notifications.pending_read.$userId';

Map<String, dynamic> _item(
  String id, {
  String userId = _me,
  bool isRead = false,
  String createdAt = '2026-08-31T10:00:00Z',
}) => {
  'id': id,
  'userId': userId,
  'title': 'Titolo $id',
  'message': 'Messaggio $id',
  'type': 0,
  'deliveryType': 0,
  'isRead': isRead,
  'isDelivered': true,
  'createdAt': createdAt,
};

Map<String, dynamic> _page(
  List<Map<String, dynamic>> items, {
  int? totalItems,
}) {
  final total = totalItems ?? items.length;
  return {
    'items': items,
    'page': 1,
    'pageSize': 50,
    'totalItems': total,
    'totalPages': (total / 50).ceil(),
    'unreadCount': items.where((i) => i['isRead'] == false).length,
  };
}

Response<dynamic> _ok(Map<String, dynamic> data, String path) => Response<dynamic>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: data,
);

DioException _networkFailure() =>
    DioException(requestOptions: RequestOptions(path: '/api/notifications'));

DioException _notFound(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: 404,
    data: {
      'title': 'Not Found',
    },
  ),
);

void _stubPage(MockDio dio, Map<String, dynamic> page) {
  when(
    () => dio.get<dynamic>(
      '/api/notifications',
      queryParameters: any(named: 'queryParameters'),
    ),
  ).thenAnswer((_) async => _ok(page, '/api/notifications'));
}

Future<void> _seed(
  AppDatabase db,
  String id, {
  required String userId,
  bool isRead = false,
}) {
  return db
      .into(db.appNotifications)
      .insertOnConflictUpdate(
        AppNotificationsCompanion.insert(
          id: id,
          tenantId: 't1',
          createdAt: DateTime.utc(2026, 8, 31, 10),
          userId: userId,
          title: 'Titolo $id',
          message: 'Messaggio $id',
          type: 'TicketAssigned',
          deliveryType: 'InApp',
          isRead: Value(isRead),
        ),
      );
}

Future<List<AppNotification>> _cached(AppDatabase db) =>
    db.select(db.appNotifications).get();

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late MockDio dio;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dio = MockDio();
    SharedPreferences.setMockInitialValues({'internal_user_id': _me});
    // Default: the read-state PUT never reaches the server (an offline device). A marker must
    // then survive; tests that need a success or a 404 restub the specific call.
    when(() => dio.put<dynamic>(any())).thenThrow(_networkFailure());
  });

  tearDown(() async {
    await db.close();
  });

  /// Builds a notifier over [db] whose `refresh()` is NOT short-circuited by the empty
  /// `String.fromEnvironment` base URL that `flutter test` always has.
  Future<NotificheNotifier> build(ProviderContainer container) async {
    late NotificheNotifier notifier;
    container.read(notificheProvider);
    // The constructor's cache load is async and not awaitable from outside; let it settle.
    await pumpEventQueue();
    notifier = container.read(notificheProvider.notifier);
    return notifier;
  }

  ProviderContainer newContainer() {
    final container = ProviderContainer(
      overrides: [
        notificheProvider.overrideWith(
          (ref) => NotificheNotifier(
            db,
            dio,
            ref,
            apiBaseUrl: 'https://api.test',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('G2a — the cache is scoped to the current internal user', () {
    test('loads only the signed-in user\'s cached rows', () async {
      await _seed(db, 'a1', userId: _me);
      await _seed(db, 'a2', userId: _me, isRead: true);
      await _seed(db, 'b1', userId: _other);

      final notifier = await build(newContainer());

      expect(notifier.state.map((n) => n.id).toSet(), {'a1', 'a2'});
    });

    test('shows nothing — not everything — when no internal user id is known', () async {
      SharedPreferences.setMockInitialValues({});
      await _seed(db, 'a1', userId: _me);
      await _seed(db, 'b1', userId: _other);

      final notifier = await build(newContainer());

      expect(notifier.state, isEmpty);
    });

    test('segnaLette marks only the current user\'s rows read', () async {
      await _seed(db, 'a1', userId: _me);
      await _seed(db, 'b1', userId: _other);

      final notifier = await build(newContainer());
      await notifier.segnaLette();

      final rows = {for (final r in await _cached(db)) r.id: r.isRead};
      expect(rows['a1'], isTrue);
      expect(rows['b1'], isFalse, reason: 'another user\'s unread row was marked read');
    });

    test('segnaLetta refuses to touch another user\'s row', () async {
      await _seed(db, 'b1', userId: _other);

      final notifier = await build(newContainer());
      await notifier.segnaLetta('b1');

      final row = (await _cached(db)).single;
      expect(row.isRead, isFalse);
      expect(notifier.state, isEmpty);
    });
  });

  group('G2b — an offline read survives the next refresh', () {
    test('segnaLetta records a pending read marker before the request', () async {
      await _seed(db, 'a1', userId: _me);

      final notifier = await build(newContainer());
      await notifier.segnaLetta('a1');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(_pendingKey(_me)), contains('a1'));
    });

    test('a refresh that still says unread does not revert a pending local read', () async {
      await _seed(db, 'a1', userId: _me);
      _stubPage(dio, _page([_item('a1')]));
      // The retried PUT fails (still offline): the marker must survive.
      when(() => dio.put<dynamic>(any())).thenThrow(_networkFailure());

      final notifier = await build(newContainer());
      await notifier.segnaLetta('a1');
      await notifier.refresh();

      expect(notifier.state.single.letta, isTrue);
      final row = (await _cached(db)).single;
      expect(row.isRead, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(_pendingKey(_me)), contains('a1'));
    });

    test('the next successful refresh flushes the marker and clears it', () async {
      await _seed(db, 'a1', userId: _me);
      _stubPage(dio, _page([_item('a1')]));

      final notifier = await build(newContainer());
      // Offline: the mark is applied locally and its marker has no way out yet.
      await notifier.segnaLetta('a1');
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(_pendingKey(_me)), contains('a1'));

      // The connection is back.
      when(() => dio.put<dynamic>(any())).thenAnswer(
        (_) async => _ok({}, '/api/notifications/a1/read'),
      );
      await notifier.refresh();

      prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(_pendingKey(_me)), isNull);
      expect((await _cached(db)).single.isRead, isTrue);
    });

    test(
      'a 404 is definitive: it clears the marker, and the server page is the authority after',
      () async {
        await _seed(db, 'a1', userId: _me);
        _stubPage(dio, _page([_item('a1')]));

        final notifier = await build(newContainer());
        // Offline mark (the setUp stub's PUT is a network failure): only the marker protects the
        // local read now.
        await notifier.segnaLetta('a1');
        var prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(_pendingKey(_me)), contains('a1'));

        // The retried PUT is answered definitively: there is no such notification server-side.
        when(
          () => dio.put<dynamic>('/api/notifications/a1/read'),
        ).thenThrow(_notFound('/api/notifications/a1/read'));

        // This refresh still shows it read: the marker was in force when the upsert ran, and a
        // 404 is a definitive answer, not a non-answer.
        await notifier.refresh();
        expect(notifier.state.single.letta, isTrue);
        prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(_pendingKey(_me)), isNull);

        // With the marker settled, the page is authoritative. This (deliberately contradictory)
        // server still lists the row as unread, so it comes back unread — the chosen rule is
        // "404 settles the marker", not "keep retrying forever". Keeping the marker would pin the
        // row read and block its pruning.
        await notifier.refresh();
        expect(notifier.state.single.letta, isFalse);
        expect((await _cached(db)).single.isRead, isFalse);
      },
    );
  });

  group('G2c — pruning', () {
    test('drops this user\'s rows the authoritative page no longer contains', () async {
      await _seed(db, 'a1', userId: _me);
      await _seed(db, 'a2', userId: _me);
      await _seed(db, 'b1', userId: _other);
      _stubPage(dio, _page([_item('a1')]));

      final notifier = await build(newContainer());
      await notifier.refresh();

      final ids = (await _cached(db)).map((r) => r.id).toSet();
      expect(ids, {'a1', 'b1'}, reason: 'a2 was pruned; another user\'s b1 was not touched');
      expect(notifier.state.map((n) => n.id), ['a1']);
    });

    test('does not prune when the page is only a window over a larger set', () async {
      await _seed(db, 'a1', userId: _me);
      await _seed(db, 'a2', userId: _me);
      // 120 InApp notifications exist; the page carries only the newest one.
      _stubPage(dio, _page([_item('a1')], totalItems: 120));

      final notifier = await build(newContainer());
      await notifier.refresh();

      final ids = (await _cached(db)).map((r) => r.id).toSet();
      expect(ids, {'a1', 'a2'});
    });

    test('never prunes a row that still has a pending read marker', () async {
      await _seed(db, 'a1', userId: _me);
      await _seed(db, 'a2', userId: _me);
      SharedPreferences.setMockInitialValues({
        'internal_user_id': _me,
        // a2 was read locally but the notification is no longer on the page.
        _pendingKey(_me): ['a2'],
      });
      _stubPage(dio, _page([_item('a1')]));
      when(() => dio.put<dynamic>(any())).thenThrow(_networkFailure());

      final notifier = await build(newContainer());
      await notifier.refresh();

      final ids = (await _cached(db)).map((r) => r.id).toSet();
      expect(ids, {'a1', 'a2'});
    });

    test('never writes another user\'s notification from the page into this cache', () async {
      await _seed(db, 'a1', userId: _me);
      _stubPage(dio, _page([_item('a1'), _item('b1', userId: _other)]));

      final notifier = await build(newContainer());
      await notifier.refresh();

      final ids = (await _cached(db)).map((r) => r.id).toSet();
      expect(ids, {'a1'});
      expect(notifier.state.map((n) => n.id), ['a1']);
    });
  });
}
