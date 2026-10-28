// dart format width=100
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart' show internalUserIdPrefsKey;
import 'package:tasktap_mobile/data/ferie/absence_request_api_client.dart' show absenceStatusLabel;
import 'package:tasktap_mobile/data/smart_working/smart_working_request_api_client.dart';

// The wire shape below is the entity the controller returns RAW (`SmartWorkingRequest`), which is
// why there is no response schema in the snapshot to generate a DTO from — see the note above
// SmartWorkingRequestDto in the client.
//
// The one rule this file exists for: an approve-holder is not the audience of this screen. The
// server answers a `GET` with **everyone's** rows when `userId` is omitted and the caller holds
// `PresenzeAbsenceApprove`, so `mySmartWorkingRequestsProvider` must put the caller's own id on the
// wire. That is asserted at the provider level, not just at the client method, because the provider
// is what the screen reads — and against the PERSISTED KEY rather than the cached
// `internalUserIdProvider`, which on a shared device can still hold the previous technician's id.

/// Answers with a canned status/body and keeps the request it was handed — the same adapter shape
/// badge_api_client_test.dart uses.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.status = 200, this.body = '{}'});

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

SmartWorkingRequestApiClient _client(_Adapter adapter) =>
    SmartWorkingRequestApiClient(Dio()..httpClientAdapter = adapter);

/// One raw entity, exactly as the server serialises it (ASP.NET default camelCase).
Map<String, dynamic> _row({
  String id = 'sw-1',
  int status = 0,
  String? reason = 'Lavoro da casa',
  String? decidedByUserId,
  String? decidedAt,
  String? decisionReason,
}) => {
  'id': id,
  'requestedByUserId': 'user-1',
  'createdByUserId': 'user-1',
  'startDate': '2026-09-14',
  'endDate': '2026-09-18',
  'reason': reason,
  'status': status,
  'decidedByUserId': decidedByUserId,
  'decidedAt': decidedAt,
  'decisionReason': decisionReason,
};

void main() {
  group('SmartWorkingRequestDto.fromJson', () {
    test('fromJson_ParsesEveryEntityField', () {
      final decided = SmartWorkingRequestDto.fromJson(
        _row(
          status: 1,
          decidedByUserId: 'boss-1',
          decidedAt: '2026-09-10T08:30:00Z',
          decisionReason: 'ok',
        ),
      );

      expect(decided.id, 'sw-1');
      expect(decided.requestedByUserId, 'user-1');
      expect(decided.createdByUserId, 'user-1');
      // A civil day, read the codebase-wide way: `DateTime.utc(y, m, d)`, never shifted through a
      // zone. West of UTC a local parse of "2026-09-14" is still the 14th here, but a `toLocal()`
      // on a UTC-constructed label would show the 13th.
      expect(decided.startDate, DateTime.utc(2026, 9, 14));
      expect(decided.endDate, DateTime.utc(2026, 9, 18));
      expect(decided.reason, 'Lavoro da casa');
      expect(decided.status, 1);
      expect(decided.decidedByUserId, 'boss-1');
      expect(decided.decidedAt, DateTime.utc(2026, 9, 10, 8, 30));
      expect(decided.decisionReason, 'ok');

      final pending = SmartWorkingRequestDto.fromJson(
        _row(reason: null),
      );
      expect(pending.reason, isNull);
      expect(pending.decidedByUserId, isNull);
      expect(pending.decidedAt, isNull);
      expect(pending.decisionReason, isNull);
    });

    test('fromJson_UnknownStatus_ClampsToALabel', () {
      final dto = SmartWorkingRequestDto.fromJson(_row(status: 99));

      // The raw ordinal is preserved; only the shared label helper clamps. A future server-side
      // status must render something rather than crash a list this screen shares with ferie.
      expect(dto.status, 99);
      expect(() => dto.statusLabel, returnsNormally);
      expect(dto.statusLabel, absenceStatusLabel(dto.status));
      expect(dto.statusLabel, 'Annullata');
    });

    test('fromJson_MissingOrEmptyId_Throws', () {
      // `POST /api/smart-working-requests//cancel` is a 404 the screen can only report as a generic
      // failure, so a row that cannot be identified never becomes a DTO.
      final withoutId = Map<String, dynamic>.from(_row())..remove('id');
      expect(() => SmartWorkingRequestDto.fromJson(withoutId), throwsFormatException);
      expect(() => SmartWorkingRequestDto.fromJson(_row(id: '')), throwsFormatException);
    });

    test('fromJson_MissingStatus_Throws', () {
      // Never default to 0: a missing field would render a decided request as "In attesa".
      final withoutStatus = Map<String, dynamic>.from(_row())..remove('status');
      expect(() => SmartWorkingRequestDto.fromJson(withoutStatus), throwsFormatException);
    });
  });

  group('SmartWorkingRequestApiClient', () {
    setUp(() {
      // Every provider test below must get its identity from the persisted key; none of them
      // overrides `internalUserIdProvider`, so a cached id cannot mask a stale read.
      SharedPreferences.setMockInitialValues(const {});
    });

    test('fetchMine_AlwaysSendsTheCallersOwnUserId', () async {
      SharedPreferences.setMockInitialValues({internalUserIdPrefsKey: 'user-1'});
      final adapter = _Adapter(body: jsonEncode([_row()]));
      final container = ProviderContainer(
        overrides: [
          smartWorkingRequestApiClientProvider.overrideWithValue(_client(adapter)),
        ],
      );
      addTearDown(container.dispose);
      // Keep the autoDispose provider alive across the await; a bare `read(.future)` can be
      // disposed between microtasks and refetch or drop the result.
      final sub = container.listen(mySmartWorkingRequestsProvider, (_, _) {});
      addTearDown(sub.close);

      final items = await container.read(mySmartWorkingRequestsProvider.future);

      expect(adapter.captured!.method, 'GET');
      expect(adapter.captured!.path, '/api/smart-working-requests');
      expect(
        adapter.captured!.queryParameters,
        {'userId': 'user-1'},
        reason:
            'omitted userId means "self" only for a non-Approve caller — for an approve-holder it '
            'means the whole tenant, in a screen titled "le mie richieste"',
      );
      expect(items.single.id, 'sw-1');
    });

    test('unknownUserId_returnsEmpty_andNeverCallsTheApi', () async {
      // Before the first /auth/me there is no internal id to scope by — and an unscoped GET is
      // "the whole tenant" for an approve-holder. Nothing goes on the wire at all, for both shapes
      // an unknown id takes: an absent key, and a key persisted as an empty string.
      final adapter = _Adapter(body: jsonEncode([_row()]));
      final container = ProviderContainer(
        overrides: [
          smartWorkingRequestApiClientProvider.overrideWithValue(_client(adapter)),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(mySmartWorkingRequestsProvider, (_, _) {});
      addTearDown(sub.close);

      for (final unknown in <String?>[null, '']) {
        SharedPreferences.setMockInitialValues({internalUserIdPrefsKey: ?unknown});
        container.invalidate(mySmartWorkingRequestsProvider);

        expect(await container.read(mySmartWorkingRequestsProvider.future), isEmpty);
        expect(
          adapter.captured,
          isNull,
          reason:
              'an unknown caller (${unknown == null ? 'absent key' : 'empty string'}) cannot be '
              'self-scoped: issue no request rather than an unscoped one',
        );
      }
    });

    test('provider_rereadsThePersistedUserId_onEveryRead', () async {
      // A forced sign-out keeps prefs while the next account's /me rewrites the key, so a cached id
      // would scope this screen to the PREVIOUS technician. The provider reads the key every time;
      // pinning that means changing the pref under a live container and reading again.
      SharedPreferences.setMockInitialValues({internalUserIdPrefsKey: 'user-a'});
      final adapter = _Adapter(body: jsonEncode(<dynamic>[]));
      final container = ProviderContainer(
        overrides: [
          smartWorkingRequestApiClientProvider.overrideWithValue(_client(adapter)),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(mySmartWorkingRequestsProvider, (_, _) {});
      addTearDown(sub.close);

      await container.read(mySmartWorkingRequestsProvider.future);
      expect(adapter.captured!.queryParameters, {'userId': 'user-a'});

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(internalUserIdPrefsKey, 'user-b');
      container.invalidate(mySmartWorkingRequestsProvider);
      await container.read(mySmartWorkingRequestsProvider.future);

      expect(adapter.captured!.queryParameters, {'userId': 'user-b'});
    });

    test('fetchMine_withoutAUserId_sendsNoFilter_noUiPathTakesIt', () async {
      // The nullable parameter is a deliberate escape hatch on the client (a manager's queue would
      // pass someone else's id); no path in this app takes it — the provider test above issues no
      // request at all when the caller's id is unknown.
      final adapter = _Adapter(body: jsonEncode(<dynamic>[]));
      await _client(adapter).fetchMine();

      expect(adapter.captured!.queryParameters, isEmpty);
    });

    test('fetchMine_EmptyBody_Throws', () async {
      // A 200 with no body is a contract violation. Answering `[]` there would show "you have filed
      // nothing" for a server that said nothing at all.
      final adapter = _Adapter(body: 'null');

      await expectLater(_client(adapter).fetchMine(), throwsFormatException);
    });

    test('create_SendsIsoCivilDatesAndOmitsAnEmptyReason', () async {
      final adapter = _Adapter(body: jsonEncode({'id': 'sw-1'}));

      // A LOCAL DateTime: the form builds its dates from a picker, and the wire carries the day
      // the technician picked, not the UTC day of the instant that picker produced.
      final id = await _client(adapter).create(
        startDate: DateTime(2026, 9, 14),
        endDate: DateTime(2026, 9, 18),
        reason: '',
      );

      expect(id, 'sw-1');
      expect(adapter.captured!.method, 'POST');
      expect(adapter.captured!.path, '/api/smart-working-requests');
      expect(adapter.captured!.data, {
        'startDate': '2026-09-14',
        'endDate': '2026-09-18',
      });
    });

    test('create_SendsTheReasonWhenPresent', () async {
      final adapter = _Adapter(body: jsonEncode({'id': 'sw-2'}));

      await _client(adapter).create(
        startDate: DateTime.utc(2026, 9, 14),
        endDate: DateTime.utc(2026, 9, 18),
        reason: 'Lavoro da casa',
      );

      expect(adapter.captured!.data, {
        'startDate': '2026-09-14',
        'endDate': '2026-09-18',
        'reason': 'Lavoro da casa',
      });
      // The server resolves a null requestedByUserId to the caller and explicitly does not trust
      // a client-supplied self-id, so the client never sends one.
      expect((adapter.captured!.data as Map).containsKey('requestedByUserId'), isFalse);
    });

    test('create_400WithDetail_BecomesValidationError', () async {
      const detail = 'la data di fine non può precedere la data di inizio';
      final adapter = _Adapter(status: 400, body: jsonEncode({'detail': detail}));

      await expectLater(
        _client(adapter).create(
          startDate: DateTime(2026, 9, 18),
          endDate: DateTime(2026, 9, 14),
        ),
        throwsA(
          isA<SmartWorkingValidationError>().having((e) => e.detail, 'detail', detail),
        ),
      );
    });

    test('cancel_PostsToTheCancelRoute', () async {
      final adapter = _Adapter(body: jsonEncode({'id': 'sw-1'}));

      await _client(adapter).cancel('sw-1');

      expect(adapter.captured!.method, 'POST');
      expect(adapter.captured!.path, '/api/smart-working-requests/sw-1/cancel');
    });
  });
}
