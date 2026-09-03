import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/ticket/ticket_workflow_api_client.dart';

DioException _err({int? status, Object? body, DioExceptionType? type}) => DioException(
  requestOptions: RequestOptions(path: '/x'),
  type: type ?? DioExceptionType.badResponse,
  response: status == null
      ? null
      : Response<dynamic>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: status,
          data: body,
        ),
);

/// Exercises the client through a Dio wired to a handler that answers however the test needs,
/// so the error mapping is tested where it actually runs rather than through a private static.
TicketWorkflowApiClient _clientThatThrows(DioException e) {
  final dio = Dio();
  dio.httpClientAdapter = _ThrowingAdapter(e);
  return TicketWorkflowApiClient(dio);
}

class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.error);

  final DioException error;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw error;
  }
}

void main() {
  group('TimeSpan parsing', () {
    test('reads HH:MM:SS', () {
      final dto = TicketWorkLogDto.fromJson({
        'id': 'w1',
        'ticketId': 't1',
        'userId': 'u1',
        'workDate': '2026-08-14T00:00:00Z',
        'startTime': '08:30:00',
        'endTime': '11:45:00',
      });

      expect(dto.startTime, const Duration(hours: 8, minutes: 30));
      expect(dto.duration, const Duration(hours: 3, minutes: 15));
      expect(dto.isRunning, isFalse);
    });

    test('reads the D.HH:MM:SS form a timer left running overnight produces', () {
      // .NET renders a TimeSpan past 24h with a leading day component. Without handling it, an
      // overnight timer parses as Duration.zero and the entry silently reads as 0 hours — on the
      // exact case that most needs to be visible.
      final dto = TicketWorkLogDto.fromJson({
        'id': 'w1',
        'ticketId': 't1',
        'userId': 'u1',
        'workDate': '2026-08-14T00:00:00Z',
        'startTime': '1.02:15:00',
      });

      expect(dto.startTime, const Duration(days: 1, hours: 2, minutes: 15));
    });

    test('tolerates fractional seconds', () {
      final dto = TicketWorkLogDto.fromJson({
        'id': 'w1',
        'ticketId': 't1',
        'userId': 'u1',
        'workDate': '2026-08-14T00:00:00Z',
        'startTime': '08:30:12.5470000',
      });

      expect(dto.startTime, const Duration(hours: 8, minutes: 30, seconds: 12));
    });

    test('a running entry has no duration rather than a zero one', () {
      final dto = TicketWorkLogDto.fromJson({
        'id': 'w1',
        'ticketId': 't1',
        'userId': 'u1',
        'workDate': '2026-08-14T00:00:00Z',
        'startTime': '09:00:00',
        'endTime': null,
      });

      expect(dto.isRunning, isTrue);
      // Zero would render as a stopped 0:00 beside a clock that is actually counting — the same
      // fabrication the dashboard hero used to make with its literal '00:00:00'.
      expect(dto.duration, isNull);
    });

    // Regression: an overnight session (start 20:02, end 06:10 next day) has startTime/endTime as
    // bare time-of-day TimeSpans with no date attached — endTime is numerically SMALLER than
    // startTime. A naive endTime-startTime subtraction gives -13:52 instead of +10:08. The backend
    // (TicketWorkLog.DurationHours) already computes this correctly and sends it as durationHours;
    // this DTO must use that value rather than recomputing it wrong from the bare time-of-day pair.
    test('an overnight session uses the backend-computed durationHours, not a naive subtraction', () {
      final dto = TicketWorkLogDto.fromJson({
        'id': 'w1',
        'ticketId': 't1',
        'userId': 'u1',
        'workDate': '2026-08-14T00:00:00Z',
        'startTime': '20:02:00',
        'endTime': '06:10:00',
        'durationHours': 10.133333333333333,
      });

      expect(dto.duration, isNotNull);
      expect(dto.duration!.isNegative, isFalse);
      expect(dto.duration!.inMinutes, 608); // 10h08m
    });

    test('durationHours absent falls back to the naive same-day subtraction (existing behavior)', () {
      // No durationHours in the payload at all — matches a same-day session, where the naive
      // fallback happens to already be correct, so nothing regresses for the common case.
      final dto = TicketWorkLogDto.fromJson({
        'id': 'w1',
        'ticketId': 't1',
        'userId': 'u1',
        'workDate': '2026-08-14T00:00:00Z',
        'startTime': '08:00:00',
        'endTime': '10:30:00',
      });

      expect(dto.duration, const Duration(hours: 2, minutes: 30));
    });
  });

  group('history parsing', () {
    test('reads a field change', () {
      final dto = TicketHistoryEntryDto.fromJson({
        'id': 'h1',
        'ticketId': 't1',
        'fieldName': 'StatusId',
        'oldValue': '1',
        'newValue': '2',
        'changedByUserId': 'u1',
        'changedAt': '2026-08-14T10:00:00Z',
      });

      expect(dto.fieldName, 'StatusId');
      expect(dto.oldValue, '1');
      expect(dto.changedAt, DateTime.utc(2026, 8, 14, 10));
    });
  });

  group('failures say something a technician can act on', () {
    test('a busy timer names the other intervento, not this one', () async {
      final client = _clientThatThrows(
        _err(status: 400, body: 'You already have an active ticket work log. Stop it first.'),
      );

      // "Stop it first" is not actionable when the running clock is on a different ticket than
      // the one on screen, which is exactly when the backend returns this.
      await expectLater(
        () => client.startTimer('t1'),
        throwsA(
          isA<TicketWorkflowFailure>().having(
            (f) => f.message,
            'message',
            contains('un altro intervento'),
          ),
        ),
      );
    });

    test('a closed ticket refuses assignment in Italian', () async {
      final client = _clientThatThrows(_err(status: 400, body: 'Cannot assign a closed ticket'));

      await expectLater(
        () => client.selfAssign('t1'),
        throwsA(
          isA<TicketWorkflowFailure>().having((f) => f.message, 'message', contains('chiuso')),
        ),
      );
    });

    test('no connection is reported as no connection, not as a server error', () async {
      final client = _clientThatThrows(_err(type: DioExceptionType.connectionError));

      await expectLater(
        () => client.stopTimer('t1'),
        throwsA(
          isA<TicketWorkflowFailure>().having(
            (f) => f.message,
            'message',
            contains('Nessuna connessione'),
          ),
        ),
      );
    });

    test('403 says it is a permission problem', () async {
      final client = _clientThatThrows(_err(status: 403, body: ''));

      await expectLater(
        () => client.updateStatus(ticketId: 't1', statusId: 2),
        throwsA(
          isA<TicketWorkflowFailure>().having((f) => f.message, 'message', contains('permessi')),
        ),
      );
    });

    test('an unrecognised server message is not shown raw', () async {
      final client = _clientThatThrows(
        _err(status: 400, body: 'Sequence contains no matching element'),
      );

      await expectLater(
        () => client.startTimer('t1'),
        throwsA(
          isA<TicketWorkflowFailure>()
              // The backend's own words here are an English stack-trace artefact written for an
              // API consumer. The call site's fallback is worse-informed but far more useful.
              .having((f) => f.message, 'message', isNot(contains('Sequence')))
              .having((f) => f.message, 'message', contains('Impossibile avviare il timer')),
        ),
      );
    });
  });
}
