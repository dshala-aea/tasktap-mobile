// dart format width=100
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart'
    show internalUserIdPrefsKey;
import 'package:tasktap_mobile/data/ferie/absence_request_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;

// Two things live here: the pure JSON parsing (`AbsenceRequestDto` is a plain fromJson factory) and
// the one wire rule this screen exists for.
//
// The rule: an approve-holder is not the audience of "Ferie e Permessi". The server answers a `GET`
// with **everyone's** rows when `userId` is omitted and the caller holds `PresenzeAbsenceApprove`
// (AbsenceRequestsController.List), and this screen renders no requester per row — so an office
// user used to see the whole tenant, unlabelled, under a heading that reads like their own history.
// `myAbsenceRequestsProvider` must therefore put the caller's own id on the wire, read from the
// PERSISTED KEY rather than the cached `internalUserIdProvider` (which on a shared device can still
// hold the previous technician's id).
//
// The HTTP-level assertions use a hand-rolled `HttpClientAdapter` — the same shape
// `smart_working_request_api_client_test.dart` and `badge_api_client_test.dart` use. No
// Dio-mocking package is added.

/// Answers with a canned body and keeps the request it was handed.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.status = 200, this.body = '[]'});

  final int status;
  final String body;
  RequestOptions? captured;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

AbsenceRequestApiClient _client(_Adapter adapter) =>
    AbsenceRequestApiClient(Dio()..httpClientAdapter = adapter);

/// One raw entity, exactly as the server serialises it (ASP.NET default camelCase).
Map<String, dynamic> _row({String id = 'ar-1'}) => {
  'id': id,
  'requestedByUserId': 'user-1',
  'createdByUserId': 'user-1',
  'type': 0,
  'startDate': '2026-09-10',
  'endDate': '2026-09-12',
  'startTime': null,
  'endTime': null,
  'reason': 'Vacanza',
  'status': 0,
  'decidedByUserId': null,
  'decidedAt': null,
  'decisionReason': null,
};

void main() {
  test('AbsenceRequestDto.fromJson parses the full wire shape', () {
    final dto = AbsenceRequestDto.fromJson(_row());

    expect(dto.id, 'ar-1');
    expect(dto.type, 0);
    expect(dto.status, 0);
    expect(dto.startDate, DateTime(2026, 9, 10));
    expect(dto.endDate, DateTime(2026, 9, 12));
  });

  test('AbsenceRequestDto.fromJson handles a partial-time Permesso', () {
    final dto = AbsenceRequestDto.fromJson({
      'id': 'ar-2',
      'requestedByUserId': 'user-1',
      'createdByUserId': 'user-1',
      'type': 1,
      'startDate': '2026-09-10',
      'endDate': '2026-09-10',
      'startTime': '09:00:00',
      'endTime': '11:00:00',
      'reason': null,
      'status': 0,
      'decidedByUserId': null,
      'decidedAt': null,
      'decisionReason': null,
    });

    expect(dto.startTime, '09:00:00');
    expect(dto.endTime, '11:00:00');
  });

  group('myAbsenceRequestsProvider — self scoping', () {
    setUp(() {
      // Every provider test below gets its identity from the persisted key; none overrides
      // `internalUserIdProvider`, so a cached id cannot mask a stale read.
      SharedPreferences.setMockInitialValues(const {});
    });

    test('sendsTheCallersOwnUserId', () async {
      SharedPreferences.setMockInitialValues({internalUserIdPrefsKey: 'user-1'});
      final adapter = _Adapter(body: jsonEncode([_row()]));
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          absenceRequestApiClientProvider.overrideWithValue(_client(adapter)),
          isOnlineProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      // Keep the autoDispose provider alive across the await; a bare `read(.future)` can be
      // disposed between microtasks and refetch or drop the result.
      final sub = container.listen(myAbsenceRequestsProvider, (_, _) {});
      addTearDown(sub.close);

      container.listen(myAbsenceRequestsProvider, (_, _) {});
      final result = await container.read(myAbsenceRequestsProvider.future);

      expect(adapter.captured!.method, 'GET');
      expect(adapter.captured!.path, '/api/absence-requests');
      expect(
        adapter.captured!.queryParameters,
        {'userId': 'user-1'},
        reason:
            'omitted userId means "self" only for a non-Approve caller — for an approve-holder it '
            'means the whole tenant, on a screen that names no requester',
      );
      expect(result.fromDevice, isFalse);
      expect(result.items.single.id, 'ar-1');
    });

    test('unknownCallerId_neverCallsTheApi', () async {
      // Before the first /auth/me there is no internal id to scope by — and an unscoped GET is
      // "the whole tenant" for an approve-holder. The provider answers from the device's own
      // mirror instead, so nothing at all goes on the wire.
      final adapter = _Adapter(body: jsonEncode([_row()]));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          absenceRequestApiClientProvider.overrideWithValue(_client(adapter)),
          isOnlineProvider.overrideWithValue(true),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(myAbsenceRequestsProvider, (_, _) {});
      addTearDown(sub.close);

      container.listen(myAbsenceRequestsProvider, (_, _) {});
      final result = await container.read(myAbsenceRequestsProvider.future);

      expect(adapter.captured, isNull, reason: 'no request may go out unscoped');
      expect(result.fromDevice, isTrue);
      expect(result.items, isEmpty);
    });
  });

  group('AbsenceRequestApiClient — approvals', () {
    test('fetchPendingForApproval_sendsStatusZeroAndNoUserId', () async {
      final adapter = _Adapter(body: jsonEncode([_row()]));
      final client = _client(adapter);

      final rows = await client.fetchPendingForApproval();

      expect(rows.single.id, 'ar-1');
      expect(adapter.captured!.path, '/api/absence-requests');
      expect(adapter.captured!.queryParameters['status'], 0);
      expect(adapter.captured!.queryParameters.containsKey('userId'), isFalse);
    });

    test('approve_postsToTheApproveRoute', () async {
      final adapter = _Adapter(body: '{}');
      final client = _client(adapter);

      await client.approve('ar-1');

      expect(adapter.captured!.method, 'POST');
      expect(adapter.captured!.path, '/api/absence-requests/ar-1/approve');
    });

    test('reject_postsTheTrimmedReason', () async {
      final adapter = _Adapter(body: '{}');
      final client = _client(adapter);

      await client.reject('ar-1', reason: '  Copertura insufficiente  ');

      expect(adapter.captured!.method, 'POST');
      expect(adapter.captured!.path, '/api/absence-requests/ar-1/reject');
      expect(adapter.captured!.data, {'reason': 'Copertura insufficiente'});
    });

    test('a_200_with_no_body_throws_instead_of_an_empty_queue', () async {
      final adapter = _Adapter(body: 'null');
      final client = _client(adapter);

      await expectLater(client.fetchPendingForApproval(), throwsA(isA<FormatException>()));
    });

    test('a_403_becomes_the_permission_error', () async {
      final adapter = _Adapter(status: 403, body: '');
      final client = _client(adapter);

      await expectLater(client.approve('ar-1'), throwsA(isA<AbsenceRequestPermissionError>()));
    });

    test('a_400_detail_becomes_the_validation_error', () async {
      final adapter = _Adapter(
        status: 400,
        body: jsonEncode({
          'detail': 'Solo una richiesta in attesa può essere approvata o rifiutata.',
        }),
      );
      final client = _client(adapter);

      await expectLater(
        client.approve('ar-1'),
        throwsA(
          isA<AbsenceRequestValidationError>().having(
            (e) => e.detail,
            'detail',
            contains('in attesa'),
          ),
        ),
      );
    });
  });
}
