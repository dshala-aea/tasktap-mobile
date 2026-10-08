// dart format width=100
// test/data/reference/reference_search_client_test.dart
//
// Covers ReferenceSearchClient — the online half of every reference picker. Two things are under
// test here and they are not the same thing: that a search asks the right question of the right
// endpoint, and that whatever it hands back is already readable from the local mirror.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reference/reference_cache_repository.dart';
import 'package:tasktap_mobile/data/reference/reference_option.dart';
import 'package:tasktap_mobile/data/reference/reference_search_client.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';

/// There is no `ApiClient` class in this repo — every client takes a bare [Dio] and each has its
/// own `_MockDio`. Follow `test/features/ticket/ticket_api_client_test.dart` verbatim.
class _MockDio extends Mock implements Dio {}

void main() {
  late AppDatabase db;
  late _MockDio dio;
  late ReferenceSearchClient client;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    dio = _MockDio();
    client = ReferenceSearchClient(dio, ReferenceCacheRepository(db));
  });
  tearDown(() => db.close());

  Map<String, dynamic> contractJson(String id) => {
    'id': id,
    'tenantId': 't',
    'createdAt': '2026-10-01T00:00:00Z',
    'updatedAt': null,
    'name': 'Manutenzione $id',
    'customerId': 'cu',
    'locationId': null,
    'startDate': '2026-01-01T00:00:00Z',
    'endDate': null,
    'isActive': true,
    'numero': 'N-$id',
    'codice': null,
    'tipo': 0,
    'externalId': null,
  };

  /// A paginated envelope, the shape every mobile client already unwraps with [pagedItems].
  Response<Map<String, dynamic>> ok(Map<String, dynamic> body) => Response(
    requestOptions: RequestOptions(path: '/api/contracts'),
    statusCode: 200,
    data: body,
  );

  Map<String, dynamic> agentJson(String id) => {
    'id': id,
    'tenantId': 't',
    'createdAt': '2026-10-01T00:00:00Z',
    'updatedAt': null,
    'nome': 'Agente $id',
    'email': null,
    'cellulare': null,
    'isActive': true,
  };

  /// The D-1(a) invariant, as a test: what a search hands the widget is readable from the mirror
  /// at the moment it is handed over. If this ever fails, a technician can pick a row the ticket
  /// write will then be rejected for.
  test('every option a search returns is already in the local mirror', () async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/contracts',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => ok({
        'items': [contractJson('c1'), contractJson('c2')],
      }),
    );

    final options = await client.searchContracts(customerId: 'cu', query: 'manu');

    expect(options.map((o) => o.id), containsAll(['c1', 'c2']));
    final cached = await ReferenceCacheRepository(db).contractsForCustomer('cu');
    expect(
      cached.map((r) => r.id),
      containsAll(options.map((o) => o.id)),
      reason: 'a pick must never reference a row the mirror lacks',
    );
  });

  test('the customer scope is sent to the server, so a search cannot widen D-1(a)', () async {
    when(
      () => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => ok({'items': <Object>[]}));

    await client.searchContracts(customerId: 'cu', query: 'x');

    final params =
        verify(
              () => dio.get<Map<String, dynamic>>(
                '/api/contracts',
                queryParameters: captureAny(named: 'queryParameters'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(params['customerId'], 'cu');
    expect(params['q'], 'x');
  });

  test('label falls back to codice when a contract has no numero', () {
    ContractSyncDto contract({String? numero, String? codice}) => ContractSyncDto(
      id: 'c1',
      tenantId: 't',
      createdAt: DateTime.utc(2026, 10, 1),
      name: 'Manutenzione caldaie',
      customerId: 'cu',
      startDate: DateTime.utc(2026, 1, 1),
      numero: numero,
      codice: codice,
    );

    expect(ReferenceOption.contract(contract(numero: 'N-1')).subtitle, 'N-1');
    expect(
      ReferenceOption.contract(contract(codice: 'EXT-9')).subtitle,
      'EXT-9',
      reason: 'a technician reads whichever is printed on the paper contract',
    );
    expect(ReferenceOption.contract(contract()).subtitle, isNull);
  });

  /// Offline is the normal case for this feature, not an exceptional one: dio throws, and the
  /// picker falls back to the mirror, which is the offline answer anyway.
  test('an offline search returns empty, never throws', () async {
    when(
      () => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/contracts'),
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(client.searchContracts(customerId: 'cu', query: 'x'), completion(isEmpty));
  });

  /// A 403 on `/api/agents` is the designed answer for a technician without `ClientiAgentRead`,
  /// not a failure: the picker then shows the agents mirrored from their own tickets.
  test('a refused agents search reads as an empty result, not as an error', () async {
    when(
      () => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/agents'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/agents'),
          statusCode: 403,
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(client.searchAgents(query: 'x'), completion(isEmpty));
  });

  test('an agents search still writes what it found into the mirror', () async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/agents',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => ok({
        'items': [agentJson('a1')],
      }),
    );

    final options = await client.searchAgents(query: 'age');

    expect(options.single.id, 'a1');
    expect(options.single.label, 'Agente a1');
    expect((await ReferenceCacheRepository(db).activeAgents()).map((a) => a.id), ['a1']);
  });

  test('an agents search sends no customer scope — agents are not a customer list', () async {
    when(
      () => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => ok({'items': <Object>[]}));

    await client.searchAgents(query: 'x');

    final params =
        verify(
              () => dio.get<Map<String, dynamic>>(
                '/api/agents',
                queryParameters: captureAny(named: 'queryParameters'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(params.containsKey('customerId'), isFalse);
    expect(params['q'], 'x');
  });

  /// The endpoint is singular — `[Route("api/[controller]")]` over `ProdottoAssistenzaController`.
  /// A plural here would 404 and the picker would silently show the mirror forever.
  test('the products endpoint is the singular /api/prodottoassistenza', () async {
    when(
      () => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer(
      (_) async => ok({
        'items': [
          {
            'id': 'p1',
            'tenantId': 't',
            'createdAt': '2026-10-01T00:00:00Z',
            'updatedAt': null,
            'name': 'Caldaia Nord',
            'customerId': 'cu',
            'locationId': 'l1',
            'isActive': true,
            'codice': null,
            'serialNumber': 'SN-1',
            'categoria': null,
            'marchio': null,
            'externalId': null,
          },
        ],
      }),
    );

    final options = await client.searchProdottiAssistenza(customerId: 'cu', query: 'cal');

    verify(
      () => dio.get<Map<String, dynamic>>(
        '/api/prodottoassistenza',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).called(1);
    expect(options.single.subtitle, 'SN-1');
    expect((await ReferenceCacheRepository(db).prodottiForCustomer('cu')).map((p) => p.id), ['p1']);
  });
}
