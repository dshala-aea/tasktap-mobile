// dart format width=100
// Field bug 2026-11-06: a button punch reached the server (the office sees it) but the phone kept it
// "in attesa" for ever, and a manual sync "failed" with nothing in the logs.
//
// Root cause, reproduced here with the REAL WorklogApiClient + REAL Drift repository and a Dio
// adapter that answers exactly what the API answers:
//   POST /api/worklog/mobile/sessions → MobileSessionsResponse(MobileSessionResult(ClientId,
//   WorkLogId, TimeSpan StartTime, TimeSpan? EndTime, IsActive, int? ClockDisagreementSeconds))
//   (WorkLogMobileSyncService.cs l.157-166, MobileSessionsDtos.cs l.75-80 on origin/master). The
//   times are .NET TimeSpans — "09:11:00", NOT ISO instants — and the openapi snapshot pins the
//   pattern `^-?(\d+\.)?\d{2}:\d{2}:\d{2}...$`.
// `UpsertSessionResponse.fromJson` called `DateTime.parse("09:11:00")` → FormatException AFTER the
// server had committed; `_pushDay` filed any non-Dio exception under "transient", so markSynced was
// never reached and every retry (the server answers the replay with the same 200) threw again.
//
// The other tests in this directory use fakes that hand back `UpsertSessionResponse` objects, so the
// wire shape was never exercised.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

/// A server that accepts every punch (QrOnly tenant, user override Both: `ClockInMethodPolicy.Allows
/// (Both, ButtonOnly)` is true) and answers the batch with the real serialized shape.
class _ServerAdapter implements HttpClientAdapter {
  final posts = <Map<String, dynamic>>[];

  static String _span(Object? iso) {
    if (iso == null) return 'null';
    final t = DateTime.parse(iso as String).toUtc().add(const Duration(hours: 1));
    String two(int n) => n.toString().padLeft(2, '0');
    return '"${two(t.hour)}:${two(t.minute)}:${two(t.second)}"';
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, '/api/worklog/mobile/sessions');
    final body = options.data as Map<String, dynamic>;
    posts.add(body);
    final sessions = (body['sessions'] as List).cast<Map<String, dynamic>>();
    final json =
        '{"sessions":[${sessions.map((s) => '{"clientId":"${s['clientId']}",'
            '"workLogId":"3f2b8a52-8f5e-4c7e-9d51-0c1f4f6a0001",'
            '"startTime":${_span(s['startTime'])},"endTime":${_span(s['endTime'])},'
            '"isActive":${s['endTime'] == null},"clockDisagreementSeconds":null}').join(',')}]}';
    return ResponseBody.fromString(
      json,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}

void main() {
  late AppDatabase db;
  late WorkSessionRepository repo;
  late _ServerAdapter server;
  late TimbraSyncService sync;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = WorkSessionRepository(db);
    server = _ServerAdapter();
    sync = TimbraSyncService(
      repo: repo,
      apiClient: WorklogApiClient(Dio()..httpClientAdapter = server),
    );
    final now = DateTime.now().toUtc();
    // turno, pausa, ripresa — all button punches, all pending.
    await repo.addEvent(
      id: 'in',
      eventTime: now.subtract(const Duration(minutes: 40)),
      eventType: 'ingresso',
    );
    await repo.addEvent(
      id: 'pausa',
      eventTime: now.subtract(const Duration(minutes: 33)),
      eventType: 'pausa',
    );
    await repo.addEvent(
      id: 'ripresa',
      eventTime: now.subtract(const Duration(minutes: 20)),
      eventType: 'ripresa',
    );
  });
  tearDown(() => db.close());

  test('a batch the server accepted drains the queue (real response shape)', () async {
    await sync.syncNow();

    expect(server.posts, hasLength(1));
    expect(await repo.getPendingCount(), 0, reason: 'the server holds them: nothing is pending');
  });

  test('a manual sync after acceptance stays clean and sends nothing more', () async {
    await sync.syncNow();
    await sync.syncNow(manual: true);

    expect(server.posts, hasLength(1));
    expect(await repo.getPendingCount(), 0);
  });
}
