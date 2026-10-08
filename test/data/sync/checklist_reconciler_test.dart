import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/checklist_reconciler.dart';
import 'package:tasktap_mobile/data/sync/checklist_sync_dto.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';

SyncControlGroupDto grp(String id, {String? parent, String name = 'Gruppo', int sort = 0}) =>
    SyncControlGroupDto(
      id: id,
      parentGroupId: parent,
      maintenanceTemplateVersionId: 'v1',
      name: name,
      sortOrder: sort,
    );

SyncTicketControlDto ctl(
  String id, {
  String ticket = 't1',
  String? asset = 'a1',
  String group = 'g1',
  String lineage = 'l1',
  ControlType type = ControlType.checkbox,
  bool required = false,
  String status = 'Pending',
  bool? boolValue,
  String? note,
}) => SyncTicketControlDto(
  id: id,
  ticketId: ticket,
  prodottoAssistenzaId: asset,
  templateControlId: 'tpl-$id',
  controlLineageId: lineage,
  groupId: group,
  label: 'Controllo $id',
  type: type,
  isRequired: required,
  status: status,
  boolValue: boolValue,
  note: note,
);

SyncTicketAssetDto cover(String ticket, String asset, {String? version = 'v1'}) =>
    SyncTicketAssetDto(ticketId: ticket, prodottoAssistenzaId: asset, maintenanceTemplateVersionId: version);

SyncAssetDto asset(String id, {List<String> libretti = const []}) =>
    SyncAssetDto(id: id, name: 'Asset $id', librettoIds: libretti);

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<List<String>> controlIds([String ticket = 't1']) async =>
      ((await (db.select(db.ticketControls)..where((c) => c.ticketId.equals(ticket))).get())
            ..sort((a, b) => a.id.compareTo(b.id)))
          .map((c) => c.id)
          .toList();

  test('stores groups, rows, coverage and assets for an authoritative ticket', () async {
    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t1'},
        controlGroups: [grp('g1')],
        ticketControls: [ctl('c1'), ctl('c2', required: true, type: ControlType.number)],
        ticketAssets: [cover('t1', 'a1')],
        assets: [asset('a1', libretti: ['lib1'])],
      ),
    );

    expect(await controlIds(), ['c1', 'c2']);
    final row = await (db.select(db.ticketControls)..where((c) => c.id.equals('c2'))).getSingle();
    expect((row.type, row.isRequired, row.controlLineageId), ('Number', true, 'l1'));
    expect((await db.select(db.ticketAssets).get()).single.maintenanceTemplateVersionId, 'v1');
    expect((await db.select(db.assets).get()).single.librettoIdsJson, '["lib1"]');
  });

  test('wholesale: a control the server stopped sending is deleted, one it sends is updated', () async {
    final first = ChecklistBatch(
      authoritativeTicketIds: {'t1'},
      controlGroups: [grp('g1')],
      ticketControls: [ctl('c1'), ctl('c2')],
      ticketAssets: [cover('t1', 'a1')],
      assets: [asset('a1')],
    );
    await applyChecklistBatch(db, first);

    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t1'},
        controlGroups: [grp('g1')],
        ticketControls: [ctl('c1', status: 'Completed', boolValue: true)],
        ticketAssets: [cover('t1', 'a1')],
        assets: [asset('a1')],
      ),
    );

    expect(await controlIds(), ['c1']);
    final c1 = await (db.select(db.ticketControls)..where((c) => c.id.equals('c1'))).getSingle();
    expect((c1.status, c1.boolValue), ('Completed', true));
  });

  test('an asset removed from coverage disappears with its coverage row and its identity', () async {
    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t1'},
        controlGroups: [grp('g1')],
        ticketControls: [ctl('c1', asset: 'a1'), ctl('c2', asset: 'a2')],
        ticketAssets: [cover('t1', 'a1'), cover('t1', 'a2')],
        assets: [asset('a1'), asset('a2')],
      ),
    );
    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t1'},
        controlGroups: [grp('g1')],
        ticketControls: [ctl('c1', asset: 'a1')],
        ticketAssets: [cover('t1', 'a1')],
        assets: [asset('a1')],
      ),
    );

    expect((await db.select(db.ticketAssets).get()).map((a) => a.prodottoAssistenzaId), ['a1']);
    expect((await db.select(db.assets).get()).map((a) => a.id), ['a1']);
  });

  test('a ticket that is in the payload with local rows but no rows now is cleared (all assets removed)', () async {
    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t1'},
        controlGroups: [grp('g1')],
        ticketControls: [ctl('c1')],
        ticketAssets: [cover('t1', 'a1')],
        assets: [asset('a1')],
      ),
    );
    final payload = SyncResultDto.fromJson({
      'syncedAt': '2026-10-07T08:00:00Z',
      'tickets': [
        {
          'id': 't1', 'tenantId': 'x', 'createdAt': '2026-10-01T00:00:00Z', 'title': 'T',
          'customerId': 'c', 'locationId': 'l', 'statusId': 1, 'typeId': 1,
        },
      ],
      'ticketControls': <Object>[],
      'ticketAssets': <Object>[],
    });

    await applyChecklistBatch(
      db,
      ChecklistBatch.fromSync(
        payload,
        payloadTicketIds: {'t1'},
        ticketsWithLocalChecklist: await ticketIdsWithLocalChecklist(db),
      ),
    );

    expect(await controlIds(), isEmpty);
    expect(await db.select(db.ticketAssets).get(), isEmpty);
  });

  test('a ticket NOT in the payload is never touched by someone else\'s batch', () async {
    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t2'},
        controlGroups: [grp('g1')],
        ticketControls: [ctl('c9', ticket: 't2')],
        ticketAssets: [cover('t2', 'a1')],
        assets: [asset('a1')],
      ),
    );
    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t1'},
        controlGroups: [grp('g1')],
        ticketControls: [ctl('c1')],
        ticketAssets: [cover('t1', 'a1')],
        assets: [asset('a1')],
      ),
    );
    expect(await controlIds('t2'), ['c9']);
  });

  test('an omitted ticket keeps its rows and is remembered; delivering it later forgets it', () async {
    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t1'},
        controlGroups: [grp('g1')],
        ticketControls: [ctl('c1')],
        ticketAssets: [cover('t1', 'a1')],
        assets: [asset('a1')],
      ),
    );

    await applyChecklistBatch(
      db,
      const ChecklistBatch(authoritativeTicketIds: {}, omittedTicketIds: {'t1', 't2'}),
    );

    expect(await controlIds(), ['c1'], reason: 'nothing implies deletion');
    expect(
      (await db.select(db.checklistOmittedTickets).get()).map((o) => o.ticketId).toSet(),
      {'t1', 't2'},
    );

    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t1'},
        controlGroups: [grp('g1')],
        ticketControls: [ctl('c1'), ctl('c3')],
        ticketAssets: [cover('t1', 'a1')],
        assets: [asset('a1')],
      ),
    );
    expect(
      (await db.select(db.checklistOmittedTickets).get()).map((o) => o.ticketId),
      ['t2'],
    );
  });

  test('remembering an omitted ticket again does not reset its attempt counter', () async {
    await db.into(db.checklistOmittedTickets).insert(
          ChecklistOmittedTicketsCompanion.insert(ticketId: 't1', attempts: const Value(3)),
        );
    await applyChecklistBatch(
      db,
      const ChecklistBatch(authoritativeTicketIds: {}, omittedTicketIds: {'t1'}),
    );
    expect((await db.select(db.checklistOmittedTickets).get()).single.attempts, 3);
  });

  test('a row the server dropped but a local Bozza already answered is retained, not deleted', () async {
    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t1'},
        controlGroups: [grp('g1')],
        ticketControls: [ctl('c1'), ctl('c2')],
        ticketAssets: [cover('t1', 'a1')],
        assets: [asset('a1')],
      ),
    );
    await db.into(db.draftReports).insert(
          DraftReportsCompanion.insert(
            id: 'r1', tenantId: 'x', createdAt: DateTime.utc(2026, 10, 7),
            title: 'T', insertedUserId: 'u', locationId: 'l',
            isLocalOnly: const Value(true),
          ),
        );
    await db.into(db.reportControlli).insert(
          ReportControlliCompanion.insert(
            id: 'ctrl-r1-c2', tenantId: 'x', createdAt: DateTime.utc(2026, 10, 7),
            reportId: 'r1', controlId: 'c2', boolValue: const Value(true),
          ),
        );

    // The office removed the asset: the server now sends neither c1 nor c2.
    await applyChecklistBatch(
      db,
      ChecklistBatch(authoritativeTicketIds: {'t1'}, controlGroups: [grp('g1')]),
    );

    expect(await controlIds(), ['c2'], reason: 'c1 was unanswered and goes; c2 holds a local answer');
    final kept = await (db.select(db.ticketControls)..where((c) => c.id.equals('c2'))).getSingle();
    expect(kept.isRetained, isTrue);
    expect((await db.select(db.assets).get()).map((a) => a.id), ['a1'],
        reason: 'the retained row still needs its asset identity');
  });

  test('groups no row references (nor an ancestor of one) are pruned', () async {
    await applyChecklistBatch(
      db,
      ChecklistBatch(
        authoritativeTicketIds: {'t1'},
        controlGroups: [grp('root'), grp('child', parent: 'root'), grp('unused')],
        ticketControls: [ctl('c1', group: 'child')],
        ticketAssets: [cover('t1', 'a1')],
        assets: [asset('a1')],
      ),
    );
    expect(
      (await db.select(db.controlGroups).get()).map((g) => g.id).toSet(),
      {'root', 'child'},
    );
  });

  test('replaceStrumenti is wholesale and an empty list clears (permission lost)', () async {
    await replaceStrumenti(db, [
      SyncStrumentoDto(id: 's1', name: 'Multimetro', matricola: 'M1', calibrationExpiry: DateTime.utc(2026, 12, 31), isMine: true),
      const SyncStrumentoDto(id: 's2', name: 'Pinza', matricola: 'P1'),
    ]);
    var rows = await db.select(db.strumenti).get();
    expect(rows.map((r) => r.id).toSet(), {'s1', 's2'});
    expect(rows.firstWhere((r) => r.id == 's1').calibrationExpiry, '2026-12-31');

    await replaceStrumenti(db, [const SyncStrumentoDto(id: 's2', name: 'Pinza', matricola: 'P1')]);
    expect((await db.select(db.strumenti).get()).map((r) => r.id), ['s2']);

    await replaceStrumenti(db, const []);
    expect(await db.select(db.strumenti).get(), isEmpty);
  });

  test('server report instruments replace for synced drafts and never touch a local-only draft', () async {
    Future<void> draft(String id, {required bool local}) => db.into(db.draftReports).insert(
          DraftReportsCompanion.insert(
            id: id, tenantId: 'x', createdAt: DateTime.utc(2026, 10, 7), title: 'T',
            insertedUserId: 'u', locationId: 'l', isLocalOnly: Value(local),
          ),
        );
    await draft('synced', local: false);
    await draft('mine', local: true);
    await db.into(db.reportStrumenti).insert(
          ReportStrumentiCompanion.insert(
            id: 'old', reportId: 'synced', name: 'Vecchio', matricola: '0',
          ),
        );
    await db.into(db.reportStrumenti).insert(
          ReportStrumentiCompanion.insert(
            id: 'local-1', reportId: 'mine', name: 'Locale', matricola: '9',
            isLocal: const Value(true),
          ),
        );

    await replaceServerReportStrumenti(
      db,
      reportIdsInPayload: ['synced', 'mine'],
      rows: const [
        SyncReportStrumentoDto(id: 'srv-1', reportId: 'synced', strumentoId: 's1', name: 'Nuovo', matricola: '1'),
        SyncReportStrumentoDto(id: 'srv-2', reportId: 'mine', strumentoId: 's9', name: 'Server', matricola: '2'),
      ],
    );

    final byReport = <String, List<String>>{};
    for (final r in await db.select(db.reportStrumenti).get()) {
      (byReport[r.reportId] ??= []).add(r.id);
    }
    expect(byReport['synced'], ['srv-1'], reason: 'replaced wholesale');
    expect(byReport['mine'], ['local-1'], reason: 'a local-only draft is authoritative');
  });
}
