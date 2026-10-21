// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/cantiere_timbra_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

/// Answer/record fake for the live endpoint. [error] set means every call throws — which is also
/// how "the offline path never touched the network" is proven: the offline branch would surface the
/// throw as an `AsyncError` instead of the mirror.
class _FakeCrewClient extends CantiereWorklogApiClient {
  _FakeCrewClient({this.answer, this.error}) : super(Dio());

  final List<CantiereCrewAssignmentDto>? answer;
  final Object? error;
  int calls = 0;

  @override
  Future<List<CantiereCrewAssignmentDto>> getAssegnazioni(String cantiereId) async {
    calls++;
    if (error != null) throw error!;
    return answer ?? const [];
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> seedCrew(String id, String cantiereId, String userId, {bool isLead = false}) =>
      db
          .into(db.cantiereCrewAssignments)
          .insert(
            CantiereCrewAssignmentsCompanion.insert(
              id: id,
              cantiereId: cantiereId,
              userId: userId,
              isLead: Value(isLead),
            ),
          );

  /// A container holding the crew provider alive (it is autoDispose) plus the two inputs it reads.
  ProviderContainer container({
    required bool online,
    required _FakeCrewClient client,
    String? internalUserId = 'u1',
  }) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(online),
        cantiereWorklogApiClientProvider.overrideWithValue(client),
        internalUserIdProvider.overrideWith((ref) async => internalUserId),
      ],
    );
    addTearDown(c.dispose);
    // Keep the autoDispose provider alive for the length of the test.
    final sub = c.listen(cantiereCrewAssignmentsProvider('c1'), (_, _) {});
    addTearDown(sub.close);
    return c;
  }

  test('offline: answers from the mirror without touching the network', () async {
    await seedCrew('a1', 'c1', 'u1', isLead: true);
    await seedCrew('a2', 'c1', 'u2');
    // A row for another cantiere must never leak into this one's answer.
    await seedCrew('a3', 'c2', 'u3', isLead: true);

    final client = _FakeCrewClient(error: StateError('offline: no network call expected'));
    final c = container(online: false, client: client);

    final rows = await c.read(cantiereCrewAssignmentsProvider('c1').future);

    expect(rows.map((r) => r.id), unorderedEquals(['a1', 'a2']));
    expect(rows.firstWhere((r) => r.id == 'a1').isLead, isTrue);
    expect(rows.firstWhere((r) => r.id == 'a2').isLead, isFalse);
    expect(client.calls, 0, reason: 'offline is answered from the mirror, never from the network');
  });

  test('online: the live answer wins over the mirror', () async {
    await seedCrew('a1', 'c1', 'u1', isLead: true);

    final client = _FakeCrewClient(
      answer: const [CantiereCrewAssignmentDto(id: 's1', userId: 'u9', isLead: false)],
    );
    final c = container(online: true, client: client);

    final rows = await c.read(cantiereCrewAssignmentsProvider('c1').future);

    expect(rows.single.id, 's1', reason: 'online this app always shows the latest server data');
    expect(client.calls, 1);
  });

  test('online failure: falls back to the mirror instead of surfacing an error', () async {
    await seedCrew('a1', 'c1', 'u1', isLead: true);

    final client = _FakeCrewClient(
      error: DioException(
        requestOptions: RequestOptions(path: '/api/cantieri/c1/assegnazioni'),
        type: DioExceptionType.connectionError,
      ),
    );
    final c = container(online: true, client: client);

    final rows = await c.read(cantiereCrewAssignmentsProvider('c1').future);

    expect(rows.single.id, 'a1');
    expect(client.calls, 1, reason: 'online the fetch is attempted first');
  });

  test('offline: a mirrored lead reads as lead', () async {
    await seedCrew('a1', 'c1', 'u1', isLead: true);

    final c = container(online: false, client: _FakeCrewClient());
    await c.read(internalUserIdProvider.future);
    await c.read(cantiereCrewAssignmentsProvider('c1').future);

    expect(c.read(isLeadForCantiereProvider('c1')), isTrue);
  });

  test('offline: a mirrored non-lead still reads as not lead', () async {
    await seedCrew('a1', 'c1', 'u1', isLead: false);
    await seedCrew('a2', 'c1', 'u2', isLead: true);

    final c = container(online: false, client: _FakeCrewClient());
    await c.read(internalUserIdProvider.future);
    await c.read(cantiereCrewAssignmentsProvider('c1').future);

    expect(c.read(isLeadForCantiereProvider('c1')), isFalse);
  });

  test('offline with nothing mirrored: not lead, and no network call', () async {
    final client = _FakeCrewClient(error: StateError('offline: no network call expected'));
    final c = container(online: false, client: client);
    await c.read(internalUserIdProvider.future);
    await c.read(cantiereCrewAssignmentsProvider('c1').future);

    expect(c.read(isLeadForCantiereProvider('c1')), isFalse);
    expect(client.calls, 0);
  });
}
