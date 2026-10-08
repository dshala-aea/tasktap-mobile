import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/checklist_refetch_service.dart';

class MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> ok(Map<String, dynamic> data, String path) =>
    Response(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

/// A checklist-only answer (what Task 0 specifies): every non-checklist collection empty.
Map<String, dynamic> checklistOnly({
  List<Map<String, dynamic>> controls = const [],
  List<Map<String, dynamic>> coverage = const [],
  List<Map<String, dynamic>> assets = const [],
  List<String> omitted = const [],
}) => {
  'syncedAt': '2026-10-07T08:00:00Z',
  'since': null,
  'controlGroups': [
    {'id': 'g1', 'parentGroupId': null, 'maintenanceTemplateVersionId': 'v1', 'name': 'G', 'sortOrder': 0},
  ],
  'ticketControls': controls,
  'ticketAssets': coverage,
  'assets': assets,
  'strumenti': <Object>[],
  'reportStrumenti': <Object>[],
  'checklistTruncated': omitted.isNotEmpty,
  'checklistOmittedTicketIds': omitted,
};

Map<String, dynamic> row(String id, String ticket) => {
  'id': id, 'ticketId': ticket, 'prodottoAssistenzaId': 'a-$ticket', 'templateControlId': 'tc-$id',
  'controlLineageId': 'l1', 'groupId': 'g1', 'label': 'Controllo $id', 'description': null,
  'type': 'Checkbox', 'isRequired': false, 'options': null, 'sortOrder': 0, 'status': 'Pending',
  'stringValue': null, 'boolValue': null, 'dateValue': null, 'numberValue': null, 'note': null,
};

Map<String, dynamic> cover(String ticket) => {
  'ticketId': ticket, 'prodottoAssistenzaId': 'a-$ticket', 'controllato': false, 'note': null,
  'maintenanceTemplateVersionId': 'v1',
};

Map<String, dynamic> assetJson(String ticket) => {
  'id': 'a-$ticket', 'name': 'Asset $ticket', 'serialNumber': null, 'matricola': null,
  'librettoIds': <String>[],
};

void main() {
  late AppDatabase db;
  late MockDio dio;
  late ChecklistRefetchService service;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    dio = MockDio();
    service = ChecklistRefetchService(db: db, dio: dio);
  });
  tearDown(() => db.close());

  Future<void> omit(String id, {int attempts = 0}) => db.into(db.checklistOmittedTickets).insert(
        ChecklistOmittedTicketsCompanion.insert(ticketId: id, attempts: Value(attempts)),
      );

  /// Answers the n-th call with the n-th body and records the requested id lists.
  List<List<String>> script(List<Map<String, dynamic>> bodies) {
    final asked = <List<String>>[];
    when(() => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((inv) async {
      final q = inv.namedArguments[#queryParameters] as Map<String, dynamic>;
      asked.add((q['checklistTicketIds'] as List).cast<String>());
      final i = asked.length - 1;
      return ok(bodies[i < bodies.length ? i : bodies.length - 1], '/api/sync/mobile');
    });
    return asked;
  }

  test('asks for the omitted ids with a repeated parameter: one probe first, then a batch', () async {
    await omit('t1');
    await omit('t2');
    await omit('t3');
    final asked = script([
      checklistOnly(controls: [row('c1', 't1')], coverage: [cover('t1')], assets: [assetJson('t1')]),
      checklistOnly(
        controls: [row('c2', 't2')],
        coverage: [cover('t2')],
        assets: [assetJson('t2')],
        omitted: ['t3'],
      ),
    ]);

    await service.refetchOmitted();

    expect(asked.first, hasLength(1), reason: 'the first request is a one-id probe');
    expect(asked[1].toSet(), {'t2', 't3'});
    expect((await db.select(db.ticketControls).get()).map((c) => c.ticketId).toSet(), {'t1', 't2'});
    // t3 was omitted again: still remembered, with one more attempt on record.
    final left = await db.select(db.checklistOmittedTickets).get();
    expect(left.map((o) => (o.ticketId, o.attempts)), [('t3', 1)]);
  });

  test('a ticket the server omits again keeps the rows it already had', () async {
    await omit('t1');
    await db.into(db.ticketControls).insert(
          TicketControlsCompanion.insert(
            id: 'old', ticketId: 't1', templateControlId: 'x', controlLineageId: 'l1',
            groupId: 'g1', label: 'Vecchio', type: 'Checkbox',
          ),
        );
    script([checklistOnly(omitted: ['t1'])]);

    await service.refetchOmitted();

    expect((await db.select(db.ticketControls).get()).map((c) => c.id), ['old']);
  });

  test('stops asking once a ticket has used its attempts', () async {
    await omit('t1', attempts: 5);
    final asked = script([checklistOnly()]);

    await service.refetchOmitted();

    expect(asked, isEmpty);
  });

  test('a requested ticket the server returns nothing for (empty checklist) is settled, not retried forever', () async {
    await omit('t1');
    script([checklistOnly()]);
    await service.refetchOmitted();
    expect(await db.select(db.checklistOmittedTickets).get(), isEmpty);
  });

  test('a backend that ignores the parameter (answers with the regular delta) disables the batched path', () async {
    await omit('t1');
    final asked = script([
      {
        ...checklistOnly(),
        'tickets': [
          {
            'id': 'other', 'tenantId': 'x', 'createdAt': '2026-10-01T00:00:00Z', 'title': 'T',
            'customerId': 'c', 'locationId': 'l', 'statusId': 1, 'typeId': 1,
          },
        ],
      },
    ]);

    await service.refetchOmitted();
    await service.refetchOmitted();

    expect(service.batchedUnsupported, isTrue);
    expect(asked, hasLength(1), reason: 'one probe per app session, never a loop');
    expect(await db.select(db.ticketControls).get(), isEmpty, reason: 'the ignored answer is not applied');
    expect((await db.select(db.checklistOmittedTickets).get()).single.attempts, 0);
  });

  test('bounded: at most 4 requests per call (1 probe + 3 batches of 50)', () async {
    for (var i = 0; i < 400; i++) {
      await omit('t${i.toString().padLeft(3, '0')}');
    }
    final asked = script([checklistOnly()]);

    await service.refetchOmitted();

    expect(asked, hasLength(4));
    expect(asked.map((a) => a.length), [1, 50, 50, 50]);
    expect((await db.select(db.checklistOmittedTickets).get()), hasLength(400 - 151));
  });

  group('per-ticket REST backfill (works without the backend parameter)', () {
    test('writes templated assets, a legacy asset and the libretto identity, and clears the omitted record', () async {
      await omit('t1');
      when(() => dio.get<Map<String, dynamic>>('/api/tickets/t1/controls')).thenAnswer(
        (_) async => ok({
          'groups': [
            {
              'id': 'tg', 'name': 'Ticket', 'description': null, 'sortOrder': 0, 'subgroups': <Object>[],
              'controls': [
                {
                  'id': 'tc1', 'templateControlId': 'tt1', 'controlLineageId': 'lt1', 'label': 'Foto',
                  'description': null, 'type': 'Text', 'isRequired': false, 'options': null,
                  'valoreLimite': null, 'sortOrder': 0, 'status': 'Pending', 'stringValue': null,
                  'boolValue': null, 'dateValue': null, 'numberValue': null, 'completedByReportId': null,
                  'completedAt': null, 'note': null, 'prodottoAssistenzaId': null,
                },
              ],
            },
          ],
          'assetProgress': [
            {'prodottoAssistenzaId': 'legacy', 'prodottoAssistenzaName': 'Vecchio', 'controllato': true, 'note': 'ok'},
          ],
          'assetChecklists': [
            {
              'prodottoAssistenzaId': 'child', 'name': 'Caldaia 1', 'matricola': 'M-1',
              'librettoId': 'lib', 'librettoName': 'Libretto Nord', 'maintenanceTemplateVersionId': 'v7',
              'groups': [
                {
                  'id': 'ag', 'name': 'Sicurezza', 'description': null, 'sortOrder': 0, 'subgroups': <Object>[],
                  'controls': [
                    {
                      'id': 'ac1', 'templateControlId': 'at1', 'controlLineageId': 'la1',
                      'label': 'Valvola chiusa', 'description': null, 'type': 'Checkbox', 'isRequired': true,
                      'options': null, 'valoreLimite': null, 'sortOrder': 0, 'status': 'Completed',
                      'stringValue': null, 'boolValue': true, 'dateValue': null, 'numberValue': null,
                      'completedByReportId': null, 'completedAt': null, 'note': 'ok', 'prodottoAssistenzaId': 'child',
                    },
                  ],
                },
              ],
            },
          ],
        }, '/api/tickets/t1/controls'),
      );

      await service.backfillTicket('t1');

      final controls = await db.select(db.ticketControls).get();
      final asset = controls.singleWhere((c) => c.id == 'ac1');
      expect((asset.prodottoAssistenzaId, asset.controlLineageId, asset.boolValue, asset.note, asset.isRequired),
          ('child', 'la1', true, 'ok', true));
      expect(controls.singleWhere((c) => c.id == 'tc1').prodottoAssistenzaId, isNull);

      final coverage = {
        for (final a in await db.select(db.ticketAssets).get()) a.prodottoAssistenzaId: a,
      };
      expect(coverage['child']!.maintenanceTemplateVersionId, 'v7');
      expect((coverage['legacy']!.maintenanceTemplateVersionId, coverage['legacy']!.controllato, coverage['legacy']!.note),
          (null, true, 'ok'));

      final assets = {for (final a in await db.select(db.assets).get()) a.id: a};
      expect(assets['child']!.matricola, 'M-1');
      expect(assets['child']!.librettoIdsJson, '["lib"]');
      expect(assets['lib']!.name, 'Libretto Nord');
      expect(await db.select(db.checklistOmittedTickets).get(), isEmpty);
    });

    test('a failure is rethrown and nothing is written', () async {
      when(() => dio.get<Map<String, dynamic>>('/api/tickets/t1/controls')).thenThrow(
        DioException(requestOptions: RequestOptions(path: '/api/tickets/t1/controls'), type: DioExceptionType.connectionError),
      );
      await expectLater(service.backfillTicket('t1'), throwsA(isA<DioException>()));
      expect(await db.select(db.ticketControls).get(), isEmpty);
    });
  });
}
